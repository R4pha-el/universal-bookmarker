import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleAccountAction} from '../functions/_shared/account-service.ts';

const user='11111111-1111-4111-8111-111111111111';
const configuration={url:'https://example.supabase.co',serviceKey:'test-service-key'};
const response=(value,status=200)=>new Response(JSON.stringify(value),{status});

test('account action rejects a missing bearer before contacting services',async()=>{
 let calls=0;
 const result=await handleAccountAction(new Request('https://app.test',{method:'POST'}),'delete',configuration,async()=>{calls++;return response({});});
 assert.equal(result.status,401); assert.equal(calls,0);
});
test('delete uses verified account identity, freezes writes, removes originals then deletes auth user',async()=>{
 const paths=[];let listCount=0;
 const fake=async(url,options={})=>{
  paths.push([String(url),options]);
  if(String(url).endsWith('/auth/v1/user')) return response({id:user});
  if(String(url).endsWith('/rpc/begin_account_deletion')) return response(null);
  if(String(url).includes('/object/list/')) return response(listCount++===0?[{name:'original.pdf',id:'object-id'}]:[]);
  return response({});
 };
 const req=new Request('https://app.test',{method:'POST',headers:{authorization:'Bearer test-user-token'},body:JSON.stringify({userID:'attacker-selected-id'})});
 const result=await handleAccountAction(req,'delete',configuration,fake);
 assert.equal(result.status,200);
 assert.ok(paths[1][0].endsWith('/rpc/begin_account_deletion'));
 const deletion=paths.find(([url,options])=>url.endsWith('/storage/v1/object/originals')&&options.method==='DELETE');
 assert.deepEqual(JSON.parse(deletion[1].body).prefixes,[`${user}/original.pdf`]);
 assert.ok(paths.at(-1)[0].endsWith('/auth/v1/admin/users/'+user));
 assert.ok(paths.every(([url])=>!url.includes('attacker-selected-id')));
});
test('failed original cleanup keeps the account and returns a retryable failure',async()=>{
 let removedAccount=false;
 const fake=async(url)=>{
  if(String(url).endsWith('/auth/v1/user'))return response({id:user});
  if(String(url).endsWith('/rpc/begin_account_deletion'))return response(null);
  if(String(url).includes('/object/list/'))return response({error:'unavailable'},503);
  if(String(url).includes('/admin/users/'))removedAccount=true;
  return response({});
 };
 const result=await handleAccountAction(new Request('https://app.test',{method:'POST',headers:{authorization:'Bearer test-user-token'}}),'delete',configuration,fake);
 assert.equal(result.status,502);assert.equal(removedAccount,false);
});
