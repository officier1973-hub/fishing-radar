create extension if not exists pgcrypto;

create table if not exists public.fishing_spots (
  id uuid primary key default gen_random_uuid(),
  latitude double precision not null,
  longitude double precision not null,
  public_latitude double precision,
  public_longitude double precision,
  depth_meters double precision not null,
  bottom_type text not null default 'Не указано',
  fish_species text not null default 'Не указана',
  fish_weight_kg double precision,
  comment text not null default '',
  is_private_circle boolean not null default false,
  photo_url text,
  user_id uuid references auth.users(id) on delete set null,
  author_name text,
  created_at timestamptz not null default now()
);

alter table public.fishing_spots add column if not exists public_latitude double precision;
alter table public.fishing_spots add column if not exists public_longitude double precision;
alter table public.fishing_spots add column if not exists photo_url text;
alter table public.fishing_spots add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.fishing_spots add column if not exists author_name text;

alter table public.fishing_spots enable row level security;

drop policy if exists "spots_select_all" on public.fishing_spots;
create policy "spots_select_all" on public.fishing_spots
  for select using (true);

drop policy if exists "spots_insert_all" on public.fishing_spots;
create policy "spots_insert_all" on public.fishing_spots
  for insert with check (auth.uid() = user_id or user_id is null);

drop policy if exists "spots_update_own" on public.fishing_spots;
create policy "spots_update_own" on public.fishing_spots
  for update using (auth.uid() = user_id);

drop policy if exists "spots_delete_own" on public.fishing_spots;
create policy "spots_delete_own" on public.fishing_spots
  for delete using (auth.uid() = user_id);

-- Профили и коды для «Кругов доверия»
create table if not exists public.angler_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Рыбак',
  trust_code text not null unique,
  created_at timestamptz not null default now()
);

alter table public.angler_profiles enable row level security;

drop policy if exists "angler_profiles_select_own" on public.angler_profiles;
create policy "angler_profiles_select_own" on public.angler_profiles
  for select using (auth.uid() = user_id);

drop policy if exists "angler_profiles_insert_own" on public.angler_profiles;
create policy "angler_profiles_insert_own" on public.angler_profiles
  for insert with check (auth.uid() = user_id);

drop policy if exists "angler_profiles_update_own" on public.angler_profiles;
create policy "angler_profiles_update_own" on public.angler_profiles
  for update using (auth.uid() = user_id);

-- Доверенные друзья (owner_id разрешает friend_id видеть точные координаты своих точек)
create table if not exists public.trusted_friends (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  friend_id uuid not null references auth.users(id) on delete cascade,
  friend_name text not null default 'Рыбак',
  created_at timestamptz not null default now(),
  constraint trusted_friends_no_self check (owner_id <> friend_id),
  constraint trusted_friends_unique unique (owner_id, friend_id)
);

alter table public.trusted_friends enable row level security;

drop policy if exists "trusted_friends_select" on public.trusted_friends;
create policy "trusted_friends_select" on public.trusted_friends
  for select using (auth.uid() = owner_id or auth.uid() = friend_id);

drop policy if exists "trusted_friends_insert_own" on public.trusted_friends;
create policy "trusted_friends_insert_own" on public.trusted_friends
  for insert with check (auth.uid() = owner_id);

drop policy if exists "trusted_friends_delete_own" on public.trusted_friends;
create policy "trusted_friends_delete_own" on public.trusted_friends
  for delete using (auth.uid() = owner_id);

