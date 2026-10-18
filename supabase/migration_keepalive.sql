-- =====================================================================
-- Wallet — fonction de « réveil » pour GitHub Actions
-- À exécuter une fois dans Supabase > SQL Editor. Relançable sans erreur.
-- Le workflow .github/workflows/keepalive.yml appelle ep_ping() tous les 3 jours avec la
-- clé publishable, pour que le projet gratuit ne soit pas mis en pause faute d'activité.
-- La fonction ne lit aucune table : elle renvoie seulement l'heure du serveur.
-- =====================================================================

create or replace function public.ep_ping()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select now();
$$;

revoke execute on function public.ep_ping() from public;
grant execute on function public.ep_ping() to anon, authenticated;
