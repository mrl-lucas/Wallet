-- =====================================================================
-- Wallet — migration « positions et part du commun »
-- À exécuter dans Supabase > SQL Editor AVANT de publier la nouvelle version d'index.html.
-- Relançable sans erreur, sans perte de données, uniquement sur des objets ep_.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Positions des comptes d'investissement (PEA, CTO, crypto…)
--    Même règle que les autres tables : 'perso' = propriétaire seul.
--    En plus, une position doit appartenir au même espace et au même propriétaire
--    que son compte parent.
-- ---------------------------------------------------------------------

create table if not exists public.ep_holdings (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.ep_households(id) on delete cascade,
  scope          text not null default 'perso' check (scope in ('perso', 'commun')),
  user_id        uuid default auth.uid() references auth.users(id) on delete cascade,
  account_id     uuid not null references public.ep_accounts(id) on delete cascade,
  asset_type     text not null check (asset_type in ('crypto', 'etf', 'action')),
  symbol         text not null check (length(trim(symbol)) between 1 and 40),  -- ex. bitcoin, CW8.PA, ISIN
  label          text,                                                         -- nom affiché (facultatif)
  quantity       numeric(24,10) not null check (quantity >= 0),
  invested       numeric(14,2)  not null default 0 check (invested >= 0),      -- montant investi (€)
  first_purchase date,                                                         -- pour le rendement annualisé
  created_at     timestamptz not null default now(),
  constraint ep_holdings_scope_user check ((scope = 'perso') = (user_id is not null))
);

create index if not exists ep_holdings_account_idx on public.ep_holdings (account_id);
create index if not exists ep_holdings_hh_idx      on public.ep_holdings (household_id, scope, user_id);

alter table public.ep_holdings enable row level security;

drop policy if exists ep_holdings_rw on public.ep_holdings;
create policy ep_holdings_rw on public.ep_holdings for all to authenticated
  using (
    public.ep_can_access(scope, user_id, household_id)
    and exists (select 1 from public.ep_accounts a
                where a.id = account_id
                  and public.ep_can_access(a.scope, a.user_id, a.household_id))
  )
  with check (
    public.ep_can_access(scope, user_id, household_id)
    and exists (select 1 from public.ep_accounts a
                where a.id = account_id
                  and a.household_id = ep_holdings.household_id
                  and a.scope = ep_holdings.scope
                  and a.user_id is not distinct from ep_holdings.user_id)
  );

revoke all on public.ep_holdings from anon, authenticated;
grant select, insert, update, delete on public.ep_holdings to authenticated;


-- ---------------------------------------------------------------------
-- 2. Ma part du compte commun (50 % par défaut), réglable par chacun pour lui-même
-- ---------------------------------------------------------------------

alter table public.ep_members
  add column if not exists common_share numeric(5,2) not null default 50
    check (common_share between 0 and 100);

grant update (common_share) on public.ep_members to authenticated;
