// Wallet — tests des calculs (fonctions pures d'index.html), sans navigateur ni Supabase.
// Lancer depuis le dossier du projet :  node tests/calculs.test.js
// Chaque test rejoue un exemple chiffré validé à une phase précédente. Code de sortie 1 si un test échoue.
'use strict';
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const block = (start, end) => {
  const a = html.indexOf(start), b = html.indexOf(end);
  if (a < 0 || b < 0) throw new Error(`Bloc introuvable : ${start}`);
  return html.slice(a, b);
};
const parseSrc = html.slice(html.indexOf('    function parseAmount'), html.indexOf('    // ================== Mois et pourcentages'));
const T = new Function(parseSrc + block('// <projection>', '// </projection>') + block('// <budget>', '// </budget>')
  + block('// <loan>', '// </loan>') + block('// <holdings>', '// </holdings>')
  + `; return { parseAmount, projectSavings, capGauge, CATEGORIES, CAT_REGISTRY, catLookup, computeBudget, computeMonth,
      countsForMe, thirdPartySummary, commonBalance, absMonth, computeLoan, goalProgress, scheduleLoan, loanDue, loanSplit,
      monthIncome, valueAccount, positionsForProjection, positionRate, dividendIncome, holdingInvested, fromTradeRepublic,
      monthPosition, monthSummary, deflate };`)();

let failed = 0, passed = 0;
function eq(label, got, want, tol = 0.01) {
  const ok = typeof want === 'number' ? Math.abs(got - want) <= tol : got === want;
  if (ok) passed++; else failed++;
  console.log(`${ok ? 'OK   ' : 'ÉCHEC'} ${label} : ${typeof got === 'number' ? got.toFixed(2) : got}${ok ? '' : ` (attendu ${want})`}`);
}
const section = (t) => console.log(`\n— ${t}`);

section('Phase 3 — projection de l’épargne');
const p3 = T.projectSavings([
  { id: 'la', name: 'Livret A', balance: 20000, monthly_contribution: 200, annual_rate: 1.7, cap: 22950 },
  { id: 'tr', name: 'Trade Republic', balance: 5000, monthly_contribution: 150, annual_rate: 6, cap: null }], 240);
eq('1er mois', p3.points[1].total, 25403.33);
eq('capital à 1 an', p3.points[12].total, 29920.17);
eq('capital à 10 ans', p3.points[120].total, 60382.37);
eq('capital à 20 ans', p3.points[240].total, 117505.12);
eq('Livret A plein au mois', p3.caps[0].month, 13);
const i = 0.06 / 12, f = Math.pow(1 + i, 120);
eq('Trade Republic seul = formule fermée', T.projectSavings([{ id: 'tr', balance: 5000, monthly_contribution: 150, annual_rate: 6 }], 120).points[120].total,
   5000 * f + 150 * (f - 1) / i);
const peaCap = T.projectSavings([{ id: 'p', balance: 160000, monthly_contribution: 500, annual_rate: 0, cap: 150000, cap_on_contributions: true, contributions_base: 149000 }], 6);
eq('PEA : plafond sur les versements (mois)', peaCap.caps[0].month, 3);

section('Phase 4 — budget et mois');
const b4 = T.computeBudget({ income: 2400, autos: { epargne: 350, virement_commun: 400, pret: 0 }, lines: [
  { category: 'logement', amount: 750 }, { category: 'alimentation', amount: 300 }, { category: 'transport', amount: 86.4 },
  { category: 'abonnements', amount: 45 }, { category: 'loisirs', amount: 120 }] });
eq('total prévu', b4.total, 2051.4);
eq('reste à vivre', b4.rest, 348.6);
eq('besoins', b4.groups.besoins, 1581.4);
eq('dépenses prévues (fonds d’urgence)', b4.monthlyExpenses, 1701.4);
const m4 = T.computeMonth({ plannedByCat: b4.byCat, overrides: [{ category: 'alimentation', planned_amount: 350 }], expenses: [
  { category: 'alimentation', amount: 82.5 }, { category: 'alimentation', amount: 64.2 }, { category: 'transport', amount: 95 }, { category: 'loisirs', amount: 110 }] });
eq('réel du mois', m4.real, 1101.7);
eq('prévu du mois', m4.planned, 2101.4);
eq('transport dépassé', m4.rows.find((r) => r.category === 'transport').level, 'over');
eq('loisirs à 92 % (orange)', m4.rows.find((r) => r.category === 'loisirs').level, 'near');

section('Phase 5 — prêt et objectifs');
const L = T.computeLoan({ capital: 20000, annual_rate: 1.5, duration_months: 84, start_date: '2028-09-01', insurance_monthly: 5, deferral_type: 'total', deferral_months: 24 });
eq('capital après différé', L.capitalAfterDeferral, 20608.70);
eq('mensualité avec assurance', L.monthly, 263.60);
eq('coût total', L.totalCost, 2142.46);
eq('dû en sept. 2028', L.dueAt(T.absMonth('2028-09-01') - L.startAbs), 263.60);
const g = T.goalProgress({ target: 2000, saved: 300, due_date: '2027-07-01', created_at: '2026-10-18T10:00:00Z' }, T.absMonth('2026-10-01'));
eq('objectif : épargne mensuelle', g.monthlyNeeded, 188.89);

