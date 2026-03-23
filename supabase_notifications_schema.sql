-- ============================================================
-- LAMY Avocats — Chrono v4
-- SQL ADDITIONNEL pour le système de notifications
-- À exécuter dans Supabase > SQL Editor APRÈS le schéma principal
-- ============================================================

-- TABLE : journal des notifications envoyées
-- Évite les doublons (une seule notification par type/ref/jour)
create table if not exists public.notification_log (
  id          bigserial primary key,
  type        text not null,         -- 'echeance' | 'no_saisie' | 'conflit' | 'nouveau_dossier'
  ref_id      text not null,         -- identifiant de référence (ex: 'ech-42-J7')
  recipient   text not null,         -- courriel(s) du destinataire
  sent_date   date not null default current_date,
  created_at  timestamptz default now()
);

-- Index pour éviter les doublons rapidement
create index if not exists notif_log_lookup
  on public.notification_log(type, ref_id, sent_date);

-- TABLE : vérifications de conflits d'intérêts
create table if not exists public.conflict_verifications (
  id                bigserial primary key,
  new_dossier       text not null,
  party_name        text not null,
  existing_dossier  text not null,
  severity          text default 'medium' check (severity in ('high','medium','low')),
  decision          text default 'pending' check (decision in ('pending','waived','refused','opened')),
  verification_id   text,
  avocat_id         uuid references public.profiles(id),
  notes             text,
  created_at        timestamptz default now()
);

-- RLS sur notification_log (admin seulement)
alter table public.notification_log    enable row level security;
alter table public.conflict_verifications enable row level security;

create policy "notif_log_admin" on public.notification_log
  for all using (public.is_admin());

create policy "conflict_select" on public.conflict_verifications
  for select using (avocat_id = auth.uid() or public.is_admin());

create policy "conflict_insert" on public.conflict_verifications
  for insert with check (avocat_id = auth.uid());

create policy "conflict_update" on public.conflict_verifications
  for update using (avocat_id = auth.uid() or public.is_admin());

-- ============================================================
-- CRONS SUPABASE (à configurer dans Supabase > Database > Cron)
-- ============================================================
-- 
-- Notifications quotidiennes (échéances + saisies manquantes) :
-- Nom      : daily-notifications
-- Schedule : 0 8 * * *        (chaque jour à 08h00)
-- Command  : select net.http_post(
--              url := 'https://VOTRE_PROJECT_ID.supabase.co/functions/v1/send-notifications',
--              headers := '{"Authorization": "Bearer VOTRE_ANON_KEY"}',
--              body := '{}'
--            );
--
-- Résumé hebdomadaire (chaque lundi matin) :
-- Nom      : weekly-summary
-- Schedule : 0 8 * * 1        (chaque lundi à 08h00)
-- Command  : select net.http_post(
--              url := 'https://VOTRE_PROJECT_ID.supabase.co/functions/v1/weekly-summary',
--              headers := '{"Authorization": "Bearer VOTRE_ANON_KEY"}',
--              body := '{}'
--            );
--
-- ============================================================
