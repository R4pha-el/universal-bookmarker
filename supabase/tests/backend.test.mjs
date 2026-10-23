import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

const db = new PGlite();
const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
let sequence = 0;
const uuid = () => `00000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`;
async function as(user = A) {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user]);
  await db.exec('set role authenticated');
}
const operation = (entity, id, expectedVersion, payload = {}, action = 'upsert') => ({
  operationID: uuid(), entity, id, expectedVersion, payload, action
});
async function apply(op) { return (await db.query('select public.apply_operation($1::jsonb) result', [JSON.stringify(op)])).rows[0].result; }
async function changes(cursor = 0, size = 200) { return (await db.query('select public.library_changes($1, $2) result', [cursor, size])).rows[0].result; }
const link = (title = 'A link') => ({title, kind: 'link', url: 'https://example.com', note: ''});
before(async () => {
  await db.exec(await readFile(new URL('fixtures.sql', import.meta.url), 'utf8'));
  const migrations = new URL('../migrations/', import.meta.url);
  for (const file of (await readdir(migrations)).filter(f => f.endsWith('.sql')).sort()) {
    try { await db.exec(await readFile(new URL(file, migrations), 'utf8')); }
    catch (error) { throw new Error(`${file}: ${error.message}`); }
  }
  await as();
});
after(() => db.close());

test('metadata RPC exists, creates and idempotently replays exactly one revision', async () => {
  await as(); const op = operation('item', uuid(), 0, link());
  const first = await apply(op); assert.equal(first.status, 'applied'); assert.equal(first.record.version, 1);
  assert.deepEqual(await apply(op), first);
  assert.equal((await changes()).changes.filter(c => c.id === op.id).length, 1);
  assert.equal((await apply({...op, payload: link('changed')})).code, 'idempotency_mismatch');
});
test('RLS hides other account rows and rejects direct writes and foreign collection references', async () => {
  await as(A); const collectionID = uuid(); await apply(operation('collection', collectionID, 0, {name:'Private', tint:'blue'}));
  const id = uuid(); await apply(operation('item', id, 0, link()));
  await as(B);
  assert.equal((await db.query('select * from public.items where id=$1', [id])).rows.length, 0);
  assert.equal((await changes()).changes.length, 0);
  assert.equal((await apply(operation('item', uuid(), 0, {...link(), collectionID}))).code, 'collection_unavailable');
  await assert.rejects(db.query("insert into public.collections(id, owner_id, name) values($1,$2,'hack')", [uuid(), B]), /permission denied|row-level security/);
  assert.equal((await apply(operation('item', id, 0, link('stolen')))).code, 'id_unavailable');
  await as(A); assert.equal((await db.query('select title from public.items where id=$1',[id])).rows[0].title, 'A link');
});
test('stale versions conflict; tombstones never resurrect and conflict replay is stable', async () => {
  await as(); const id=uuid(); await apply(operation('item',id,0,link()));
  const stale=operation('item',id,0,link('offline')); const conflict=await apply(stale);
  assert.equal(conflict.status,'conflict'); assert.equal(conflict.record.version,1);
  const deletion=await apply(operation('item',id,1,{},'delete')); assert.equal(deletion.record.version,2); assert.ok(deletion.record.deletedAt);
  assert.deepEqual(await apply(stale),conflict);
  assert.equal((await apply(operation('item',id,2,link('resurrect')))).code,'deleted');
});
test('collection deletion preserves items, bumps versions, and pages every ordered change', async () => {
  await as(); const collectionID=uuid(); await apply(operation('collection',collectionID,0,{name:'Folder',tint:'mint'}));
  const id=uuid(); await apply(operation('item',id,0,{...link(),collectionID}));
  const result=await apply(operation('collection',collectionID,1,{},'delete')); assert.equal(result.status,'applied');
  const row=(await db.query('select * from public.items where id=$1',[id])).rows[0];
  assert.equal(row.collection_id,null); assert.equal(row.version,2); assert.equal(row.deleted_at,null);
  const offline=await apply(operation('item',id,2,{...link('retained edit'),collectionID}));
  assert.equal(offline.status,'applied'); assert.equal(offline.record.collectionID,null); assert.deepEqual(offline.warnings,['collection_removed']);
  const all=(await changes()).changes; const paged=[]; let cursor=0; let page;
  do { page=await changes(cursor,2); paged.push(...page.changes); assert.ok(page.nextRevision>=cursor); cursor=page.nextRevision; } while(page.hasMore);
  assert.deepEqual(paged,all); assert.ok(all.every((c,i)=>i===0 || c.revision>all[i-1].revision));
  const related=all.filter(c=>c.id===id || c.id===collectionID); assert.ok(related.findIndex(c=>c.id===id && c.record.version===2)<related.findIndex(c=>c.id===collectionID && c.record.deletedAt));
});
test('validates shape, kind, URL, byte limit, absent originals and immutable attachment', async () => {
  await as();
  for (const payload of [{...link(),url:'javascript:alert(1)'},{...link(),kind:'exe'},{...link(),title:''}]) assert.equal((await apply(operation('item',uuid(),0,payload))).code,'invalid_payload');
  const id=uuid(), attachmentID=uuid(), path=`${A}/${id}/${attachmentID}`, sha256='a'.repeat(64);
  const payload={title:'Photo',kind:'photo',filename:'photo.png',contentType:'image/png',byteCount:12,attachmentID,storagePath:path,sha256};
  assert.equal((await apply(operation('item',id,0,payload))).code,'original_missing');
  await db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',['originals',path,{size:12},{sha256}]);
  const saved=await apply(operation('item',id,0,payload)); assert.equal(saved.status,'applied');
  assert.equal((await apply(operation('item',id,1,{...payload,sha256:'b'.repeat(64)}))).code,'immutable_original');
  assert.equal((await apply(operation('item',uuid(),0,{...payload,byteCount:26214401}))).code,'invalid_payload');
});
test('originals are private, owner scoped, create-only, with path and byte checks', async () => {
  await as(A); const path=`${A}/${uuid()}/${uuid()}`;
  await db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',['originals',path,{size:5},{sha256:'a'.repeat(64)}]);
  assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,1);
  assert.equal((await db.query('update storage.objects set metadata=$1 where name=$2 returning *',[{size:9},path])).rows.length,0);
  assert.equal((await db.query('delete from storage.objects where name=$1 returning *',[path])).rows.length,0);
  await assert.rejects(db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',['originals',`${A}/${uuid()}/${uuid()}`,{size:26214401},{sha256:'a'.repeat(64)}]),/row-level security/);
  await as(B); assert.equal((await db.query('select * from storage.objects where name=$1',[path])).rows.length,0);
  await assert.rejects(db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',['originals',path,{size:5},{sha256:'a'.repeat(64)}]),/row-level security/);
});
test('anonymous RPC and non-owner history are unavailable', async()=>{
  await as(''); await assert.rejects(changes(),/authentication_required/);
  await db.exec('set role anon'); await assert.rejects(changes(),/permission denied/);
  await as();
});

test('malformed operations and link attachment injection are rejected without publishing',async()=>{
 await as();
 for(const op of [
  {...operation('item',uuid(),0,link()),entity:null},
  {...operation('item',uuid(),0,link()),action:null},
  operation('item',uuid(),0,{...link(),createdAt:'not-a-date'}),
  operation('item',uuid(),0,{...link(),title:123}),
  operation('item',uuid(),0,{...link(),attachmentID:uuid(),storagePath:`${B}/${uuid()}/${uuid()}`,sha256:'a'.repeat(64)})
 ]) {
  const outcome=await apply(op);assert.equal(outcome.status,'rejected');
  assert.equal((await changes()).changes.some(change=>change.id===op.id),false);
 }
});

test('storage authorization accepts Supabase probe metadata before finalized size exists',async()=>{
 await as(A);
 await db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',[
  'originals',`${A}/${uuid()}/${uuid()}`,{contentLength:5,mimetype:'image/png',contentEncoding:'identity'},{sha256:'a'.repeat(64)}
 ]);
});

