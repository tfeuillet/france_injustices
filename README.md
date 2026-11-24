# Les injustices territoriales en France

Où se cumulent les désavantages en France, et touchent-ils davantage les territoires déjà modestes ?
Cette carte interactive réunit, pour chacune des 35 000 communes de métropole (et les arrondissements
de Paris, Lyon et Marseille), des indicateurs regroupés en dimensions : niveau de vie (indice européen
de défavorisation, chômage), accès aux services (APL, indice SCALe, éloignement des lycées et des formations post-bac), accès au numérique (fibre),
éducation (ségrégation sociale entre collèges), environnement et
risques (pollution de l'air, nuits chaudes, sites Seveso, catastrophes naturelles), pesticides et eau (usage agricole
des pesticides, pesticides et nitrates dans l'eau du robinet), participation politique
(abstention), santé (surmortalité à âge égal) et trajectoires (emploi et population sur dix ans,
revenu et capital immobilier sur plusieurs décennies d'après Julia Cagé et Thomas Piketty).

Chacun coche les indicateurs qui lui paraissent relever de l'injustice. Chaque dimension cochée pèse
autant dans le score, quel que soit son nombre d'indicateurs, pour qu'une même information ne compte
pas plusieurs fois. La carte peut aussi compter dans combien de dimensions un territoire fait partie
des plus défavorisés. Un tableau compare ce que supportent les territoires les plus modestes et les
plus aisés.

L'onglet « Double peine » croise un désavantage social et une exposition, en tiers de la population,
pour montrer où les deux se cumulent. Trois autres onglets servent à l'analyse. Le premier repère les concentrations de désavantages avec
l'indice local de Moran (LISA), univarié ou bivarié, sur un voisinage de contiguïté, de distance ou de
plus proches voisins. Le deuxième mesure la relation locale entre deux indicateurs par une régression
géographiquement pondérée, à la largeur de bande optimale par défaut, avec des t corrigés de
l'autocorrélation spatiale. Le troisième hiérarchise les
facteurs associés à un indicateur, la surmortalité par exemple. Il répartit le R² d'une régression
multiple entre les facteurs (décomposition de Shapley, ou LMG), pour toute la France puis autour de
chaque territoire, et cartographie le facteur dominant. Chaque carte s'exporte en PNG ou en PDF.

[Thierry Feuillet](https://tfeuillet.github.io/), Université de Caen Normandie, [UMR CNRS IDEES](https://umr-idees.fr/)  
[thierry.feuillet@unicaen.fr](mailto:thierry.feuillet@unicaen.fr)

## Refaire la carte chez soi

```r
install.packages(c("sf", "dplyr", "jsonlite", "data.table", "readxl", "melodi", "rmapshaper", "servr", "haven"))
source("run.R")          # télécharge les données et prépare docs/data/
servr::httd("docs")      # ouvre la carte
```

Toutes les données sont téléchargées automatiquement, sauf celles de Julia Cagé et Thomas Piketty :
leur site ne donne pas d'adresse fixe. Il faut télécharger une fois les bases « Revenus » et « Capital
immobilier » sur [unehistoireduconflitpolitique.fr](https://unehistoireduconflitpolitique.fr/telecharger.html)
et les déposer dans `data/brut/piketty/`. De même, les indices de fréquence de traitement par commune
de la [carte Adonis](https://solagro.org/nos-domaines-d-intervention/agroecologie/carte-pesticides-adonis)
sont fournis sur demande par Solagro, et le fichier reçu se dépose dans `data/brut/adonis/`. Sans lui,
l'indicateur manque simplement à la carte (`avec_adonis <- FALSE` par défaut). Ces données ne peuvent pas être rediffusées : elles ne vont
jamais dans `docs/`, qui est publié, mais dans une copie locale de la carte, `prive/`, que git ignore
(`servr::httd("prive")`). Les cartes qui les utilisent portent la mention « Source : Carte Adonis des
pesticides, Solagro, 2024 » et le logo de Solagro, à déposer sous le nom `prive/solagro.png`.
Enfin, l'Insee ne publie pas les décès par âge et par commune : le taux de mortalité prématurée se
télécharge sur l'[Observatoire des territoires](https://www.observatoire-des-territoires.gouv.fr/taux-de-mortalite-prematuree)
et se dépose dans `data/brut/mortalite_prematuree/`. Les jeux publiés sur data.gouv.fr sont
retrouvés par l'API du portail, si bien que leur dernière version est prise sans changer d'adresse.

Chaque indicateur est préparé dans son propre bloc de `R/01_donnees.R`. Si un serveur ne répond pas
ou si un fichier a changé de forme, le bloc échoue sans arrêter les autres, et le bilan affiché à la
fin dit ce qui manque. Le message d'erreur liste alors les colonnes du fichier, ce qui permet
d'adapter le motif de recherche en une ligne.

## Ce que contient le dépôt

Le dossier `R/` prépare les données. `01_donnees.R` les télécharge et calcule les indicateurs par
commune, `02_export.R` écrit les fichiers lus par la carte.

Le dossier `docs/` contient la page (`index.html`) et les calculs, faits dans le navigateur
(`moteur.js` pour le score, `lisa.js` pour les concentrations, `gwr.js` pour les corrélations
locales, `export.js` pour l'export des cartes). Les calculs ont été vérifiés contre les modules
Python de référence : esda pour le LISA, mgwr pour la GWR.

Le fichier `.github/workflows/maj.yml` met les données à jour le premier jour de chaque mois.

## La méthode en quelques mots

Chaque indicateur est converti en rang de population, entre 0 et 100. Une commune au rang 80 est plus
défavorisée que des communes où vivent 80 % des habitants. Chaque dimension reçoit la moyenne des rangs
de ses indicateurs cochés, et le score cumulé est la moyenne des dimensions, qui pèsent toutes autant. La carte peut aussi être calculée par intercommunalité, par bassin de vie ou par zone d'emploi (table d'appartenance géographique de l'Insee). Le détail, les
sources et les limites figurent dans l'onglet « Méthode et sources ».

## À savoir avant de s'en servir

Les indicateurs décrivent des territoires et non des personnes.

Le secret statistique masque la pauvreté et le niveau de vie des plus petites communes. Elles
reçoivent la valeur de leur intercommunalité, signalée sur la carte.

La pollution de l'air provient de la reconstitution par commune publiée par l'Ineris, qui s'arrête
en 2015.

## Contribuer

Les remarques, corrections et propositions d'indicateurs sont les bienvenues, par courriel ou en
ouvrant une proposition (*issue*) sur GitHub.