-- =====================================================================
-- Wallet — migration phase 5 bis
-- À exécuter UNE FOIS schema.sql déjà en place, AVANT d'utiliser la nouvelle version
-- d'index.html. Relançable sans erreur, aucune perte de données : uniquement des
-- ALTER sur des tables ep_ (ajout de colonnes, assouplissement de contraintes).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Prêts : plusieurs prêts, mode « échéancier », taux optionnel, payé par un tiers
-- ---------------------------------------------------------------------

alter table public.ep_loans
  add column if not exists mode text not null default 'calcul'
    check (mode in ('calcul', 'echeancier')),
  -- Paliers du mode échéancier : [{ "from": "2028-09-01", "to": "2033-08-01", "amount": 180 }]
  add column if not exists schedule jsonb not null default '[]'::jsonb,
  add column if not exists remaining_capital numeric(14,2),          -- optionnel (mode échéancier)
  add column if not exists paid_by text not null default 'moi'
    check (paid_by in ('moi', 'tiers', 'partage')),
  add column if not exists payer_name text,                          -- ex. « Parents »
  add column if not exists third_share_type text
    check (third_share_type in ('montant', 'pourcentage')),
  add column if not exists third_share numeric(14,2);                -- € ou % pris en charge par le tiers

-- En mode échéancier, capital / durée / début ne sont pas nécessaires ; le taux devient optionnel.
alter table public.ep_loans alter column capital         drop not null;
alter table public.ep_loans alter column duration_months drop not null;
alter table public.ep_loans alter column start_date      drop not null;
alter table public.ep_loans alter column annual_rate     drop not null;


-- ---------------------------------------------------------------------
-- 2. Dépenses et lignes de budget payées par un tiers ou avancées
-- ---------------------------------------------------------------------

alter table public.ep_expenses
  add column if not exists paid_by text not null default 'moi'
    check (paid_by in ('moi', 'tiers', 'avance')),
  add column if not exists payer_name text,
  add column if not exists reimbursed boolean not null default false;

alter table public.ep_budget_lines
  add column if not exists paid_by text not null default 'moi'
    check (paid_by in ('moi', 'tiers', 'avance')),
  add column if not exists payer_name text,
  add column if not exists reimbursed boolean not null default false;


-- ---------------------------------------------------------------------
-- 3. Aide familiale / argent de poche
-- ---------------------------------------------------------------------

alter table public.ep_incomes drop constraint if exists ep_incomes_kind_check;
alter table public.ep_incomes add constraint ep_incomes_kind_check
  check (kind in ('salaire', 'contribution', 'aide_famille', 'autre'));

alter table public.ep_incomes
  add column if not exists payer_name text,                          -- ex. « Parents »
  add column if not exists recurrence text not null default 'mensuel'
    check (recurrence in ('mensuel', 'ponctuel')),
  add column if not exists received_on date;                         -- date de l'aide ponctuelle
