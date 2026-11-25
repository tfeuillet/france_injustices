# Vérification des indicateurs avant publication

Pour chaque indicateur : ce qui pourrait être faux, et comment le vérifier. Les contrôles automatiques
sont faits par `R/verifier.R` (tableau `data/verification.csv`, cartes `data/verification.pdf`). Les
contrôles externes consistent à comparer deux ou trois villes repères à une valeur publiée ailleurs.

Contrôles communs à tous les indicateurs :
- la couverture (part de la population renseignée) et la part de valeurs complétées par l'intercommunalité ;
- les valeurs hors des bornes plausibles ;
- les ruptures nettes le long des limites de départements ou de régions sur la carte du PDF, signe d'une
  différence de source ou de méthode plutôt que d'une réalité ;
- le sens : une valeur élevée est-elle bien défavorable (sens = 1) ou favorable (sens = -1) ?

## Niveau de vie

**Défavorisation sociale (EDI)**
- Risques : colonne prise (score continu ou quintile) ; moyenne simple des IRIS, non pondérée par leur population.
- Vérifier : le script affiche la colonne retenue ; comparer deux IRIS de Caen à la carte de Santé publique France (Odissé).

**Taux de pauvreté, niveau de vie médian**
- Risques : millésime ; communes masquées par le secret statistique, complétées par l'intercommunalité.
- Vérifier : Caen et Roubaix dans le comparateur de territoires de l'Insee.

**Taux de chômage (recensement)**
- Risques : choix des statuts (chômeurs / actifs) et de la tranche d'âge ; dimension sans total additionnée.
- Vérifier : Caen et Denain dans le comparateur de territoires de l'Insee, rubrique « Emploi – chômage au sens du recensement ».

## Accès aux services

**APL médecins généralistes**
- Risques : feuille de l'année la plus récente ; colonne APL tous âges (et non « moins de 65 ans »).
- Vérifier : la feuille affichée dans la console ; une commune dans le fichier de la DREES.

**SCALe**
- Risques : sens de l'indice (élevé = accès difficile) ; pondération des zones par la surface faute de population.
- Vérifier : avec l'équipe ANTICIPE de Caen (Ludivine Launay, Fabien Guillot), qui a construit l'indice.

**Lycée général, formations post-bac**
- Risques : filtre « voie générale » ; formations de Parcoursup en dehors de la métropole ; coordonnées inversées.
- Vérifier : distance d'un village connu à son lycée sur une carte ; valeurs proches de 0 dans les grandes villes.

## Numérique

**Locaux raccordables à la fibre**
- Risques : colonne du dernier trimestre ; dénominateur (tous les locaux).
- Vérifier : une commune sur « Ma connexion internet » (Arcep).

## Éducation

**Ségrégation entre collèges**
- Risques : rentrée retenue ; poids des collèges ; territoires à un seul collège (désormais sans valeur).
- Vérifier : écart-type calculé à la main pour l'intercommunalité de Caen à partir du fichier des IPS.

## Environnement et risques

**Dioxyde d'azote, particules fines**
- Risques : nouveau fichier de l'Ineris lu automatiquement (colonnes, indicateur « moyenne annuelle », années).
- Vérifier : les lignes « on garde… » et « années… » dans la console ; Paris et un village du Massif central (écart attendu).

**Sites Seveso, catastrophes naturelles**
- Risques : Seveso désactivé par défaut ; arrêtés en double dans la base Gaspar.
- Vérifier : nombre d'arrêtés d'une commune sur Géorisques.

**Nuits chaudes**
- Risques : colonne de température minimale ; coordonnées en hectomètres ; années lues.
- Vérifier : gradient attendu (beaucoup au sud et dans la vallée du Rhône, presque rien en Bretagne).

## Pesticides et eau

**Pesticides dans l'eau du robinet**
- Erreur déjà trouvée et corrigée : les métabolites reclassés non pertinents gardaient leur limite de 0,1 µg/L
  dans les fichiers des années passées. La classification la plus récente s'applique désormais à toutes les années.
- Vérifier : la liste des substances écartées dans la console ; Caen nettement plus bas qu'avant ; une commune sur
  le site « Qualité de l'eau potable » du ministère de la Santé.

**Nitrates dans l'eau du robinet**
- Risques : paramètre NO3 (et non NO2) ; moyenne de réseaux de tailles très différentes.
- Vérifier : une commune sur le site du ministère de la Santé.

## Participation politique

**Abstention**
- Risques : codes des communes (départements à un chiffre, Corse) ; Paris, Lyon et Marseille.
- Vérifier : Caen et Saint-Denis sur le site des résultats du ministère de l'Intérieur.

## Santé

**Indice comparatif de mortalité**
- Risques : classes d'âge et sexes retenus ; années de décès complètes ; taux d'Eurostat de chaque année.
- Vérifier : les lignes de la console (« sexes : M, F », « communes présentes par année », rapport national proche
  de 1) ; comparer quelques intercommunalités aux atlas des ORS ; relecture par un épidémiologiste.

## Trajectoires récentes

**Emploi salarié privé, population**
- Risques : années comparées ; seuil de 50 salariés ; fusions de communes.
- Vérifier : évolution nationale affichée dans la console, à comparer aux chiffres publiés par l'Urssaf et l'Insee.

## Temps long

**Rangs de revenu et de capital immobilier (Cagé et Piketty)**
- Risques : variable retenue par le motif ; années extrêmes ; rangs calculés avec les populations actuelles.
- Vérifier : la variable et les années affichées dans la console ; le sens du décrochage pour une ville industrielle connue.

## La page elle-même

- Les rangs, les paliers, le score et les tableaux sont calculés dans le navigateur (`moteur.js`, `index.html`).
- Vérifier : envoyer `docs/data/donnees.json` pour faire tourner le moteur sur les vraies données et contrôler
  la répartition en classes de 10 %, les paliers et les ex æquo.
