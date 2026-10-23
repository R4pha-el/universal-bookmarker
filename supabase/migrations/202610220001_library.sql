-- Private metadata and a commit-ordered per-account change stream.
create table public.user_revisions (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 revision bigint not null default 0
);
create table public.collections (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 name text not null, tint text not null default 'blue', version bigint not null default 1,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create table public.items (
 id uuid primary key, owner_id uuid not null references auth.users(id) on delete cascade,
 title text not null, kind text not null check(kind in ('link','photo','pdf','file')),
 url text, filename text, content_type text, byte_count bigint, note text not null default '',
 collection_id uuid references public.collections(id), attachment_id uuid, storage_path text, sha256 text,
 version bigint not null default 1, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index items_owner_created on public.items(owner_id,created_at desc);
create table public.operation_receipts (
 owner_id uuid not null references auth.users(id) on delete cascade, operation_id uuid not null,
 request jsonb not null, response jsonb not null, primary key(owner_id,operation_id)
);
create table public.library_change_log (
 owner_id uuid not null references auth.users(id) on delete cascade,
 revision bigint not null, entity text not null, entity_id uuid not null, record jsonb not null,
 primary key(owner_id,revision)
);
create table public.original_cleanup_jobs (
 owner_id uuid not null references auth.users(id) on delete cascade,
 storage_path text primary key, created_at timestamptz not null default now()
);
create table public.account_deletions (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 requested_at timestamptz not null default now()
);
alter table public.user_revisions enable row level security;
alter table public.collections enable row level security;
alter table public.items enable row level security;
alter table public.operation_receipts enable row level security;
alter table public.library_change_log enable row level security;
alter table public.original_cleanup_jobs enable row level security;
alter table public.account_deletions enable row level security;
create policy own_items on public.items for select to authenticated using(owner_id=auth.uid());
create policy own_collections on public.collections for select to authenticated using(owner_id=auth.uid());
create policy own_cleanup_jobs on public.original_cleanup_jobs for select to authenticated using(owner_id=auth.uid());
revoke all on public.user_revisions,public.collections,public.items,public.operation_receipts,public.library_change_log,public.original_cleanup_jobs,public.account_deletions from anon,authenticated;
grant select on public.items,public.collections,public.original_cleanup_jobs to authenticated;
grant all on public.user_revisions,public.collections,public.items,public.operation_receipts,public.library_change_log,public.original_cleanup_jobs,public.account_deletions to service_role;

create function public.item_json(record_value public.items) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object('id',record_value.id,'ownerID',record_value.owner_id,'title',record_value.title,'kind',record_value.kind,'url',record_value.url,
 'filename',record_value.filename,'contentType',record_value.content_type,'byteCount',record_value.byte_count,'note',record_value.note,
 'collectionID',record_value.collection_id,'attachmentID',record_value.attachment_id,'storagePath',record_value.storage_path,'sha256',record_value.sha256,
 'version',record_value.version,'createdAt',record_value.created_at,'updatedAt',record_value.updated_at,'deletedAt',record_value.deleted_at)
$$;
create function public.collection_json(record_value public.collections) returns jsonb language sql stable set search_path=public,pg_temp as $$
 select jsonb_build_object('id',record_value.id,'ownerID',record_value.owner_id,'name',record_value.name,'tint',record_value.tint,
 'version',record_value.version,'createdAt',record_value.created_at,'updatedAt',record_value.updated_at,'deletedAt',record_value.deleted_at)
$$;
create function public.append_library_change(owner uuid,kind text,target uuid,value jsonb) returns bigint
language plpgsql set search_path=public,pg_temp as $$
 declare next_revision bigint;
 begin
  update public.user_revisions set revision=revision+1 where owner_id=owner returning revision into next_revision;
  insert into public.library_change_log values(owner,next_revision,kind,target,value);
  return next_revision;
 end
$$;
revoke all on function public.item_json(public.items),public.collection_json(public.collections),public.append_library_change(uuid,text,uuid,jsonb) from public,anon,authenticated;

create function public.apply_operation(operation jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
 owner uuid:=auth.uid(); op_id uuid; target uuid; expected bigint; entity text; action text;
 p jsonb; prior public.operation_receipts; item public.items; folder public.collections;
 referenced public.collections; existing boolean; response jsonb; value jsonb; rev bigint;
 cid uuid; aid uuid; path text; hash text; bytes bigint; submitted_at timestamptz; warning jsonb:='[]';
begin
 if owner is null then raise exception 'authentication_required' using errcode='42501'; end if;
 if not exists(select 1 from auth.users where id=owner) then raise exception 'authentication_required' using errcode='42501'; end if;
 begin
  op_id:=(operation->>'operationID')::uuid; target:=(operation->>'id')::uuid;
  expected:=(operation->>'expectedVersion')::bigint; entity:=operation->>'entity'; action:=operation->>'action'; p:=coalesce(operation->'payload','{}');
  if op_id is null or target is null or expected is null or expected<0 or coalesce(entity,'') not in ('item','collection') or coalesce(action,'') not in ('upsert','delete') or jsonb_typeof(p) is distinct from 'object' then raise invalid_parameter_value; end if;
 exception when invalid_text_representation or invalid_parameter_value or numeric_value_out_of_range then
  return jsonb_build_object('status','rejected','code','invalid_operation');
 end;
 insert into public.user_revisions(owner_id) values(owner) on conflict do nothing;
 -- Held until RPC commit: later revisions cannot commit before this operation.
 perform 1 from public.user_revisions where owner_id=owner for update;
 if exists(select 1 from public.account_deletions where owner_id=owner) then return jsonb_build_object('status','rejected','code','account_deleting'); end if;
 select * into prior from public.operation_receipts where owner_id=owner and operation_id=op_id;
 if found then
  if prior.request=operation then return prior.response; end if;
  return jsonb_build_object('status','rejected','code','idempotency_mismatch');
 end if;
 response:=null;
 if entity='item' then
  select * into item from public.items where id=target; existing:=found;
  if existing and item.owner_id<>owner then response:=jsonb_build_object('status','rejected','code','id_unavailable');
  elsif existing and (item.version<>expected or (action='upsert' and item.deleted_at is not null)) then response:=jsonb_build_object('status','conflict','code',case when item.deleted_at is not null then 'deleted' else 'version_conflict' end,'record',public.item_json(item));
  elsif not existing and (expected<>0 or action='delete') then response:=jsonb_build_object('status','rejected','code','not_found');
  elsif action='delete' then
   update public.items set deleted_at=coalesce(deleted_at,now()),updated_at=now(),version=version+1 where id=target returning * into item;
   if item.storage_path is not null then insert into public.original_cleanup_jobs(owner_id,storage_path) values(owner,item.storage_path) on conflict do nothing; end if;
   value:=public.item_json(item);
  else
   begin
    bytes:=nullif(p->>'byteCount','')::bigint; cid:=nullif(p->>'collectionID','')::uuid;
    aid:=nullif(p->>'attachmentID','')::uuid; path:=p->>'storagePath'; hash:=p->>'sha256';
    submitted_at:=coalesce((p->>'createdAt')::timestamptz,now());
    if jsonb_typeof(p->'title') is distinct from 'string' or coalesce(length(trim(p->>'title')),0) not between 1 and 500 or coalesce(length(p->>'note'),0)>10000
      or coalesce(p->>'kind','') not in ('link','photo','pdf','file')
      or (p->>'kind'='link' and coalesce(p->>'url','') !~* '^https?://[^[:space:]/?#@]+([/?#][^[:space:]]*)?$')
      or (p->>'kind'='link' and (aid is not null or path is not null or hash is not null or bytes is not null))
      or (p->>'kind'<>'link' and (jsonb_typeof(p->'filename') is distinct from 'string' or coalesce(length(p->>'filename'),0) not between 1 and 255 or coalesce(length(p->>'contentType'),0) not between 1 and 150))
      or (p->>'kind'<>'link' and (bytes is null or bytes<0 or bytes>26214400 or aid is null or hash !~ '^[a-f0-9]{64}$' or hash is null or path is null or path<>owner::text||'/'||target::text||'/'||aid::text)) then
      response:=jsonb_build_object('status','rejected','code','invalid_payload');
    end if;
   exception when invalid_text_representation or numeric_value_out_of_range or invalid_datetime_format or datetime_field_overflow then response:=jsonb_build_object('status','rejected','code','invalid_payload'); end;
   if response is null and cid is not null then
    select * into referenced from public.collections where id=cid;
    if not found or referenced.owner_id<>owner then response:=jsonb_build_object('status','rejected','code','collection_unavailable');
    elsif referenced.deleted_at is not null then cid:=null; warning:='["collection_removed"]'; end if;
   end if;
   if response is null and existing and item.storage_path is not null and (item.storage_path is distinct from path or item.attachment_id is distinct from aid or item.sha256 is distinct from hash or item.byte_count is distinct from bytes) then response:=jsonb_build_object('status','rejected','code','immutable_original'); end if;
   if response is null and p->>'kind'<>'link' and not exists(select 1 from storage.objects o where o.bucket_id='originals' and o.name=path and (o.metadata->>'size')::bigint=bytes and o.user_metadata->>'sha256'=hash) then response:=jsonb_build_object('status','rejected','code','original_missing'); end if;
   if response is null then
    if not existing then
    insert into public.items(id,owner_id,title,kind,url,filename,content_type,byte_count,note,collection_id,attachment_id,storage_path,sha256,created_at)
    values(target,owner,trim(p->>'title'),p->>'kind',p->>'url',p->>'filename',p->>'contentType',bytes,coalesce(p->>'note',''),cid,aid,path,hash,submitted_at)
    on conflict(id) do nothing returning * into item;
    else
     update public.items set title=trim(p->>'title'),kind=p->>'kind',url=p->>'url',filename=p->>'filename',
       content_type=p->>'contentType',byte_count=bytes,note=coalesce(p->>'note',''),collection_id=cid,
       attachment_id=aid,storage_path=path,sha256=hash,version=version+1,updated_at=now()
       where id=target and owner_id=owner and version=expected returning * into item;
    end if;
    if found then value:=public.item_json(item);
    else response:=jsonb_build_object('status','rejected','code','id_unavailable'); end if;
   end if;
  end if;
 else
  select * into folder from public.collections where id=target; existing:=found;
  if existing and folder.owner_id<>owner then response:=jsonb_build_object('status','rejected','code','id_unavailable');
  elsif existing and (folder.version<>expected or (action='upsert' and folder.deleted_at is not null)) then response:=jsonb_build_object('status','conflict','code',case when folder.deleted_at is not null then 'deleted' else 'version_conflict' end,'record',public.collection_json(folder));
  elsif not existing and (expected<>0 or action='delete') then response:=jsonb_build_object('status','rejected','code','not_found');
  elsif action='delete' then
   for item in update public.items set collection_id=null,version=version+1,updated_at=now() where owner_id=owner and collection_id=target returning * loop
    perform public.append_library_change(owner,'item',item.id,public.item_json(item));
   end loop;
   update public.collections set deleted_at=coalesce(deleted_at,now()),updated_at=now(),version=version+1 where id=target returning * into folder;
   value:=public.collection_json(folder);
  elsif jsonb_typeof(p->'name') is distinct from 'string' or coalesce(length(trim(p->>'name')),0) not between 1 and 120 or coalesce(length(p->>'tint'),0)>40 then response:=jsonb_build_object('status','rejected','code','invalid_payload');
  else
   begin
   if not existing then
   insert into public.collections(id,owner_id,name,tint,created_at) values(target,owner,trim(p->>'name'),coalesce(p->>'tint','blue'),coalesce((p->>'createdAt')::timestamptz,now()))
   on conflict(id) do nothing returning * into folder;
   else
    update public.collections set name=trim(p->>'name'),tint=coalesce(p->>'tint','blue'),version=version+1,updated_at=now()
     where id=target and owner_id=owner and version=expected returning * into folder;
   end if;
   if found then value:=public.collection_json(folder);
   else response:=jsonb_build_object('status','rejected','code','id_unavailable'); end if;
   exception when invalid_datetime_format or datetime_field_overflow then response:=jsonb_build_object('status','rejected','code','invalid_payload'); end;
  end if;
 end if;
 if response is null then
  rev:=public.append_library_change(owner,entity,target,value);
  response:=jsonb_build_object('status','applied','entity',entity,'id',target,'record',value,'revision',rev,'warnings',warning);
 end if;
 insert into public.operation_receipts values(owner,op_id,operation,response);
 return response;
end
$$;
revoke all on function public.apply_operation(jsonb) from public,anon;
grant execute on function public.apply_operation(jsonb) to authenticated;

create function public.library_changes(after_revision bigint default 0,page_size integer default 200) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare owner uuid:=auth.uid(); changes jsonb; last_revision bigint; more boolean;
begin
 if owner is null then raise exception 'authentication_required' using errcode='42501'; end if;
 if after_revision<0 or page_size<1 or page_size>200 then raise exception 'invalid_cursor'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('revision',revision,'entity',entity,'id',entity_id,'record',record) order by revision),'[]'),coalesce(max(revision),after_revision)
 into changes,last_revision from (select * from public.library_change_log where owner_id=owner and revision>after_revision order by revision limit page_size) page;
 select exists(select 1 from public.library_change_log where owner_id=owner and revision>last_revision) into more;
 return jsonb_build_object('changes',changes,'nextRevision',last_revision,'hasMore',more);
end
$$;
revoke all on function public.library_changes(bigint,integer) from public,anon;
grant execute on function public.library_changes(bigint,integer) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit) values('originals','originals',false,26214400) on conflict(id) do update set public=false,file_size_limit=26214400;
create function public.original_write_allowed(object_name text,object_metadata jsonb) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare owner uuid:=auth.uid();
begin
 if owner is null then return false; end if;
 insert into public.user_revisions(owner_id) select owner where exists(select 1 from auth.users where id=owner) on conflict do nothing;
 perform 1 from public.user_revisions where owner_id=owner for update;
 return exists(select 1 from auth.users where id=owner) and not exists(select 1 from public.account_deletions where owner_id=owner)
 and object_name ~ ('^'||owner::text||'/[0-9a-f-]{36}/[0-9a-f-]{36}$')
 -- Storage probes may supply contentLength before final metadata.size exists.
 -- The bucket enforces bytes independently; apply_operation verifies final size.
 and (coalesce(object_metadata->>'size',object_metadata->>'contentLength') is null
      or coalesce(object_metadata->>'size',object_metadata->>'contentLength')::bigint between 0 and 26214400);
exception when invalid_text_representation or numeric_value_out_of_range then return false;
end
$$;
revoke all on function public.original_write_allowed(text,jsonb) from public,anon;
grant execute on function public.original_write_allowed(text,jsonb) to authenticated;
create policy originals_read on storage.objects for select to authenticated using(bucket_id='originals' and split_part(name,'/',1)=auth.uid()::text);
create policy originals_create on storage.objects for insert to authenticated with check(bucket_id='originals' and public.original_write_allowed(name,metadata));
-- No client UPDATE or DELETE policy. Server cleanup uses the Storage API.

create function public.begin_account_deletion() returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare owner uuid:=auth.uid();
begin
 if owner is null then raise exception 'authentication_required' using errcode='42501'; end if;
 insert into public.user_revisions(owner_id) values(owner) on conflict do nothing;
 perform 1 from public.user_revisions where owner_id=owner for update;
 insert into public.account_deletions(owner_id) values(owner) on conflict do nothing;
end
$$;
revoke all on function public.begin_account_deletion() from public,anon;
grant execute on function public.begin_account_deletion() to authenticated;
