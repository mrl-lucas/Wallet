-- =====================================================================
-- Wallet — LOT 1, points 1.2 et 1.3 : fonctions de sécurité dans un schéma privé
-- À exécuter dans Supabase > SQL Editor. Relançable, sans perte de données, en UNE transaction :
-- si une étape échoue, rien n'est appliqué (les anciennes règles restent en place).
--
-- 1.2  ep_is_member / ep_can_access (SECURITY DEFINER) quittent le schéma public, que l'API publie,
--      pour ep_private, qu'elle ne publie pas. ep_resolve_first_name et ep_new_invite_code suivent.
--      Les 16 règles d'accès sont réécrites à l'identique avec les fonctions privées
--      (même effet : perso = propriétaire seul, commun = membres du foyer).
--      ep_create_household / ep_join_household restent dans public (appelables, voulu) ; ep_ping aussi.
-- 1.3  ep_members_update : (select auth.uid()) au lieu de auth.uid() (évalué une seule fois).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Schéma privé : utilisable par les règles d'accès, invisible pour l'API
--    (seuls « public » et « graphql_public » sont publiés par l'API Supabase).
-- ---------------------------------------------------------------------
create schema if not exists ep_private;
revoke all on schema ep_private from public;
revoke all on schema ep_private from anon;
grant usage on schema ep_private to authenticated;   -- nécessaire pour que les règles fonctionnent

-- Appartenance au foyer. SECURITY DEFINER : lit ep_members sans repasser par sa propre règle.
create or replace function ep_private.is_member(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.ep_members
    where household_id = p_household_id
      and user_id = (select auth.uid())
  );
$$;

-- Règle unique : perso → propriétaire (membre du foyer) ; commun → tout membre du foyer.
create or replace function ep_private.can_access(p_scope text, p_user_id uuid, p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case p_scope
    when 'perso'  then p_user_id = (select auth.uid()) and ep_private.is_member(p_household_id)
    when 'commun' then ep_private.is_member(p_household_id)
    else false
  end;
$$;

-- Code d'invitation lisible de 8 caractères (sans 0/O/1/I).
create or replace function ep_private.new_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
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
create or replace function ep_private.resolve_first_name(p_first_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    nullif(trim(p_first_name), ''),
    nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''),
    split_part(u.email, '@', 1)
  )
  from auth.users u
  where u.id = (select auth.uid());
$$;

revoke all on all functions in schema ep_private from public, anon, authenticated;
grant execute on function ep_private.is_member(uuid)              to authenticated;
grant execute on function ep_private.can_access(text, uuid, uuid) to authenticated;
-- new_invite_code / resolve_first_name : appelées seulement par les fonctions du foyer (pas de droit direct).


-- ---------------------------------------------------------------------
-- 2. Créer / rejoindre le foyer : mêmes fonctions publiques, qui appellent désormais ep_private
--    (ep_join_household sera remplacée par sa version « statut » dans migration_lot1_invitation.sql)
-- ---------------------------------------------------------------------
create or replace function public.ep_create_household(p_name text, p_first_name text default null)
returns text   -- le code d'invitation
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_hid  uuid;
  v_code text;
begin
  if v_uid is null then raise exception 'Non connecté.'; end if;
  if exists (select 1 from public.ep_members where user_id = v_uid) then
    raise exception 'Tu fais déjà partie d''un foyer.';
  end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Donne un nom au foyer.'; end if;

  loop
    v_code := ep_private.new_invite_code();
    exit when not exists (select 1 from public.ep_households where invite_code = v_code);
  end loop;

  insert into public.ep_households (name, invite_code, created_by)
  values (trim(p_name), v_code, v_uid)
  returning id into v_hid;

  insert into public.ep_members (household_id, user_id, first_name, slot)
  values (v_hid, v_uid, ep_private.resolve_first_name(p_first_name), 1);

  return v_code;
end;
$$;

do $$
begin
  -- Version d'origine (renvoie uuid) : mise à jour seulement si la version « statut » n'est pas déjà là
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'ep_join_household'
               and pg_get_function_result(p.oid) = 'uuid') then
    execute $f$
      create or replace function public.ep_join_household(p_code text, p_first_name text default null)
      returns uuid
      language plpgsql
      security definer
      set search_path = ''
      as $body$
      declare
        v_uid uuid := (select auth.uid());
        v_hid uuid;
      begin
        if v_uid is null then raise exception 'Non connecté.'; end if;
        if exists (select 1 from public.ep_members where user_id = v_uid) then
          raise exception 'Tu fais déjà partie d''un foyer.';
        end if;
        select id into v_hid from public.ep_households where invite_code = upper(trim(p_code)) for update;
        if v_hid is null then raise exception 'Code d''invitation invalide.'; end if;
        if (select count(*) from public.ep_members where household_id = v_hid) >= 2 then
          raise exception 'Ce foyer est déjà complet.';
        end if;
        insert into public.ep_members (household_id, user_id, first_name, slot)
        values (v_hid, v_uid, ep_private.resolve_first_name(p_first_name), 2);
        update public.ep_households set invite_code = null where id = v_hid;
        return v_hid;
      end;
      $body$;
    $f$;
  end if;