section('Phase 5 bis — échéancier, tiers, aides');
const sched = { mode: 'echeancier', paid_by: 'moi', schedule: [{ from: '2026-09-01', to: '2028-08-01', amount: 0 }, { from: '2028-09-01', to: '2033-08-01', amount: 180 }] };
eq('échéancier : dû en oct. 2026', T.loanDue(sched, T.absMonth('2026-10-01')), 0);
eq('échéancier : dû en sept. 2028', T.loanDue(sched, T.absMonth('2028-09-01')), 180);
eq('échéancier : total', T.scheduleLoan(sched).totalPaid, 10800);
eq('revenu salaire + aide', T.monthIncome([{ kind: 'salaire', amount: 1400 }, { kind: 'aide_famille', recurrence: 'mensuel', amount: 150 }], null).total, 1550);
const tp = T.thirdPartySummary([{ paid_by: 'tiers', payer_name: 'Parents', amount: 60 }, { paid_by: 'avance', amount: 45, reimbursed: false }]);
eq('pris en charge par des tiers', tp.total, 60);
eq('en attente de remboursement', tp.pending, 45);

section('Commun — équilibre');
eq('membre 2 doit à membre 1', T.commonBalance([{ paid_by: 'membre', paid_by_member: 'l', amount: 46 }], ['l', 'c']).transfers[0].amount, 23);
eq('après remboursement : équilibre', T.commonBalance([{ paid_by: 'membre', paid_by_member: 'l', amount: 46 }], ['l', 'c'],
  [{ from_user: 'c', to_user: 'l', amount: 23 }]).transfers.length, 0);

section('Positions — Trade Republic, indice, projection');
eq('saisie « -50 »', T.parseAmount('−50'), -50);
eq('Copier TR : investi', T.fromTradeRepublic({ value: 2544.64, gain: 162.91 }).invested, 2381.73);
eq('Copier TR : gain %', T.fromTradeRepublic({ value: 2544.64, gain: 162.91 }).pct, 6.84);
eq('Copier TR : perte → investi', T.fromTradeRepublic({ value: 950, gain: -50 }).invested, 1000);
const tracked = T.valueAccount([{ asset_type: 'etf', price_mode: 'saisie', entry_mode: 'tr', manual_value: 2000, invested: 1800,
  track_index: 'URTH', index_ref_eur: 150 }], { 'td:URTH': { eur: 151.8 } });
eq('suivi d’indice +1,2 %', tracked.value, 2024);
const etf = { id: 'etf', asset_type: 'etf', price_mode: 'saisie', entry_mode: 'tr', manual_value: 13200, invested: 12000,
              monthly_contribution: 150, distribution: 'capitalisant', total_return: 6, label: 'ETF' };
const vE = T.valueAccount([etf], {});
const k10 = Math.pow(1.005, 120);
eq('ETF 13 200 € + 150 €/mois à 6 % sur 10 ans', T.projectSavings(T.positionsForProjection({ id: 'pea', name: 'PEA', cap: 150000 }, vE,
  { capOnContributions: true }), 120).points[120].total, 13200 * k10 + 150 * (k10 - 1) / 0.005);

section('Jauges, mois, inflation');
eq('jauge Livret A : mois avant plein', T.capGauge({ balance: 14200, monthly: 200, rate: 1.7, cap: 22950 }).months, 39);
eq('jauge PEA : mois avant plein', T.capGauge({ balance: 2544.64, invested: 2381.73, monthly: 150, cap: 150000, onContributions: true }).months, 985);
eq('mois : investi ETF', T.monthPosition({ investedBefore: 2381.73, contribution: 150, value: 2700 }).invested, 2531.73);
eq('mois : gain %', T.monthPosition({ investedBefore: 2381.73, contribution: 150, value: 2700 }).pct, 6.65);
eq('mois : résumé', T.monthSummary([{ before: 2544.64, after: 2700, paid: 150 }, { before: 14200, after: 14400, paid: 200 }]).gains, 5.36);
eq('euros d’aujourd’hui (30 ans, 2 %)', T.deflate(203142, 360, 2), 203142 / Math.pow(1.02, 30));

section('Catégories personnalisées');
T.CAT_REGISTRY.perso = { c_cadeaux1: { label: 'Cadeaux', group: 'envies', order: 95 } };
const cat = T.catLookup('perso');
const bc = T.computeBudget({ income: 1550, lines: [{ category: 'c_cadeaux1', amount: 80 }], autos: {}, cat });
const row = (m) => m.rows.find((r) => r.category === 'c_cadeaux1');
eq('Cadeaux sans dépense : prévu', row(T.computeMonth({ plannedByCat: bc.byCat, cat })).planned, 80);
eq('Cadeaux + 30 € : réel', row(T.computeMonth({ plannedByCat: bc.byCat, expenses: [{ category: 'c_cadeaux1', amount: 30 }], cat })).real, 30);
eq('novembre à 120 € (ce mois-ci)', row(T.computeMonth({ plannedByCat: bc.byCat, overrides: [{ category: 'c_cadeaux1', planned_amount: 120 }], cat })).planned, 120);
eq('groupe envies dans la 50/30/20', bc.groups.envies, 80);
eq('catégorie perso inconnue dans le Commun', T.catLookup('commun')('c_cadeaux1').label, 'Autre');

console.log(`\n${passed} réussi(s), ${failed} échec(s).`);
process.exit(failed ? 1 : 0);
