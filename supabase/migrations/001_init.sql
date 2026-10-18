-- KOC ONE · ORT platform schema
-- Polygons are stored as jsonb arrays of [lat, lng] points.

create extension if not exists pgcrypto;

-- ───────── Organisation structure ─────────
create table public.sectors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color text not null default '#0e7490',
  boundary jsonb,                       -- [[lat,lng],...]
  entry_message text,                   -- shown to employees on entering the boundary
  created_at timestamptz not null default now()
);

create table public.zones (
  id uuid primary key default gen_random_uuid(),
  sector_id uuid not null references public.sectors(id) on delete cascade,
  name text not null,
  classification text not null default 'unclassified'
    check (classification in ('unclassified','zone2','zone1','zone0')),
  boundary jsonb,
  entry_message text,
  created_at timestamptz not null default now()
);

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones(id) on delete cascade,
  name text not null,
  code text,
  muster_point text,
  boundary jsonb,
  entry_message text,
  created_at timestamptz not null default now()
);

-- ───────── People ─────────
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  employee_no text,
  phone text,
  blood_type text,
  role text not null default 'employee' check (role in ('employee','ort')),
  -- current position (updated by the app on boundary transitions and during alarms only)
  cur_sector_id uuid references public.sectors(id) on delete set null,
  cur_zone_id uuid references public.zones(id) on delete set null,
  cur_building_id uuid references public.buildings(id) on delete set null,
  last_lat double precision,
  last_lng double precision,
  last_seen timestamptz,
  online boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_ort() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'ort');
$$;

-- non-ORT users cannot change their own role
create or replace function public.protect_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- only signed-in end users are restricted; server-side admin code (no auth.uid) may set roles
  if auth.uid() is not null and not public.is_ort() then new.role := old.role; end if;
  return new;
end $$;
create trigger trg_protect_role before update on public.profiles
  for each row execute function public.protect_role();

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, employee_no, phone, blood_type)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name',''),
          new.raw_user_meta_data->>'employee_no',
          new.raw_user_meta_data->>'phone',
          new.raw_user_meta_data->>'blood_type');
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────── Alarms ─────────
create table public.alarms (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('signal1','signal2','signal3','message')),
  title text not null,
  body text,
  scope text not null check (scope in ('employee','building','zone','sector','all')),
  target_id uuid,                        -- employee / building / zone / sector id (null for 'all')
  drill boolean not null default false,
  active boolean not null default true,
  created_by uuid references public.profiles(id),
  confirmed_by_name text,                -- dual confirmation (second officer)
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create table public.alarm_acks (
  alarm_id uuid not null references public.alarms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'received'
    check (status in ('received','safe','need_help','injured','trapped')),
  lat double precision,
  lng double precision,
  building_id uuid,
  updated_at timestamptz not null default now(),
  primary key (alarm_id, user_id)
);

-- ───────── Boundary events (enter / exit) ─────────
create table public.geofence_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  area_type text not null check (area_type in ('sector','zone','building')),
  area_id uuid not null,
  event text not null check (event in ('enter','exit')),
  created_at timestamptz not null default now()
);

-- ───────── Encrypted reports ─────────
-- Content and photos are encrypted on the phone (AES-256-GCM); the AES key is wrapped
-- with the ORT public RSA key. Only ORT officers holding the passphrase can decrypt.
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  type text not null,                    -- fire / leak / injury / road / suspicious / hazard
  enc_payload text not null,             -- base64(iv|ciphertext) of JSON {description}
  wrapped_key text not null,             -- base64 RSA-OAEP(AES key)
  photo_paths text[] not null default '{}',
  lat double precision,
  lng double precision,
  building_id uuid,
  zone_id uuid,
  status text not null default 'new' check (status in ('new','received','dispatched','closed')),
  created_at timestamptz not null default now()
);

create table public.org_public_key (
  id int primary key default 1 check (id = 1),
  jwk jsonb not null,
  updated_at timestamptz not null default now()
);
create table public.org_private_key (
  id int primary key default 1 check (id = 1),
  wrapped text not null,                 -- private JWK encrypted with passphrase (PBKDF2 + AES-GCM)
  salt text not null,
  iv text not null,
  updated_at timestamptz not null default now()
);

