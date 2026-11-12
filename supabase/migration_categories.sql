-- =====================================================================
-- Wallet — migration « catégories personnalisées »
-- À exécuter dans Supabase > SQL Editor AVANT de publier la nouvelle version d'index.html.
-- Relançable sans erreur, sans perte de données, uniquement sur des tables ep_.
-- La nouvelle table suit exactement la règle d'accès des autres : perso = propriétaire seul,
-- commun = membres du foyer.
--
-- Une ligne sert soit à personnaliser une catégorie par défaut (code = 'logement', 'loisirs'…),
-- soit à créer une catégorie (code = 'c_' + 8 caractères). Les dépenses et les lignes de budget
-- gardent ce code dans leur colonne category : aucune donnée existante ne change.
-- Les catégories automatiques (épargne, virement commun, prêt) ne sont pas modifiables.
-- =====================================================================

create table if not exists public.ep_categories (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.ep_households(id) on delete cascade,
  scope          text not null check (scope in ('perso', 'commun')),
  user_id        uuid references auth.users(id) on delete cascade,
  code           text not null check (code ~ '^[a-z0-9_]{1,40}$'
                                      and code not in ('epargne', 'virement_commun', 'pret')),
  name           text not null check (length(trim(name)) between 1 and 40),
  category_group text not null check (category_group in ('besoins', 'envies', 'epargne')),   -- barre 50/30/20
  sort_order     integer not null default 100 check (sort_order between 0 and 100000),
  archived       boolean not null default false,
  created_at     timestamptz not null default now(),
  constraint ep_categories_scope_user check ((scope = 'perso') = (user_id is not null)),
  constraint ep_categories_unique unique nulls not distinct (household_id, scope, user_id, code)
);

create index if not exists ep_categories_hh_idx   on public.ep_categories (household_id, scope, user_id);
create index if not exists ep_categories_user_idx on public.ep_categories (user_id);

alter table public.ep_categories enable row level security;

drop policy if exists ep_categories_rw on public.ep_categories;
create policy ep_categories_rw on public.ep_categories for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

revoke all on public.ep_categories from anon, authenticated;
grant select, insert, update, delete on public.ep_categories to authenticated;
