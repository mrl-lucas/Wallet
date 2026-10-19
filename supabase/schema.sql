-- =====================================================================
-- Wallet — schéma Supabase (Phase 1)
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- Relançable sans erreur : tout est en IF NOT EXISTS / CREATE OR REPLACE /
-- DROP POLICY IF EXISTS. Ne touche qu'aux objets préfixés ep_.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Foyer et membres
-- ---------------------------------------------------------------------

create table if not exists public.ep_households (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (length(trim(name)) between 1 and 80),
  invite_code text unique,                       -- vidé quand le foyer est complet
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table if not exists public.ep_members (
  household_id uuid not null references public.ep_households(id) on delete cascade,
  user_id      uuid not null unique references auth.users(id) on delete cascade, -- 1 foyer par personne
  first_name   text not null check (length(trim(first_name)) between 1 and 40),
  slot         smallint not null check (slot in (1, 2)),
  created_at   timestamptz not null default now(),
  primary key (household_id, user_id),
  unique (household_id, slot)
);


-- ---------------------------------------------------------------------
-- 2. Fonctions utilitaires pour la RLS
--    SECURITY DEFINER : lit ep_members sans repasser par sa propre RLS
--    (sinon la policy de ep_members s'appellerait en boucle).
-- ---------------------------------------------------------------------

create or replace function public.ep_is_member(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ep_members
    where household_id = p_household_id
      and user_id = auth.uid()
  );
$$;

-- Règle unique appliquée à toutes les tables de données :
--   perso  → seulement le propriétaire (et il doit être membre du foyer indiqué)
--   commun → tout membre du foyer
create or replace function public.ep_can_access(p_scope text, p_user_id uuid, p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case p_scope
    when 'perso'  then p_user_id = auth.uid() and public.ep_is_member(p_household_id)
    when 'commun' then public.ep_is_member(p_household_id)
    else false
  end;
$$;


-- ---------------------------------------------------------------------
-- 3. Tables de données (toutes avec household_id + scope + user_id)
--    Convention : scope 'perso' ⇒ user_id obligatoire ; 'commun' ⇒ user_id NULL.
--    Mois = 1er jour du mois (ex. 2026-10-01).
-- ---------------------------------------------------------------------

create table if not exists public.ep_accounts (
  id                   uuid primary key default gen_random_uuid(),
  household_id         uuid not null references public.ep_households(id) on delete cascade,
  scope                text not null check (scope in ('perso', 'commun')),
  user_id              uuid references auth.users(id) on delete cascade,
  name                 text not null,
  type                 text not null default 'autre',     -- courant, pee, livret_a, trade_republic, …
  balance              numeric(14,2) not null default 0,
  monthly_contribution numeric(14,2) not null default 0,
  annual_rate          numeric(6,3)  not null default 0,  -- en %, ex. 1.7
  cap                  numeric(14,2),                     -- plafond (ex. 22950 pour le Livret A)
  created_at           timestamptz not null default now(),
  constraint ep_accounts_scope_user check ((scope = 'perso') = (user_id is not null))
);

-- Relevés mensuels : pas de scope propre, ils héritent du compte parent.
create table if not exists public.ep_balance_snapshots (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.ep_accounts(id) on delete cascade,
  month      date not null check (extract(day from month) = 1),
  balance    numeric(14,2) not null,
  created_at timestamptz not null default now(),
  unique (account_id, month)
);

create table if not exists public.ep_budget_lines (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  scope        text not null check (scope in ('perso', 'commun')),
  user_id      uuid references auth.users(id) on delete cascade,
  label        text not null,
  category     text not null,   -- logement, alimentation, transport, abonnements, sante, loisirs, shopping, voyages, autre, epargne, virement_commun, pret
  amount       numeric(14,2) not null default 0,
  is_auto      boolean not null default false,   -- ligne automatique (épargne, virement commun, prêt)
  created_at   timestamptz not null default now(),
  constraint ep_budget_lines_scope_user check ((scope = 'perso') = (user_id is not null))
);

create table if not exists public.ep_month_overrides (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.ep_households(id) on delete cascade,
  scope          text not null check (scope in ('perso', 'commun')),
  user_id        uuid references auth.users(id) on delete cascade,
  month          date not null check (extract(day from month) = 1),
  category       text not null,
  planned_amount numeric(14,2) not null,
  created_at     timestamptz not null default now(),
  constraint ep_month_overrides_scope_user check ((scope = 'perso') = (user_id is not null)),
  constraint ep_month_overrides_unique unique nulls not distinct (household_id, scope, user_id, month, category)
);

create table if not exists public.ep_expenses (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  scope        text not null check (scope in ('perso', 'commun')),
  user_id      uuid references auth.users(id) on delete cascade,
  date         date not null default current_date,
  label        text not null,
  category     text not null,
  amount       numeric(14,2) not null,
  created_by   uuid default auth.uid() references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  constraint ep_expenses_scope_user check ((scope = 'perso') = (user_id is not null))
);

create table if not exists public.ep_incomes (
  id                  uuid primary key default gen_random_uuid(),
  household_id        uuid not null references public.ep_households(id) on delete cascade,
  scope               text not null check (scope in ('perso', 'commun')),
  user_id             uuid references auth.users(id) on delete cascade,
  kind                text not null default 'salaire' check (kind in ('salaire', 'contribution', 'autre')),
  label               text,
  amount              numeric(14,2) not null default 0,
  contributor_user_id uuid references auth.users(id) on delete set null, -- pour une contribution au Commun
  created_at          timestamptz not null default now(),
  constraint ep_incomes_scope_user check ((scope = 'perso') = (user_id is not null))
);

create table if not exists public.ep_loans (
  id                uuid primary key default gen_random_uuid(),
  household_id      uuid not null references public.ep_households(id) on delete cascade,
  scope             text not null default 'perso' check (scope in ('perso', 'commun')),
  user_id           uuid references auth.users(id) on delete cascade,
  name              text not null default 'Prêt étudiant',
  capital           numeric(14,2) not null,
  annual_rate       numeric(6,3)  not null default 0,  -- en %
  duration_months   integer not null check (duration_months > 0),
  start_date        date not null,                     -- début du remboursement
  insurance_monthly numeric(10,2) not null default 0,
  deferral_type     text not null default 'aucun' check (deferral_type in ('aucun', 'partiel', 'total')),
  deferral_months   integer not null default 0,
  future_salary     numeric(14,2),                     -- salaire prévu après les études
  created_at        timestamptz not null default now(),
  constraint ep_loans_scope_user check ((scope = 'perso') = (user_id is not null))
);

create table if not exists public.ep_goals (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  scope        text not null check (scope in ('perso', 'commun')),
  user_id      uuid references auth.users(id) on delete cascade,
  name         text not null,
  target       numeric(14,2) not null,
  saved        numeric(14,2) not null default 0,
  due_date     date,
  created_at   timestamptz not null default now(),
  constraint ep_goals_scope_user check ((scope = 'perso') = (user_id is not null))
);

-- Index pour les filtres les plus fréquents
create index if not exists ep_accounts_hh_idx      on public.ep_accounts      (household_id, scope, user_id);
create index if not exists ep_budget_lines_hh_idx  on public.ep_budget_lines  (household_id, scope, user_id);
create index if not exists ep_expenses_hh_date_idx on public.ep_expenses      (household_id, scope, user_id, date);
create index if not exists ep_incomes_hh_idx       on public.ep_incomes       (household_id, scope, user_id);
create index if not exists ep_loans_hh_idx         on public.ep_loans         (household_id, scope, user_id);
create index if not exists ep_goals_hh_idx         on public.ep_goals         (household_id, scope, user_id);


-- ---------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------

alter table public.ep_households        enable row level security;
alter table public.ep_members           enable row level security;
alter table public.ep_accounts          enable row level security;
alter table public.ep_balance_snapshots enable row level security;
alter table public.ep_budget_lines      enable row level security;
alter table public.ep_month_overrides   enable row level security;
alter table public.ep_expenses          enable row level security;
alter table public.ep_incomes           enable row level security;
alter table public.ep_loans             enable row level security;
alter table public.ep_goals             enable row level security;

-- Foyer : visible et renommable par ses membres. Création / adhésion
-- uniquement via les fonctions ep_create_household / ep_join_household.
drop policy if exists ep_households_select on public.ep_households;
create policy ep_households_select on public.ep_households
  for select to authenticated using (public.ep_is_member(id));

drop policy if exists ep_households_update on public.ep_households;
create policy ep_households_update on public.ep_households
  for update to authenticated
  using (public.ep_is_member(id)) with check (public.ep_is_member(id));

-- Membres : on voit les membres de son foyer (prénoms), on ne modifie que sa ligne.
drop policy if exists ep_members_select on public.ep_members;
create policy ep_members_select on public.ep_members
  for select to authenticated using (public.ep_is_member(household_id));

drop policy if exists ep_members_update on public.ep_members;
create policy ep_members_update on public.ep_members
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Tables de données : même règle perso / commun partout (lecture + écriture).
drop policy if exists ep_accounts_rw on public.ep_accounts;
create policy ep_accounts_rw on public.ep_accounts for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_budget_lines_rw on public.ep_budget_lines;
create policy ep_budget_lines_rw on public.ep_budget_lines for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_month_overrides_rw on public.ep_month_overrides;
create policy ep_month_overrides_rw on public.ep_month_overrides for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_expenses_rw on public.ep_expenses;
create policy ep_expenses_rw on public.ep_expenses for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_incomes_rw on public.ep_incomes;
create policy ep_incomes_rw on public.ep_incomes for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_loans_rw on public.ep_loans;
create policy ep_loans_rw on public.ep_loans for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

drop policy if exists ep_goals_rw on public.ep_goals;
create policy ep_goals_rw on public.ep_goals for all to authenticated
  using      (public.ep_can_access(scope, user_id, household_id))
  with check (public.ep_can_access(scope, user_id, household_id));

-- Relevés : autorisés si le compte parent est accessible (même règle via le compte).
drop policy if exists ep_balance_snapshots_rw on public.ep_balance_snapshots;
create policy ep_balance_snapshots_rw on public.ep_balance_snapshots for all to authenticated
  using (exists (
    select 1 from public.ep_accounts a
    where a.id = account_id and public.ep_can_access(a.scope, a.user_id, a.household_id)
  ))
  with check (exists (
    select 1 from public.ep_accounts a
    where a.id = account_id and public.ep_can_access(a.scope, a.user_id, a.household_id)
  ));


-- ---------------------------------------------------------------------
-- 5. Droits d'accès : rien pour les visiteurs non connectés (anon),
--    droits explicites pour les utilisateurs connectés
-- ---------------------------------------------------------------------

revoke all on public.ep_households, public.ep_members, public.ep_accounts,
              public.ep_balance_snapshots, public.ep_budget_lines, public.ep_month_overrides,
              public.ep_expenses, public.ep_incomes, public.ep_loans, public.ep_goals
  from anon, authenticated;

-- Foyer / membres : lecture, et modification limitée au nom / prénom
-- (impossible de changer de foyer, de slot ou de code d'invitation à la main).
grant select on public.ep_households, public.ep_members to authenticated;
grant update (name)       on public.ep_households to authenticated;
grant update (first_name) on public.ep_members    to authenticated;
grant select, insert, update, delete on
  public.ep_accounts, public.ep_balance_snapshots, public.ep_budget_lines, public.ep_month_overrides,
  public.ep_expenses, public.ep_incomes, public.ep_loans, public.ep_goals
  to authenticated;


-- ---------------------------------------------------------------------
-- 6. Créer / rejoindre le foyer
-- ---------------------------------------------------------------------

-- Code lisible de 8 caractères (sans 0/O/1/I pour éviter les confusions).
create or replace function public.ep_new_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  code  text := '';
begin
  for i in 0..7 loop
    code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return code;
end;
$$;

-- Prénom : paramètre, sinon celui saisi à l'inscription, sinon début de l'e-mail.
create or replace function public.ep_resolve_first_name(p_first_name text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(p_first_name), ''),
    nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''),
    split_part(u.email, '@', 1)
  )
  from auth.users u
  where u.id = auth.uid();
$$;

create or replace function public.ep_create_household(p_name text, p_first_name text default null)
returns text   -- le code d'invitation
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_hid  uuid;
  v_code text;
begin
  if v_uid is null then
    raise exception 'Non connecté.';
  end if;
  if exists (select 1 from public.ep_members where user_id = v_uid) then
    raise exception 'Tu fais déjà partie d''un foyer.';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Donne un nom au foyer.';
  end if;

  loop
    v_code := public.ep_new_invite_code();
    exit when not exists (select 1 from public.ep_households where invite_code = v_code);
  end loop;

  insert into public.ep_households (name, invite_code, created_by)
  values (trim(p_name), v_code, v_uid)
  returning id into v_hid;

  insert into public.ep_members (household_id, user_id, first_name, slot)
  values (v_hid, v_uid, public.ep_resolve_first_name(p_first_name), 1);

  return v_code;
end;
$$;

create or replace function public.ep_join_household(p_code text, p_first_name text default null)
returns uuid   -- l'id du foyer rejoint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_hid uuid;
begin
  if v_uid is null then
    raise exception 'Non connecté.';
  end if;
  if exists (select 1 from public.ep_members where user_id = v_uid) then
    raise exception 'Tu fais déjà partie d''un foyer.';
  end if;

  select id into v_hid
  from public.ep_households
  where invite_code = upper(trim(p_code))
  for update;

  if v_hid is null then
    raise exception 'Code d''invitation invalide.';
  end if;
  if (select count(*) from public.ep_members where household_id = v_hid) >= 2 then
    raise exception 'Ce foyer est déjà complet.';
  end if;

  insert into public.ep_members (household_id, user_id, first_name, slot)
  values (v_hid, v_uid, public.ep_resolve_first_name(p_first_name), 2);

  -- Foyer complet : le code ne sert plus, on le supprime.
  update public.ep_households set invite_code = null where id = v_hid;

  return v_hid;
end;
$$;

-- Seuls les utilisateurs connectés peuvent appeler ces fonctions.
revoke execute on function public.ep_is_member(uuid)                  from public, anon;
revoke execute on function public.ep_can_access(text, uuid, uuid)     from public, anon;
revoke execute on function public.ep_new_invite_code()                from public, anon, authenticated;
revoke execute on function public.ep_resolve_first_name(text)         from public, anon, authenticated;
revoke execute on function public.ep_create_household(text, text)     from public, anon;
revoke execute on function public.ep_join_household(text, text)       from public, anon;

grant execute on function public.ep_is_member(uuid)              to authenticated;
grant execute on function public.ep_can_access(text, uuid, uuid) to authenticated;
grant execute on function public.ep_create_household(text, text) to authenticated;
grant execute on function public.ep_join_household(text, text)   to authenticated;

-- ---------------------------------------------------------------------
-- Suite : exécuter ensuite supabase/migration_5bis.sql (colonnes ajoutées en phase 5 bis).
--         puis supabase/migration_keepalive.sql (fonction ep_ping pour le réveil GitHub Actions).
--         puis supabase/migration_holdings.sql (positions + part du commun), et test_rls_holdings.sql pour la vérifier.
--         puis supabase/migration_holdings_v2.sql (valeur saisie, PRU, versement mensuel, ETF capitalisant / distribuant).
--         puis supabase/migration_commun_index.sql (dépenses avancées dans le Commun, remboursements, suivi d'indice).
--         puis supabase/migration_holdings_v3.sql (copier Trade Republic : quantité facultative, investi = valeur − gain).
-- ---------------------------------------------------------------------
