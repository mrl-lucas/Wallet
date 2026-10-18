# Cahier des charges — « Wallet »

## Objectif
Un seul endroit pour : voir toute l'épargne (perso + commune), gérer le budget mensuel de chacun
et du compte commun, comparer le réel au prévu, et projeter l'épargne à 1, 5, 10 et 20 ans.

## Utilisateurs & accès
- 2 personnes : Lucas et sa copine, chacune avec son compte (connexion e-mail Supabase).
- Un « foyer » regroupe les deux. Espaces : **Lucas**, **Célia**, **Commun**.
- **Espaces perso PRIVÉS** : Lucas ne voit pas les données de Célia et inversement (garanti par RLS côté
  base, pas seulement masqué dans l'interface).
- **Espace Commun partagé** : compte commun, budget commun, dépenses communes, objectifs communs,
  visibles et modifiables par les deux.
- La vue d'ensemble montre : mon perso + le commun (jamais le détail de l'autre).

## Fonctionnalités
1. **Vue d'ensemble du foyer**
   - Patrimoine total + répartition par personne et par compte.
   - Projection combinée 1 / 5 / 10 / 20 ans.
   - Dépenses du mois vs prévu pour chaque espace ; avancement des objectifs.
2. **Budget mensuel (par espace)**
   - Salaire net saisi à la main (pour le Commun : contributions de chacun).
   - Lignes de budget par thème : logement/loyer, alimentation, transport, abonnements & factures,
     santé, loisirs, shopping, voyages, autre.
   - Lignes automatiques : versements épargne, virement vers le compte commun, mensualité du prêt étudiant.
   - Reste à vivre, taux d'épargne, comparaison à la règle 50/30/20 (besoins / envies / épargne).
3. **Dépenses du mois**
   - Saisie rapide (date, libellé, catégorie, montant), navigation mois par mois.
   - Réel vs prévu par catégorie avec barre de progression (alerte si dépassement).
   - Le prévu d'un mois peut être ajusté sans toucher au budget par défaut.
4. **Épargne & projections**
   - Comptes : compte courant perso (prélèvements auto), PEE (entreprise), Livret A, Trade Republic, etc.
     Champs : nom, type, solde, versement mensuel, taux/rendement annuel estimé, plafond.
   - Bouton « relever les soldes du mois » → historique ⇒ courbe **réel** + courbe **projection**
     + courbe « versements seuls » (pour visualiser les intérêts).
   - Curseur « +X €/mois » pour simuler un effort supplémentaire.
   - Alertes : plafond Livret A atteint (22 950 €), fonds d'urgence (3–6 mois de dépenses), PEE bloqué 5 ans.
5. **Prêt étudiant**
   - Capital, taux, durée, date de début du remboursement, assurance, différé partiel ou total.
   - Mensualité, coût total, date de fin, tableau d'amortissement annuel, graphique du capital restant dû.
   - Part de la mensualité dans le salaire actuel ET dans le salaire prévu après les études.
6. **Objectifs** (vacances, voiture, apport…)
   - Montant cible, déjà épargné, échéance, propriétaire (moi / Commun).
   - Calcul de l'épargne mensuelle nécessaire, ajout de versements, barre de progression.

## Calculs
- Projection mensuelle par compte : `solde = solde × (1 + taux/12) + versement` (versement stoppé au plafond).
- Mensualité de prêt : `M = P × r / (1 − (1 + r)^−n)` avec `r = taux annuel / 12`.
- Objectif : `mensualité nécessaire = (cible − déjà épargné) / mois restants`.
- Taux par défaut modifiables : Livret A 1,7 % (à vérifier), rendement bourse = hypothèse saisie par l'utilisateur.

## Modèle de données Supabase (à affiner en phase 1)
- `households` (id, nom) · `members` (household_id, user_id, prénom, slot)
- Chaque ligne a `scope` = 'perso' | 'commun' et `user_id` (propriétaire si perso).
- `accounts` (id, household_id, scope, user_id, nom, type, solde, versement, taux, plafond)
- `balance_snapshots` (account_id, mois, solde)
- `budget_lines` (id, household_id, scope, user_id, libellé, catégorie, montant)
- `month_overrides` (household_id, scope, user_id, mois, catégorie, montant_prévu)
- `expenses` (id, household_id, scope, user_id, date, libellé, catégorie, montant, created_by)
- `incomes` (household_id, scope, user_id, salaire / contribution)
- `loans` (id, scope, user_id, capital, taux, durée_mois, début, assurance, type_différé, salaire_futur)
- `goals` (id, household_id, scope, user_id, nom, cible, épargné, échéance)
- RLS : ligne 'perso' → lecture/écriture seulement si `user_id = auth.uid()` ;
  ligne 'commun' → lecture/écriture si l'utilisateur est membre du `household_id`.
- Rejoindre le foyer : Lucas crée le foyer, Célia le rejoint avec un code d'invitation.
- Inscriptions désactivées dans Supabase une fois les deux comptes créés.

## Phases
1. Supabase : création du projet, `schema.sql` (tables + RLS), connexion e-mail dans `index.html`.
2. Structure de l'app : navigation (onglets + sélecteur Mon espace / Commun), design, thème.
3. Comptes d'épargne + projections + graphiques.
4. Budget mensuel + dépenses du mois (réel vs prévu).
5. Prêt étudiant + objectifs.
6. Vue d'ensemble du foyer, finitions mobile, déploiement GitHub Pages + invitation de la copine.
