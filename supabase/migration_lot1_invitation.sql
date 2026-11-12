-- =====================================================================
-- Wallet — LOT 1, point 1.6 : code d'invitation qui expire, essais limités
-- À exécuter dans Supabase > SQL Editor APRÈS migration_lot1_prive.sql. Relançable, en une transaction.
--
-- - Le code expire 7 jours après sa création ; un membre peut le régénérer (ep_regenerate_invite),
--   sauf si le foyer a déjà 2 membres.
-- - Au plus 5 essais ratés par utilisateur (auth.uid()) et par heure ; au-delà, refus.
-- - ep_join_household renvoie désormais un STATUT (jsonb) au lieu de lever une erreur : un essai raté
--   est ainsi bien enregistré (une erreur annulerait l'enregistrement de l'essai).
--   Statuts : ok, invalid, expired, full, too_many, already_member, not_signed_in.
-- =====================================================================

begin;

alter table public.ep_households add column if not exists invite_expires_at timestamptz;
-- Codes existants encore actifs : 7 jours à partir de maintenant
update public.ep_households
   set invite_expires_at = now() + interval '7 days'
 where invite_code is not null and invite_expires_at is null;

-- Essais pour rejoindre un foyer (aucun accès direct : seules les fonctions y écrivent)
create table if not exists public.ep_join_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null,
  attempted_at timestamptz not null default now(),
  success      boolean not null default false
);
create index if not exists ep_join_attempts_user_time_idx on public.ep_join_attempts (user_id, attempted_at);
alter table public.ep_join_attempts enable row level security;   -- aucune règle : personne ne lit ni n'écrit via l'API
revoke all on public.ep_join_attempts from anon, authenticated;

-- Créer le foyer : le code expire dans 7 jours
create or replace function public.ep_create_household(p_name text, p_first_name text default null)
returns text
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
  insert into public.ep_households (name, invite_code, invite_expires_at, created_by)
  values (trim(p_name), v_code, now() + interval '7 days', v_uid)
  returning id into v_hid;
  insert into public.ep_members (household_id, user_id, first_name, slot)
  values (v_hid, v_uid, ep_private.resolve_first_name(p_first_name), 1);
  return v_code;
end;
$$;

-- Rejoindre : nouvelle version qui renvoie un statut (la signature de retour change → drop puis create)
drop function if exists public.ep_join_household(text, text);
create function public.ep_join_household(p_code text, p_first_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_hid     uuid;
  v_expires timestamptz;
  v_failed  int;
begin
  if v_uid is null then return jsonb_build_object('status', 'not_signed_in'); end if;
  if exists (select 1 from public.ep_members where user_id = v_uid) then
    return jsonb_build_object('status', 'already_member');
  end if;

  select count(*) into v_failed from public.ep_join_attempts
   where user_id = v_uid and not success and attempted_at > now() - interval '1 hour';
  if v_failed >= 5 then return jsonb_build_object('status', 'too_many'); end if;

  select id, invite_expires_at into v_hid, v_expires
    from public.ep_households where invite_code = upper(trim(p_code)) for update;

  if v_hid is null then
    insert into public.ep_join_attempts (user_id) values (v_uid);
    return jsonb_build_object('status', 'invalid', 'left', 4 - v_failed);
  end if;
  if v_expires is not null and v_expires < now() then
    insert into public.ep_join_attempts (user_id) values (v_uid);
    return jsonb_build_object('status', 'expired');
  end if;
  if (select count(*) from public.ep_members where household_id = v_hid) >= 2 then
    insert into public.ep_join_attempts (user_id) values (v_uid);
    return jsonb_build_object('status', 'full');
  end if;

  insert into public.ep_members (household_id, user_id, first_name, slot)
  values (v_hid, v_uid, ep_private.resolve_first_name(p_first_name), 2);
  update public.ep_households set invite_code = null, invite_expires_at = null where id = v_hid;   -- foyer complet
  insert into public.ep_join_attempts (user_id, success) values (v_uid, true);
  return jsonb_build_object('status', 'ok', 'household_id', v_hid);
end;
$$;

-- Régénérer le code (membre du foyer uniquement ; refusé si le foyer a déjà 2 membres)
create or replace function public.ep_regenerate_invite()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_hid  uuid;
  v_code text;
  v_exp  timestamptz := now() + interval '7 days';
begin
  select household_id into v_hid from public.ep_members where user_id = v_uid;
  if v_hid is null then return jsonb_build_object('status', 'not_member'); end if;
  if (select count(*) from public.ep_members where household_id = v_hid) >= 2 then
    return jsonb_build_object('status', 'full');
  end if;
  loop
    v_code := ep_private.new_invite_code();
    exit when not exists (select 1 from public.ep_households where invite_code = v_code);
  end loop;
  update public.ep_households set invite_code = v_code, invite_expires_at = v_exp where id = v_hid;
  return jsonb_build_object('status', 'ok', 'code', v_code, 'expires_at', v_exp);
end;
$$;

revoke execute on function public.ep_join_household(text, text) from public, anon;
revoke execute on function public.ep_regenerate_invite()         from public, anon;
grant  execute on function public.ep_join_household(text, text) to authenticated;
grant  execute on function public.ep_regenerate_invite()         to authenticated;

commit;
