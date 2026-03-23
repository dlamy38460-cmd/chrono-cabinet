-- ============================================================
-- CHRONO CABINET v4 — Schéma Supabase
-- Exécuter dans : Supabase > SQL Editor > New Query
-- ============================================================

-- 1. TABLE PROFILS (liée à auth.users de Supabase)
create table public.profiles (
  id          uuid references auth.users(id) on delete cascade primary key,
  full_name   text not null,
  role        text not null default 'avocat' check (role in ('admin','avocat')),
  taux_defaut numeric(10,2) default 200,
  created_at  timestamptz default now()
);

-- 2. TABLE ENTRÉES DE TEMPS
create table public.time_entries (
  id          bigserial primary key,
  user_id     uuid references public.profiles(id) on delete cascade not null,
  dossier     text not null,
  minutes     integer not null check (minutes > 0),
  taux        numeric(10,2) not null,
  montant     numeric(10,2) not null,
  description text not null,
  date        date not null,
  juris_status text default 'pending' check (juris_status in ('pending','synced','error')),
  created_at  timestamptz default now()
);

-- 3. TABLE ÉCHÉANCES
create table public.echeances (
  id          bigserial primary key,
  user_id     uuid references public.profiles(id) on delete cascade not null,
  titre       text not null,
  dossier     text not null,
  date        date not null,
  heure       time,
  type        text default 'autre',
  notes       text,
  done        boolean default false,
  created_at  timestamptz default now()
);

-- ============================================================
-- SÉCURITÉ : Row Level Security (RLS)
-- Chaque avocat ne voit que ses propres données.
-- L'admin voit tout.
-- ============================================================

alter table public.profiles     enable row level security;
alter table public.time_entries enable row level security;
alter table public.echeances    enable row level security;

-- Fonction helper : est-ce que l'utilisateur connecté est admin ?
create or replace function public.is_admin()
returns boolean as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer;

-- PROFILS : chacun voit son propre profil, admin voit tous
create policy "profiles_select" on public.profiles for select
  using (id = auth.uid() or public.is_admin());

create policy "profiles_update" on public.profiles for update
  using (id = auth.uid() or public.is_admin());

create policy "profiles_insert" on public.profiles for insert
  with check (public.is_admin());

create policy "profiles_delete" on public.profiles for delete
  using (public.is_admin());

-- TIME ENTRIES : avocat voit les siennes, admin voit toutes
create policy "entries_select" on public.time_entries for select
  using (user_id = auth.uid() or public.is_admin());

create policy "entries_insert" on public.time_entries for insert
  with check (user_id = auth.uid());

create policy "entries_update" on public.time_entries for update
  using (user_id = auth.uid() or public.is_admin());

create policy "entries_delete" on public.time_entries for delete
  using (user_id = auth.uid() or public.is_admin());

-- ÉCHÉANCES : même logique
create policy "ech_select" on public.echeances for select
  using (user_id = auth.uid() or public.is_admin());

create policy "ech_insert" on public.echeances for insert
  with check (user_id = auth.uid());

create policy "ech_update" on public.echeances for update
  using (user_id = auth.uid() or public.is_admin());

create policy "ech_delete" on public.echeances for delete
  using (user_id = auth.uid() or public.is_admin());

-- ============================================================
-- TRIGGER : créer automatiquement un profil à l'inscription
-- ============================================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'avocat')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- NOTE : Après avoir exécuté ce SQL,
-- créez votre compte admin manuellement dans
-- Supabase > Authentication > Users > Invite user
-- puis dans SQL Editor :
--   update public.profiles set role = 'admin' where id = 'VOTRE-UUID';
-- ============================================================
