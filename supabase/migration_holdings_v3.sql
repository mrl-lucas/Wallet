-- =====================================================================
-- Wallet — migration « positions v3 : copier Trade Republic »
-- À exécuter dans Supabase > SQL Editor AVANT de publier la nouvelle version d'index.html.
-- Relançable sans erreur, sans perte de données, uniquement sur ep_holdings (RLS inchangée).
-- =====================================================================

-- La quantité devient facultative (une position peut être saisie par valeur + gain uniquement).
alter table public.ep_holdings alter column quantity drop not null;

-- Origine du montant investi :
--   'tr'  = déduit de la saisie Trade Republic (investi = valeur − gain €), jamais recalculé par le PRU ;
--   'pru' = quantité × PRU (ou montant total saisi) ; NULL = positions créées avant cette migration.
alter table public.ep_holdings
  add column if not exists entry_mode text check (entry_mode in ('tr', 'pru'));
