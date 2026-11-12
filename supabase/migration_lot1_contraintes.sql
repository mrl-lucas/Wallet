-- =====================================================================
-- Wallet — LOT 1, point 1.5 : limites de saisie en base
-- À exécuter dans Supabase > SQL Editor. Relançable, sans perte de données.
-- Longueurs : noms 80, libellés 120, symboles / catégories 40 ; montants entre −1 et +1 milliard ;
-- taux entre −100 et 100 % ; dates entre 2000 et 2100 ; durées de prêt plausibles.
--
-- Chaque limite est d'abord ajoutée « NOT VALID » (elle s'applique aussitôt à toute nouvelle saisie),
-- puis vérifiée sur les lignes existantes. Si une ligne ancienne dépasse, la limite reste active pour
-- les nouvelles saisies et le tableau final indique laquelle corriger : rien n'est bloqué ni supprimé.
-- =====================================================================

do $$
declare
  c record;
  v_report text[] := '{}';
begin
  for c in
    select * from (values
      -- Textes
      ('ep_accounts',          'ep_accounts_name_len',        'length(name) <= 80'),
      ('ep_accounts',          'ep_accounts_type_len',        'length(type) <= 40'),
      ('ep_budget_lines',      'ep_budget_lines_label_len',   'length(label) <= 120'),
      ('ep_budget_lines',      'ep_budget_lines_cat_len',     'length(category) <= 40'),
      ('ep_budget_lines',      'ep_budget_lines_payer_len',   'payer_name is null or length(payer_name) <= 80'),
      ('ep_month_overrides',   'ep_month_overrides_cat_len',  'length(category) <= 40'),
      ('ep_expenses',          'ep_expenses_label_len',       'length(label) <= 120'),
      ('ep_expenses',          'ep_expenses_cat_len',         'length(category) <= 40'),
      ('ep_expenses',          'ep_expenses_payer_len',       'payer_name is null or length(payer_name) <= 80'),
      ('ep_incomes',           'ep_incomes_label_len',        'label is null or length(label) <= 120'),
      ('ep_incomes',           'ep_incomes_payer_len',        'payer_name is null or length(payer_name) <= 80'),
      ('ep_loans',             'ep_loans_name_len',           'length(name) <= 80'),
      ('ep_loans',             'ep_loans_payer_len',          'payer_name is null or length(payer_name) <= 80'),
      ('ep_goals',             'ep_goals_name_len',           'length(name) <= 80'),
      ('ep_holdings',          'ep_holdings_label_len',       'label is null or length(label) <= 120'),
      -- Montants (€)
      ('ep_accounts',          'ep_accounts_amounts',         'abs(balance) <= 1e9 and abs(monthly_contribution) <= 1e9 and (cap is null or abs(cap) <= 1e9)'),
      ('ep_balance_snapshots', 'ep_balance_snapshots_amount', 'abs(balance) <= 1e9'),
      ('ep_budget_lines',      'ep_budget_lines_amount',      'abs(amount) <= 1e9'),
      ('ep_month_overrides',   'ep_month_overrides_amount',   'abs(planned_amount) <= 1e9'),
      ('ep_expenses',          'ep_expenses_amount',          'abs(amount) <= 1e9'),
      ('ep_incomes',           'ep_incomes_amount',           'abs(amount) <= 1e9'),
      ('ep_loans',             'ep_loans_amounts',            '(capital is null or abs(capital) <= 1e9) and abs(insurance_monthly) <= 1e9
                                                              and (future_salary is null or abs(future_salary) <= 1e9)
                                                              and (remaining_capital is null or abs(remaining_capital) <= 1e9)
                                                              and (third_share is null or abs(third_share) <= 1e9)'),
      ('ep_goals',             'ep_goals_amounts',            'abs(target) <= 1e9 and abs(saved) <= 1e9'),
      ('ep_holdings',          'ep_holdings_amounts',         'abs(invested) <= 1e9 and abs(monthly_contribution) <= 1e9
                                                              and (manual_value is null or abs(manual_value) <= 1e9)
                                                              and (pru is null or abs(pru) <= 1e9)
                                                              and (quantity is null or quantity <= 1e12)'),
      ('ep_settlements',       'ep_settlements_amount',       'amount <= 1e9'),
      -- Taux (%)
      ('ep_accounts',          'ep_accounts_rate',            'annual_rate between -100 and 100'),
      ('ep_loans',             'ep_loans_rate',               'annual_rate is null or annual_rate between -100 and 100'),
      ('ep_holdings',          'ep_holdings_rates',           '(total_return is null or total_return between -100 and 100)
                                                              and (price_return is null or price_return between -100 and 100)
                                                              and (dividend_yield is null or dividend_yield between -100 and 100)'),
      -- Durées
      ('ep_loans',             'ep_loans_durations',          '(duration_months is null or duration_months <= 600) and deferral_months between 0 and 240'),
      -- Dates plausibles
      ('ep_expenses',          'ep_expenses_date',            'date between date ''2000-01-01'' and date ''2100-12-31'''),
      ('ep_balance_snapshots', 'ep_balance_snapshots_month',  'month between date ''2000-01-01'' and date ''2100-12-01'''),
      ('ep_month_overrides',   'ep_month_overrides_month',    'month between date ''2000-01-01'' and date ''2100-12-01'''),
      ('ep_loans',             'ep_loans_start',              'start_date is null or start_date between date ''2000-01-01'' and date ''2100-12-31'''),
      ('ep_goals',             'ep_goals_due',                'due_date is null or due_date between date ''2000-01-01'' and date ''2100-12-31'''),
      ('ep_incomes',           'ep_incomes_received',         'received_on is null or received_on between date ''2000-01-01'' and date ''2100-12-31'''),
      ('ep_holdings',          'ep_holdings_dates',           '(manual_value_date is null or manual_value_date between date ''2000-01-01'' and date ''2100-12-31'')
                                                              and (first_purchase is null or first_purchase between date ''2000-01-01'' and date ''2100-12-31'')'),
      ('ep_settlements',       'ep_settlements_month',        'month between date ''2000-01-01'' and date ''2100-12-01'''),
      ('ep_month_closes',      'ep_month_closes_month',       'month between date ''2000-01-01'' and date ''2100-12-01''')
    ) as t(tbl, con, expr)
  loop
    if not exists (select 1 from pg_constraint where conname = c.con and conrelid = ('public.' || c.tbl)::regclass) then
      execute format('alter table public.%I add constraint %I check (%s) not valid', c.tbl, c.con, c.expr);
    end if;
    begin
      execute format('alter table public.%I validate constraint %I', c.tbl, c.con);
    exception when check_violation then
      v_report := array_append(v_report, format('À corriger : %s — des lignes existantes dépassent « %s »', c.tbl, c.con));
    end;
  end loop;

  create temp table if not exists ep_constraints_report (resultat text);
  truncate ep_constraints_report;
  insert into ep_constraints_report
    select unnest(case when cardinality(v_report) = 0 then array['OK — toutes les limites sont actives et vérifiées'] else v_report end);
end $$;

select resultat from ep_constraints_report;