drop function if exists public.get_or_create_my_trust_code(text);
create or replace function public.get_or_create_my_trust_code(
  p_display_name text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_name text := coalesce(nullif(trim(p_display_name), ''), 'Рыбак');
begin
  if v_uid is null then
    raise exception 'Требуется вход в аккаунт';
  end if;

  select ap.trust_code
  into v_code
  from public.angler_profiles ap
  where ap.user_id = v_uid;

  if v_code is null then
    v_code := 'FR' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    insert into public.angler_profiles (user_id, display_name, trust_code)
    values (v_uid, v_name, v_code)
    on conflict (user_id) do update
      set display_name = excluded.display_name
    returning trust_code into v_code;
  elsif p_display_name is not null and trim(p_display_name) <> '' then
    update public.angler_profiles
    set display_name = v_name
    where user_id = v_uid;
  end if;

  return v_code;
end;
$$;

grant execute on function public.get_or_create_my_trust_code(text) to authenticated;

drop function if exists public.add_trusted_friend_by_code(text);
create or replace function public.add_trusted_friend_by_code(p_code text)
returns table (
  id uuid,
  owner_id uuid,
  friend_id uuid,
  friend_name text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_target_id uuid;
  v_target_name text;
  v_clean_code text := upper(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g'));
begin
  if v_uid is null then
    raise exception 'Требуется вход в аккаунт';
  end if;

  if length(v_clean_code) < 4 then
    raise exception 'Введите корректный код друга';
  end if;

  select ap.user_id, ap.display_name
  into v_target_id, v_target_name
  from public.angler_profiles ap
  where upper(ap.trust_code) = v_clean_code
  limit 1;

  if v_target_id is null then
    raise exception 'Пользователь с таким кодом не найден';
  end if;

  if v_target_id = v_uid then
    raise exception 'Нельзя добавить собственный код';
  end if;

  return query
  insert into public.trusted_friends (owner_id, friend_id, friend_name)
  values (v_uid, v_target_id, coalesce(nullif(v_target_name, ''), 'Рыбак'))
  on conflict on constraint trusted_friends_unique do update
    set friend_name = excluded.friend_name
  returning
    trusted_friends.id,
    trusted_friends.owner_id,
    trusted_friends.friend_id,
    trusted_friends.friend_name,
    trusted_friends.created_at;
end;
$$;

grant execute on function public.add_trusted_friend_by_code(text) to authenticated;

drop function if exists public.get_my_trust_circle();
create or replace function public.get_my_trust_circle()
returns table (
  id uuid,
  peer_user_id uuid,
  peer_name text,
  direction text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    tf.id,
    tf.friend_id as peer_user_id,
    coalesce(nullif(ap.display_name, ''), tf.friend_name, 'Рыбак') as peer_name,
    'outgoing'::text as direction,
    tf.created_at
  from public.trusted_friends tf
  left join public.angler_profiles ap on ap.user_id = tf.friend_id
  where tf.owner_id = auth.uid()

  union all

  select
    tf.id,
    tf.owner_id as peer_user_id,
    coalesce(nullif(ap.display_name, ''), 'Рыбак') as peer_name,
    'incoming'::text as direction,
    tf.created_at
  from public.trusted_friends tf
  left join public.angler_profiles ap on ap.user_id = tf.owner_id
  where tf.friend_id = auth.uid()

  order by created_at desc;
$$;

grant execute on function public.get_my_trust_circle() to authenticated;

drop function if exists public.remove_trusted_friend(uuid);
create or replace function public.remove_trusted_friend(p_friend_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.trusted_friends
  where owner_id = auth.uid() and friend_id = p_friend_id;
$$;

grant execute on function public.remove_trusted_friend(uuid) to authenticated;

drop function if exists public.get_spots_nearby(double precision, double precision, double precision);

create or replace function public.get_spots_nearby(
  user_lat double precision,
  user_lon double precision,
  radius_meters double precision default 50000
)
returns table (
  id uuid,
  latitude double precision,
  longitude double precision,
  public_latitude double precision,
  public_longitude double precision,
  depth_meters double precision,
  bottom_type text,
  fish_species text,
  fish_weight_kg double precision,
  comment text,
  is_private_circle boolean,
  is_trusted_friend boolean,
  photo_url text,
  user_id uuid,
  author_name text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    case
      when s.is_private_circle and (
        auth.uid() is null
        or (
          s.user_id is distinct from auth.uid()
          and not exists (
            select 1
            from public.trusted_friends tf
            where tf.owner_id = s.user_id
              and tf.friend_id = auth.uid()
          )
        )
      )
        then coalesce(s.public_latitude, s.latitude)
      else s.latitude
    end as latitude,
    case
      when s.is_private_circle and (
        auth.uid() is null
        or (
          s.user_id is distinct from auth.uid()
          and not exists (
            select 1
            from public.trusted_friends tf
            where tf.owner_id = s.user_id
              and tf.friend_id = auth.uid()
          )
        )
      )
        then coalesce(s.public_longitude, s.longitude)
      else s.longitude
    end as longitude,
    s.public_latitude,
    s.public_longitude,
    s.depth_meters,
    s.bottom_type,
    s.fish_species,
    s.fish_weight_kg,
    s.comment,
    s.is_private_circle,
    (
      auth.uid() is not null
      and s.user_id is not null
      and s.user_id is distinct from auth.uid()
      and exists (
        select 1
        from public.trusted_friends tf
        where tf.owner_id = s.user_id
          and tf.friend_id = auth.uid()
      )
    ) as is_trusted_friend,
    s.photo_url,
    s.user_id,
    s.author_name,
    s.created_at
  from public.fishing_spots s
  where 6371000.0 * acos(
    least(1.0, greatest(-1.0,
      cos(radians(user_lat)) * cos(radians(s.latitude)) *
      cos(radians(s.longitude) - radians(user_lon)) +
      sin(radians(user_lat)) * sin(radians(s.latitude))
    ))
  ) <= radius_meters
  order by s.created_at desc
  limit 300;
$$;

grant execute on function public.get_spots_nearby(double precision, double precision, double precision) to anon, authenticated;

-- Чат по регионам и водоёмам
create table if not exists public.region_messages (
  id uuid primary key default gen_random_uuid(),
  region text not null,
  user_id uuid references auth.users(id) on delete set null,
  author_name text not null default 'Рыбак',
  message_text text not null,
  created_at timestamptz not null default now()
);

alter table public.region_messages enable row level security;

drop policy if exists "chat_select_all" on public.region_messages;
create policy "chat_select_all" on public.region_messages
  for select using (true);

drop policy if exists "chat_insert_all" on public.region_messages;
create policy "chat_insert_all" on public.region_messages
  for insert with check (auth.uid() = user_id or user_id is null);

do $$
begin
  alter publication supabase_realtime add table public.region_messages;
exception
  when duplicate_object then null;
end $$;

-- Бакет для фото уловов
insert into storage.buckets (id, name, public)
values ('spot-photos', 'spot-photos', true)
on conflict (id) do nothing;

drop policy if exists "spot_photos_read" on storage.objects;
create policy "spot_photos_read" on storage.objects
  for select using (bucket_id = 'spot-photos');

drop policy if exists "spot_photos_upload" on storage.objects;
create policy "spot_photos_upload" on storage.objects
  for insert with check (bucket_id = 'spot-photos');

drop policy if exists "spot_photos_delete" on storage.objects;
create policy "spot_photos_delete" on storage.objects
  for delete using (
    bucket_id = 'spot-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
