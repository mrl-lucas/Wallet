-- =====================================================================
-- Wallet — migration « positions v2 »
-- Valeur saisie à la main (ETF / actions), PRU, versement mensuel programmé,
-- ETF capitalisant / distribuant. À exécuter dans Supabase > SQL Editor AVANT de publier
-- la nouvelle version d'index.html. Relançable sans erreur, sans perte de données,
-- uniquement sur ep_holdings. Les règles d'accès (RLS) ne changent pas.
-- =====================================================================

-- 1. Mode de prix : 'saisie' (valeur lue dans Trade Republic) ou 'auto' (CoinGecko / Twelve Data).
--    À la création de la colonne, les cryptos existantes passent en 'auto' (Bitcoin via CoinGecko).
do $$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'ep_holdings' and column_name = 'price_mode') then
    alter table public.ep_holdings
      add column price_mode text not null default 'saisie' check (price_mode in ('saisie', 'auto'));
    update public.ep_holdings set price_mode = 'auto' where asset_type = 'crypto';
  end if;
end $$;

alter table public.ep_holdings
  -- Valeur actuelle saisie à la main, avec sa date
  add column if not exists manual_value         numeric(14,2) check (manual_value >= 0),
  add column if not exists manual_value_date    date,
  -- Prix de revient unitaire (investi = quantité × PRU ; la colonne invested reste remplie)
  add column if not exists pru                  numeric(20,6) check (pru >= 0),
  -- Investissement programmé (€ / mois)
  add column if not exists monthly_contribution numeric(14,2) not null default 0 check (monthly_contribution >= 0),
  -- ETF : capitalisant / distribuant et rendements estimés (% par an)
  add column if not exists distribution         text check (distribution in ('capitalisant', 'distribuant')),
  add column if not exists total_return         numeric(6,3),   -- capitalisant (et crypto / action) : rendement total
  add column if not exists price_return         numeric(6,3),   -- distribuant : rendement du prix
  add column if not exists dividend_yield       numeric(6,3),   -- distribuant : rendement du dividende
  add column if not exists dividends_reinvested boolean not null default true;
