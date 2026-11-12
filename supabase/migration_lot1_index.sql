-- =====================================================================
-- Wallet — LOT 1, point 1.4 : index sur les clés étrangères
-- À exécuter dans Supabase > SQL Editor. Relançable, sans effet sur les données ni sur les règles d'accès.
-- Les colonnes déjà en tête d'un index existant (household_id, account_id…) ne sont pas dupliquées.
-- =====================================================================

-- user_id (propriétaire des lignes perso) : utilisé par toutes les règles d'accès
create index if not exists ep_accounts_user_idx        on public.ep_accounts (user_id);
create index if not exists ep_budget_lines_user_idx    on public.ep_budget_lines (user_id);
create index if not exists ep_month_overrides_user_idx on public.ep_month_overrides (user_id);
create index if not exists ep_expenses_user_idx        on public.ep_expenses (user_id);
create index if not exists ep_incomes_user_idx         on public.ep_incomes (user_id);
create index if not exists ep_loans_user_idx           on public.ep_loans (user_id);
create index if not exists ep_goals_user_idx           on public.ep_goals (user_id);
create index if not exists ep_holdings_user_idx        on public.ep_holdings (user_id);
create index if not exists ep_month_closes_user_idx    on public.ep_month_closes (user_id);

-- Autres références à un utilisateur
create index if not exists ep_households_created_by_idx       on public.ep_households (created_by);
create index if not exists ep_expenses_created_by_idx         on public.ep_expenses (created_by);
create index if not exists ep_expenses_paid_by_member_idx     on public.ep_expenses (paid_by_member);
create index if not exists ep_incomes_contributor_idx         on public.ep_incomes (contributor_user_id);
create index if not exists ep_settlements_from_user_idx       on public.ep_settlements (from_user);
create index if not exists ep_settlements_to_user_idx         on public.ep_settlements (to_user);
create index if not exists ep_settlements_created_by_idx      on public.ep_settlements (created_by);

-- Clés vers un foyer non couvertes par un index composite
create index if not exists ep_month_overrides_hh_idx on public.ep_month_overrides (household_id);
create index if not exists ep_month_closes_hh_idx    on public.ep_month_closes (household_id);
