-- =====================================================================
-- Wallet — TEST de confidentialité des positions (ep_holdings)
-- À exécuter dans Supabase > SQL Editor APRÈS migration_holdings.sql.
-- Le script crée un compte + une position de test pour membre 1 (membre n° 1), se fait passer
-- pour membre 2 (membre n° 2) exactement comme l'API le ferait, tente de lire / modifier /
-- supprimer / ajouter, puis efface ses données de test.
-- Résultat attendu : un tableau avec 5 lignes « OK ». Toute faille arrête le script avec « ÉCHEC ».
-- =====================================================================

do $$
declare
  v_hh     uuid;
  v_membre1  uuid;
  v_membre2  uuid;
  v_acc    uuid;
  v_n      int;
  v_report text[] := '{}';
begin
  select household_id, user_id into v_hh, v_membre1 from public.ep_members where slot = 1 limit 1;
  select user_id into v_membre2 from public.ep_members where household_id = v_hh and slot = 2;
  if v_membre2 is null then
    raise exception 'membre 2 n''a pas encore rejoint le foyer : test impossible pour l''instant.';
  end if;

  -- Données de test de membre 1 (créées en administrateur, supprimées à la fin)
  insert into public.ep_accounts (household_id, scope, user_id, name, type, balance)
  values (v_hh, 'perso', v_membre1, 'TEST RLS (supprimé à la fin)', 'crypto', 0)
  returning id into v_acc;
  insert into public.ep_holdings (household_id, scope, user_id, account_id, asset_type, symbol, quantity, invested)
  values (v_hh, 'perso', v_membre1, v_acc, 'crypto', 'bitcoin', 0.01, 500);

  -- ---------- On devient membre 2 (comme une requête de son navigateur) ----------
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre2, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.ep_holdings where user_id = v_membre1;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 voit % position(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 1 — lecture : membre 2 ne voit aucune position de membre 1'::text);

  update public.ep_holdings set quantity = 999 where user_id = v_membre1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 a modifié % position(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 2 — modification : 0 ligne touchée'::text);

  delete from public.ep_holdings where user_id = v_membre1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 a supprimé % position(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 3 — suppression : 0 ligne touchée'::text);

  begin
    insert into public.ep_holdings (household_id, scope, user_id, account_id, asset_type, symbol, quantity)
    values (v_hh, 'perso', v_membre2, v_acc, 'etf', 'CW8.PA', 1);
    raise exception 'ÉCHEC : membre 2 a pu ajouter une position dans le compte de membre 1';
  exception when insufficient_privilege then
    v_report := array_append(v_report, 'OK 4 — ajout dans le compte de membre 1 : refusé par la RLS'::text);
  end;

  -- ---------- Contrôle positif : membre 1 voit bien sa propre position ----------
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.ep_holdings where account_id = v_acc;
  if v_n <> 1 then raise exception 'ÉCHEC : membre 1 devrait voir sa position (vu : %)', v_n; end if;
  v_report := array_append(v_report, 'OK 5 — membre 1 voit bien sa propre position'::text);

  -- ---------- Nettoyage (en administrateur) ----------
  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.ep_accounts where id = v_acc;   -- supprime aussi la position (cascade)

  create temp table if not exists ep_rls_report (resultat text);
  truncate ep_rls_report;
  insert into ep_rls_report select unnest(v_report);
end $$;

select resultat from ep_rls_report;
