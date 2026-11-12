-- =====================================================================
-- Wallet — TEST du LOT 1 (sécurité)
-- À exécuter dans Supabase > SQL Editor APRÈS les 4 migrations du lot 1.
-- Ne modifie pas tes données : il lit tes lignes existantes, et ses rares données de test
-- (un faux foyer, des essais d'invitation) sont effacées à la fin.
-- Résultat attendu : un tableau de lignes « OK ». Toute faille arrête le script avec « ÉCHEC ».
-- =====================================================================

do $$
declare
  v_hh     uuid;
  v_membre1  uuid;
  v_membre2  uuid;
  v_fake1  uuid := gen_random_uuid();   -- utilisateurs fictifs, hors foyer (essais d'invitation)
  v_fake2  uuid := gen_random_uuid();
  v_test_hh uuid;
  v_n      int;
  v_admin  int;
  v_res    jsonb;
  t        text;
  v_report text[] := '{}';
begin
  select household_id, user_id into v_hh, v_membre1 from public.ep_members where slot = 1 limit 1;
  select user_id into v_membre2 from public.ep_members where household_id = v_hh and slot = 2;
  if v_membre2 is null then raise exception 'membre 2 n''a pas encore rejoint le foyer : test impossible.'; end if;

  -- ---------- 1. Fonctions : plus rien de sensible dans le schéma public (publié par l'API) ----------
  if to_regprocedure('public.ep_is_member(uuid)') is not null
     or to_regprocedure('public.ep_can_access(text,uuid,uuid)') is not null
     or to_regprocedure('public.ep_resolve_first_name(text)') is not null
     or to_regprocedure('public.ep_new_invite_code()') is not null then
    raise exception 'ÉCHEC : une ancienne fonction de sécurité est encore dans public';
  end if;
  v_report := array_append(v_report, 'OK 1 — ep_is_member / ep_can_access / resolve / invite_code ne sont plus dans public'::text);

  if has_schema_privilege('anon', 'ep_private', 'usage')
     or has_function_privilege('anon', 'ep_private.can_access(text,uuid,uuid)', 'execute') then
    raise exception 'ÉCHEC : les visiteurs non connectés ont accès à ep_private';
  end if;
  if not has_function_privilege('authenticated', 'ep_private.can_access(text,uuid,uuid)', 'execute')
     or not has_schema_privilege('authenticated', 'ep_private', 'usage') then
    raise exception 'ÉCHEC : les règles d''accès ne peuvent pas utiliser ep_private';
  end if;
  if has_function_privilege('authenticated', 'ep_private.resolve_first_name(text)', 'execute') then
    raise exception 'ÉCHEC : resolve_first_name est appelable directement';
  end if;
  if has_table_privilege('authenticated', 'public.ep_join_attempts', 'select') then
    raise exception 'ÉCHEC : la table des essais d''invitation est lisible';
  end if;
  v_report := array_append(v_report, 'OK 2 — ep_private : interdit aux visiteurs, utilisable par les règles ; essais illisibles'::text);

  if not has_function_privilege('anon', 'public.ep_ping()', 'execute') then
    raise exception 'ÉCHEC : ep_ping n''est plus appelable (réveil GitHub)';
  end if;
  v_report := array_append(v_report, 'OK 3 — ep_ping reste appelable pour le réveil'::text);

  -- ---------- 2. Confidentialité table par table, sur tes vraies données ----------
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre2, 'role', 'authenticated')::text, true);
  foreach t in array array['ep_accounts', 'ep_budget_lines', 'ep_month_overrides', 'ep_expenses', 'ep_incomes',
                           'ep_loans', 'ep_goals', 'ep_holdings', 'ep_month_closes', 'ep_categories']
  loop
    reset role;
    execute format('select count(*) from public.%I where scope = ''perso'' and user_id = $1', t) into v_admin using v_membre1;
    set local role authenticated;
    execute format('select count(*) from public.%I where scope = ''perso'' and user_id = $1', t) into v_n using v_membre1;
    if v_n <> 0 then raise exception 'ÉCHEC : membre 2 voit % ligne(s) perso de membre 1 dans %', v_n, t; end if;
    execute format('select count(*) from public.%I where scope = ''commun''', t) into v_n;
    reset role;
    execute format('select count(*) from public.%I where scope = ''commun'' and household_id = $1', t) into v_admin using v_hh;
    if v_n <> v_admin then raise exception 'ÉCHEC : membre 2 devrait voir % ligne(s) communes dans % (vu : %)', v_admin, t, v_n; end if;
  end loop;
  reset role;
  select count(*) into v_admin from public.ep_balance_snapshots s join public.ep_accounts a on a.id = s.account_id
   where a.scope = 'perso' and a.user_id = v_membre1;
  set local role authenticated;
  select count(*) into v_n from public.ep_balance_snapshots s join public.ep_accounts a on a.id = s.account_id
   where a.user_id = v_membre1;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 voit % relevé(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, format('OK 4 — membre 2 ne voit aucune ligne perso de membre 1 (11 tables, dont %s relevés) et voit tout le Commun', v_admin));

  -- Contrôle positif : membre 1 voit bien ses propres lignes
  reset role;
  select count(*) into v_admin from public.ep_accounts where scope = 'perso' and user_id = v_membre1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.ep_accounts where scope = 'perso' and user_id = v_membre1;
  if v_n <> v_admin then raise exception 'ÉCHEC : membre 1 devrait voir ses % compte(s) perso (vu : %)', v_admin, v_n; end if;
  v_report := array_append(v_report, format('OK 5 — membre 1 voit bien ses %s compte(s) perso', v_admin));

  -- ---------- 3. Invitation ----------
  -- Foyer complet : régénérer est refusé
  v_res := public.ep_regenerate_invite();
  if v_res->>'status' <> 'full' then raise exception 'ÉCHEC : régénération acceptée pour un foyer complet (%)', v_res; end if;
  v_report := array_append(v_report, 'OK 6 — régénérer le code est refusé quand le foyer a 2 membres'::text);

  -- Code expiré (faux foyer de test, effacé à la fin)
  reset role;
  insert into public.ep_households (name, invite_code, invite_expires_at)
  values ('TEST LOT 1 (effacé à la fin)', 'ZZZZZZZZ', now() - interval '1 day') returning id into v_test_hh;
  perform set_config('request.jwt.claims', json_build_object('sub', v_fake2, 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_res := public.ep_join_household('ZZZZZZZZ');
  if v_res->>'status' <> 'expired' then raise exception 'ÉCHEC : code expiré accepté (%)', v_res; end if;
  v_report := array_append(v_report, 'OK 7 — un code de plus de 7 jours est refusé (« expired »)'::text);

  -- 5 essais ratés, puis blocage
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_fake1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  for i in 1..5 loop
    v_res := public.ep_join_household('AAAAAAA' || i);
    if v_res->>'status' <> 'invalid' then raise exception 'ÉCHEC : essai % → %', i, v_res; end if;
  end loop;
  v_res := public.ep_join_household('AAAAAAA6');
  if v_res->>'status' <> 'too_many' then raise exception 'ÉCHEC : 6e essai raté non bloqué (%)', v_res; end if;
  select count(*) into v_n from public.ep_accounts;   -- un inconnu ne voit aucune donnée
  if v_n <> 0 then raise exception 'ÉCHEC : un utilisateur hors foyer voit % compte(s)', v_n; end if;
  v_report := array_append(v_report, 'OK 8 — après 5 essais ratés en 1 heure, le 6e est bloqué (« too_many ») ; un inconnu ne voit rien'::text);

  -- ---------- Nettoyage (en administrateur) ----------
  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.ep_join_attempts where user_id in (v_fake1, v_fake2);
  delete from public.ep_households where id = v_test_hh;

  create temp table if not exists ep_rls_report (resultat text);
  truncate ep_rls_report;
  insert into ep_rls_report select unnest(v_report);
end $$;

select resultat from ep_rls_report;