-- ───────── Voice calls (WebRTC signalling via Realtime broadcast) ─────────
create table public.calls (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid not null references public.profiles(id) on delete cascade default auth.uid(),
  callee_id uuid not null references public.profiles(id) on delete cascade,
  caller_name text,
  status text not null default 'ringing' check (status in ('ringing','accepted','ended','rejected','missed')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

-- ───────── RLS ─────────
alter table public.sectors enable row level security;
alter table public.zones enable row level security;
alter table public.buildings enable row level security;
alter table public.profiles enable row level security;
alter table public.alarms enable row level security;
alter table public.alarm_acks enable row level security;
alter table public.geofence_events enable row level security;
alter table public.reports enable row level security;
alter table public.org_public_key enable row level security;
alter table public.org_private_key enable row level security;
alter table public.calls enable row level security;

-- structure: everyone signed in reads, ORT writes
create policy "read sectors" on public.sectors for select to authenticated using (true);
create policy "ort sectors" on public.sectors for all to authenticated using (public.is_ort()) with check (public.is_ort());
create policy "read zones" on public.zones for select to authenticated using (true);
create policy "ort zones" on public.zones for all to authenticated using (public.is_ort()) with check (public.is_ort());
create policy "read buildings" on public.buildings for select to authenticated using (true);
create policy "ort buildings" on public.buildings for all to authenticated using (public.is_ort()) with check (public.is_ort());

-- profiles
create policy "own or ort read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_ort());
create policy "own update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_ort()) with check (id = auth.uid() or public.is_ort());

-- alarms
create policy "read alarms" on public.alarms for select to authenticated using (true);
create policy "ort alarms" on public.alarms for all to authenticated using (public.is_ort()) with check (public.is_ort());

-- acks
create policy "own or ort read acks" on public.alarm_acks for select to authenticated
  using (user_id = auth.uid() or public.is_ort());
create policy "own insert acks" on public.alarm_acks for insert to authenticated with check (user_id = auth.uid());
create policy "own update acks" on public.alarm_acks for update to authenticated
  using (user_id = auth.uid() or public.is_ort()) with check (user_id = auth.uid() or public.is_ort());

-- geofence events
create policy "own insert geo" on public.geofence_events for insert to authenticated with check (user_id = auth.uid());
create policy "ort read geo" on public.geofence_events for select to authenticated using (public.is_ort() or user_id = auth.uid());

-- reports
create policy "own insert reports" on public.reports for insert to authenticated with check (user_id = auth.uid());
create policy "own or ort read reports" on public.reports for select to authenticated using (user_id = auth.uid() or public.is_ort());
create policy "ort update reports" on public.reports for update to authenticated using (public.is_ort()) with check (public.is_ort());

-- keys
create policy "read public key" on public.org_public_key for select to authenticated using (true);
create policy "ort public key" on public.org_public_key for all to authenticated using (public.is_ort()) with check (public.is_ort());
create policy "ort private key" on public.org_private_key for all to authenticated using (public.is_ort()) with check (public.is_ort());

-- calls
create policy "participants read calls" on public.calls for select to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid() or public.is_ort());
create policy "insert calls" on public.calls for insert to authenticated
  with check (caller_id = auth.uid());
create policy "participants update calls" on public.calls for update to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid() or public.is_ort())
  with check (caller_id = auth.uid() or callee_id = auth.uid() or public.is_ort());

-- ───────── Storage: encrypted report photos ─────────
insert into storage.buckets (id, name, public) values ('reports', 'reports', false)
  on conflict (id) do nothing;
create policy "upload own encrypted photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'reports' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "ort reads photos" on storage.objects for select to authenticated
  using (bucket_id = 'reports' and public.is_ort());

-- ───────── Realtime ─────────
alter publication supabase_realtime add table public.alarms, public.alarm_acks, public.reports, public.calls, public.profiles;
alter table public.alarm_acks replica identity full;
alter table public.profiles replica identity full;

-- ───────── Indexes ─────────
create index on public.zones(sector_id);
create index on public.buildings(zone_id);
create index on public.alarm_acks(user_id);
create index on public.reports(created_at desc);
create index on public.calls(callee_id, status);
create index on public.geofence_events(user_id, created_at desc);