end $$;


-- ---------------------------------------------------------------------
-- 3. Les 16 règles d'accès, réécrites avec ep_private (même effet qu'avant)
-- ---------------------------------------------------------------------
drop policy if exists ep_households_select on public.ep_households;
create policy ep_households_select on public.ep_households
  for select to authenticated using (ep_private.is_member(id));

drop policy if exists ep_households_update on public.ep_households;
create policy ep_households_update on public.ep_households
  for update to authenticated
  using (ep_private.is_member(id)) with check (ep_private.is_member(id));

drop policy if exists ep_members_select on public.ep_members;
create policy ep_members_select on public.ep_members
  for select to authenticated using (ep_private.is_member(household_id));

-- 1.3 : (select auth.uid()) est évalué une fois par requête, pas à chaque ligne
drop policy if exists ep_members_update on public.ep_members;
create policy ep_members_update on public.ep_members
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

do $$
declare t text;
begin
  foreach t in array array['ep_accounts', 'ep_budget_lines', 'ep_month_overrides', 'ep_expenses', 'ep_incomes',
                           'ep_loans', 'ep_goals', 'ep_settlements', 'ep_month_closes', 'ep_categories']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_rw', t);
    execute format('create policy %I on public.%I for all to authenticated
                      using      (ep_private.can_access(scope, user_id, household_id))
                      with check (ep_private.can_access(scope, user_id, household_id))', t || '_rw', t);
  end loop;
end $$;

-- Relevés : autorisés si le compte parent est accessible
drop policy if exists ep_balance_snapshots_rw on public.ep_balance_snapshots;
create policy ep_balance_snapshots_rw on public.ep_balance_snapshots for all to authenticated
  using (exists (
    select 1 from public.ep_accounts a
    where a.id = account_id and ep_private.can_access(a.scope, a.user_id, a.household_id)
  ))
  with check (exists (
    select 1 from public.ep_accounts a
    where a.id = account_id and ep_private.can_access(a.scope, a.user_id, a.household_id)
  ));

-- Positions : même espace et même propriétaire que le compte parent
drop policy if exists ep_holdings_rw on public.ep_holdings;
create policy ep_holdings_rw on public.ep_holdings for all to authenticated
  using (
    ep_private.can_access(scope, user_id, household_id)
    and exists (select 1 from public.ep_accounts a
                where a.id = account_id
                  and ep_private.can_access(a.scope, a.user_id, a.household_id))
  )
  with check (
    ep_private.can_access(scope, user_id, household_id)
    and exists (select 1 from public.ep_accounts a
                where a.id = account_id
                  and a.household_id = ep_holdings.household_id
                  and a.scope = ep_holdings.scope
                  and a.user_id is not distinct from ep_holdings.user_id)
  );


-- ---------------------------------------------------------------------
-- 4. Les anciennes fonctions publiques ne servent plus : on les retire de l'API
-- ---------------------------------------------------------------------
drop function if exists public.ep_can_access(text, uuid, uuid);
drop function if exists public.ep_is_member(uuid);
drop function if exists public.ep_resolve_first_name(text);
drop function if exists public.ep_new_invite_code();

revoke execute on function public.ep_create_household(text, text) from public, anon;
grant  execute on function public.ep_create_household(text, text) to authenticated;

commit;
