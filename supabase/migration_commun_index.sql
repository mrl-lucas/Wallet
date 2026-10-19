-- =====================================================================
-- Wallet — migration « dépenses du Commun + suivi d'indice »
-- À exécuter dans Supabase > SQL Editor AVANT de publier la nouvelle version d'index.html.
-- Relançable sans erreur, sans perte de données, uniquement sur des tables ep_.
-- Les règles d'accès existantes ne changent pas ; la nouvelle table suit la même règle.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Dépenses du Commun : payées par le compte commun ou avancées par un membre
--    paid_by : 'moi' / 'tiers' / 'avance' (Mon espace) + 'commun' / 'membre' (Commun)
-- ---------------------------------------------------------------------

do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.ep_expenses'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%paid_by%'
  loop
    execute format('alter table public.ep_expenses drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.ep_expenses add constraint ep_expenses_paid_by_check
  check (paid_by in ('moi', 'tiers', 'avance', 'commun', 'membre'));

alter table public.ep_expenses
  add column if not exists paid_by_member uuid references auth.users(id) on delete set null;  -- qui a avancé


-- ---------------------------------------------------------------------
-- 2. Remboursements entre membres (« Marquer comme réglé »), visibles par les deux
-- ---------------------------------------------------------------------

create table if not exists public.ep_settlements (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  scope        text not null default 'commun' check (scope = 'commun'),
  user_id      uuid references auth.users(id) on delete cascade,      -- toujours NULL (espace Commun)
  month        date not null check (extract(day from month) = 1),
  from_user    uuid not null references auth.users(id) on delete cascade,
  to_user      uuid not null references auth.users(id) on delete cascade,
  amount       numeric(14,2) not null check (amount > 0),
  created_by   uuid default auth.uid() references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  constraint ep_settlements_commun_user check (user_id is null),
  constraint ep_settlements_distinct check (from_user <> to_user)
);

create index if not exists ep_settlements_hh_month_idx on public.ep_settlements (household_id, month);

alter table public.ep_settlements enable row level security;

drop policy if exists ep_settlements_rw on public.ep_settlements;
create policy ep_settlements_rw on public.ep_settlements for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

revoke all on public.ep_settlements from anon, authenticated;
grant select, insert, update, delete on public.ep_settlements to authenticated;


-- ---------------------------------------------------------------------
-- 3. Positions en valeur saisie : suivi d'un indice de référence (S&P 500 / MSCI World)
--    index_ref_eur = prix de l'indice (en €) au moment de la saisie de la valeur.
-- ---------------------------------------------------------------------

alter table public.ep_holdings
  add column if not exists track_index   text check (track_index in ('SPY', 'URTH')),
  add column if not exists index_ref_eur numeric(14,6) check (index_ref_eur > 0),
  add column if not exists index_ref_at  timestamptz;