-- ───────── Hardening ─────────
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.protect_role() from public, anon, authenticated;
revoke execute on function public.is_ort() from public, anon;
grant execute on function public.is_ort() to authenticated;

-- Structure tables also stream changes (the app reloads boundaries live)
alter publication supabase_realtime add table public.sectors, public.zones, public.buildings;

-- English alarm text (the app shows the employee's chosen language)
alter table public.alarms add column if not exists title_en text, add column if not exists body_en text;

-- ───────── Digital ID (managed by ORT; photo uploaded from the dashboard only) ─────────
alter table public.profiles
  add column if not exists job_title text,
  add column if not exists department text,
  add column if not exists civil_id text,
  add column if not exists photo_path text,
  add column if not exists active boolean not null default true;

create or replace function public.protect_role() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_ort() then
    new.role := old.role; new.full_name := old.full_name; new.employee_no := old.employee_no;
    new.blood_type := old.blood_type; new.phone := old.phone; new.job_title := old.job_title;
    new.department := old.department; new.civil_id := old.civil_id; new.photo_path := old.photo_path;
    new.active := old.active;
  end if;
  return new;
end $$;
revoke execute on function public.protect_role() from public, anon, authenticated;

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', false) on conflict (id) do nothing;
create policy "ort uploads photos" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and public.is_ort());
create policy "ort updates photos" on storage.objects for update to authenticated using (bucket_id = 'avatars' and public.is_ort()) with check (bucket_id = 'avatars' and public.is_ort());
create policy "ort deletes photos" on storage.objects for delete to authenticated using (bucket_id = 'avatars' and public.is_ort());
create policy "own or ort reads photo" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (public.is_ort() or (storage.foldername(name))[1] = auth.uid()::text));

-- ───────── Background alarm delivery while the app is closed ─────────
-- The native Android service holds a device token (one per account) and polls pending_alarms().
create table if not exists public.device_tokens (
  token uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.device_tokens enable row level security;  -- no policies: only the functions below use it

create or replace function public.register_device() returns uuid
language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into public.device_tokens(user_id) values (auth.uid())
    on conflict (user_id) do update set token = gen_random_uuid(), created_at = now()
    returning token into t;
  return t;
end $$;

create or replace function public.pending_alarms(p_token uuid)
returns table (id uuid, kind text, title text, body text, title_en text, body_en text,
               active boolean, drill boolean, created_at timestamptz, status text)
language sql stable security definer set search_path = public as $$
  with u as (select p.* from public.device_tokens d join public.profiles p on p.id = d.user_id where d.token = p_token)
  select a.id, a.kind, a.title, a.body, a.title_en, a.body_en, a.active, a.drill, a.created_at, k.status
  from public.alarms a cross join u
  left join public.alarm_acks k on k.alarm_id = a.id and k.user_id = u.id
  where (a.active or a.created_at > now() - interval '10 minutes')
    and ((a.scope = 'employee' and a.target_id = u.id)
      or (a.scope = 'all' and (u.cur_sector_id is not null or u.cur_zone_id is not null or u.cur_building_id is not null))
      or (a.scope = 'sector' and a.target_id = u.cur_sector_id)
      or (a.scope = 'zone' and a.target_id = u.cur_zone_id)
      or (a.scope = 'building' and a.target_id = u.cur_building_id))
  order by a.created_at desc limit 20;
$$;

create or replace function public.device_ack(p_token uuid, p_alarm uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.alarm_acks(alarm_id, user_id, status)
  select p_alarm, d.user_id, 'received' from public.device_tokens d where d.token = p_token
  on conflict (alarm_id, user_id) do nothing;
$$;

-- Ringing ORT call for a device (the background service rings even when the app is closed)
create or replace function public.pending_calls(p_token uuid)
returns table (id uuid, caller_name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select c.id, c.caller_name, c.created_at
  from public.calls c join public.device_tokens d on d.user_id = c.callee_id
  where d.token = p_token and c.status = 'ringing' and c.created_at > now() - interval '70 seconds'
  order by c.created_at desc limit 1;
$$;