test('a conflicting owner inserted between absence check and insert cannot be overwritten',async()=>{
 // PGlite has one connection. A BEFORE INSERT trigger exercises the precise
 // interleaving produced by another account committing before ON CONFLICT.
 for(const entity of ['collection','item']) {
  const id=uuid(),table=entity==='item'?'items':'collections';
  await db.exec('reset role');
  const insert=entity==='item'
   ? `insert into public.items(id,owner_id,title,kind,url) values(new.id,'${B}','Private owner B','link','https://private.example')`
   : `insert into public.collections(id,owner_id,name) values(new.id,'${B}','Private owner B')`;
  await db.exec(`create function public.test_interleaving() returns trigger language plpgsql as $$ begin if new.id='${id}' and new.owner_id='${A}' then ${insert}; end if; return new; end $$; create trigger test_interleaving before insert on public.${table} for each row execute function public.test_interleaving();`);
  await as(A);
  const outcome=await apply(operation(entity,id,0,entity==='item'?link():{name:'Account A',tint:'blue'}));
  assert.equal(outcome.code,'id_unavailable');assert.equal(outcome.record,undefined);
  assert.equal((await changes()).changes.some(change=>change.id===id),false);
  await db.exec('reset role');
  assert.equal((await db.query(`select owner_id from public.${table} where id=$1`,[id])).rows[0].owner_id,B);
  await db.exec(`drop trigger test_interleaving on public.${table}; drop function public.test_interleaving()`);
 }
});

test('account deletion freezes writes and auth removal cascades private records',async()=>{
 await as();
 await db.query('select public.begin_account_deletion()');
 assert.equal((await apply(operation('item',uuid(),0,link()))).code,'account_deleting');
 await assert.rejects(db.query('insert into storage.objects(bucket_id,name,metadata,user_metadata) values($1,$2,$3,$4)',['originals',`${A}/${uuid()}/${uuid()}`,{size:5},{sha256:'a'.repeat(64)}]),/row-level security/);
 await db.exec('reset role');
 await db.query('delete from auth.users where id=$1',[A]);
 assert.equal((await db.query('select * from public.items where owner_id=$1',[A])).rows.length,0);
 assert.equal((await db.query('select * from public.collections where owner_id=$1',[A])).rows.length,0);
});
