-- =====================================================================
-- Wallet — TEST de confidentialité des catégories (ep_categories)
-- À exécuter dans Supabase > SQL Editor APRÈS migration_categories.sql.
-- Crée une catégorie perso de test pour membre 1 (membre n° 1) et une catégorie commune, se fait passer
-- pour membre 2 (membre n° 2) comme le ferait l'API, tente de lire / modifier / supprimer / créer,
-- puis efface ses données de test.
-- Résultat attendu : un tableau avec 6 lignes « OK ». Toute faille arrête le script avec « ÉCHEC ».
-- =====================================================================

do $$
declare
  v_hh     uuid;
  v_membre1  uuid;
  v_membre2  uuid;
  v_n      int;
  v_report text[] := '{}';
begin
  select household_id, user_id into v_hh, v_membre1 from public.ep_members where slot = 1 limit 1;
  select user_id into v_membre2 from public.ep_members where household_id = v_hh and slot = 2;
  if v_membre2 is null then
    raise exception 'membre 2 n''a pas encore rejoint le foyer : test impossible pour l''instant.';
  end if;

  -- Données de test (créées en administrateur, supprimées à la fin)
  insert into public.ep_categories (household_id, scope, user_id, code, name, category_group)
  values (v_hh, 'perso', v_membre1, 'c_testrls1', 'TEST RLS perso membre 1', 'envies'),
         (v_hh, 'commun', null,   'c_testrls2', 'TEST RLS commun',      'besoins');

  -- ---------- On devient membre 2 ----------
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre2, 'role', 'authenticated')::text, true);
  set local role authenticated;

  select count(*) into v_n from public.ep_categories where code = 'c_testrls1';
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 voit % catégorie(s) perso de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 1 — lecture : membre 2 ne voit pas la catégorie perso de membre 1'::text);

  update public.ep_categories set name = 'piraté' where code = 'c_testrls1';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 a modifié % catégorie(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 2 — modification : 0 ligne touchée'::text);

  delete from public.ep_categories where code = 'c_testrls1';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'ÉCHEC : membre 2 a supprimé % catégorie(s) de membre 1', v_n; end if;
  v_report := array_append(v_report, 'OK 3 — suppression : 0 ligne touchée'::text);

  begin
    insert into public.ep_categories (household_id, scope, user_id, code, name, category_group)
    values (v_hh, 'perso', v_membre1, 'c_testrls3', 'usurpation', 'envies');
    raise exception 'ÉCHEC : membre 2 a pu créer une catégorie au nom de membre 1';
  exception when insufficient_privilege then
    v_report := array_append(v_report, 'OK 4 — création au nom de membre 1 : refusée par la RLS'::text);
  end;

  select count(*) into v_n from public.ep_categories where code = 'c_testrls2';
  if v_n <> 1 then raise exception 'ÉCHEC : membre 2 devrait voir la catégorie commune (vu : %)', v_n; end if;
  v_report := array_append(v_report, 'OK 5 — membre 2 voit bien la catégorie du Commun'::text);

  -- ---------- Contrôle positif : membre 1 voit sa catégorie perso ----------
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', v_membre1, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into v_n from public.ep_categories where code = 'c_testrls1';
  if v_n <> 1 then raise exception 'ÉCHEC : membre 1 devrait voir sa catégorie (vu : %)', v_n; end if;
  v_report := array_append(v_report, 'OK 6 — membre 1 voit bien sa propre catégorie'::text);

  -- ---------- Nettoyage (en administrateur) ----------
  reset role;
  perform set_config('request.jwt.claims', '', true);
  delete from public.ep_categories where code in ('c_testrls1', 'c_testrls2', 'c_testrls3') and household_id = v_hh;

  create temp table if not exists ep_rls_report (resultat text);
  truncate ep_rls_report;
  insert into ep_rls_report select unnest(v_report);
end $$;

select resultat from ep_rls_report;
