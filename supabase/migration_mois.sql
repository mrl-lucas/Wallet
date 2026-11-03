-- =====================================================================
-- Wallet — migration « mise à jour du mois + inflation »
-- À exécuter dans Supabase > SQL Editor AVANT de publier la nouvelle version d'index.html.
-- Relançable sans erreur, sans perte de données, uniquement sur des tables ep_.
-- Les règles d'accès existantes ne changent pas ; la nouvelle table suit la même règle.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Taux d'inflation (projection « en euros d'aujourd'hui »), réglage personnel
-- ---------------------------------------------------------------------

alter table public.ep_members
  add column if not exists inflation_rate numeric(5,2) not null default 2
    check (inflation_rate between -5 and 20);

grant update (inflation_rate) on public.ep_members to authenticated;


-- ---------------------------------------------------------------------
-- 2. Mois validés (« Mettre à jour mon mois ») : un enregistrement par espace et par mois.
--    details garde l'état AVANT la 1re validation (investi, quantité, soldes) :
--    une 2e validation repart de cet état et ne double donc pas les versements.
-- ---------------------------------------------------------------------

create table if not exists public.ep_month_closes (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  scope        text not null check (scope in ('perso', 'commun')),
  user_id      uuid references auth.users(id) on delete cascade,
  month        date not null check (extract(day from month) = 1),
  details      jsonb not null default '{}'::jsonb,
  summary      jsonb not null default '{}'::jsonb,   -- { delta, paid, gains }
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint ep_month_closes_scope_user check ((scope = 'perso') = (user_id is not null)),
  constraint ep_month_closes_unique unique nulls not distinct (household_id, scope, user_id, month)
);

alter table public.ep_month_closes enable row level security;

drop policy if exists ep_month_closes_rw on public.ep_month_closes;
create policy ep_month_closes_rw on public.ep_month_closes for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

revoke all on public.ep_month_closes from anon, authenticated;
grant select, insert, update, delete on public.ep_month_closes to authenticated;
