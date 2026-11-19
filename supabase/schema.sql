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
      when s.is_private_circle and (auth.uid() is null or s.user_id is distinct from auth.uid())
        then coalesce(s.public_latitude, s.latitude)
      else s.latitude
    end as latitude,
    case
      when s.is_private_circle and (auth.uid() is null or s.user_id is distinct from auth.uid())
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
