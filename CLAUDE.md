# Projet : site d'épargne & budget du couple (Lucas + Célia)

Nom de l'app : **Wallet**.

## Contexte
Site privé pour centraliser l'épargne, le compte commun et les budgets de Lucas et de Célia.
Lire `SPEC.md` pour le cahier des charges complet et les phases.

## Stack (ne pas en changer sans demander)
- **Un seul fichier `index.html`** : HTML + CSS + JS vanilla, sans framework ni build.
- **Chart.js** via CDN (version figée, ex. 4.4.1) pour les graphiques.
- **Supabase** (offre gratuite) via `@supabase/supabase-js` en CDN : authentification e-mail + base Postgres.
  Les données ne sont JAMAIS dans le code : tout passe par Supabase avec Row Level Security (RLS).
- Hébergement : **GitHub Pages**. Le code est public, donc :
  seule la clé `anon` publique Supabase peut apparaître dans `index.html`, jamais la `service_role`.
- Schéma SQL dans `supabase/schema.sql` (tables + policies RLS), à coller dans l'éditeur SQL Supabase.

## Règles de travail
- Ne jamais supprimer de code existant : modifier sur place.
- Pour une refonte importante, créer une copie versionnée (`index_V2.html`) plutôt qu'écraser.
- Générer les gros morceaux de code en plusieurs étapes (3–4) pour éviter les troncatures.
- Expliquer brièvement (≈2 phrases) ce qui est fait et pourquoi à chaque étape : Lucas veut comprendre.
- Réponses courtes ; poser des questions directes quand une décision est nécessaire.
- Interface en français, montants en euros (`Intl.NumberFormat('fr-FR')`), virgule décimale acceptée en saisie.
- Responsive mobile obligatoire (utilisé surtout sur téléphone), thème clair + sombre.

## Confidentialité
- Espaces perso privés (RLS par `user_id`), espace Commun partagé (RLS par `household_id`).
- Toujours tester qu'un compte ne peut PAS lire les données perso de l'autre.

## Supabase (projet dédié à ce site)
- URL : https://fycuoqqecbmbqgindjpx.supabase.co
- Clé publishable (publique, OK dans le code) : sb_publishable__N92eqoFrQQwO552meumWw_e6H0sGVq
- Convention : préfixer TOUTES les tables, fonctions et policies par `ep_`
  (ex. `ep_accounts`) et ne jamais modifier ou supprimer ce qui n'est pas préfixé `ep_`.
- Jamais de clé secret / service_role dans le code ni dans ce dossier.
