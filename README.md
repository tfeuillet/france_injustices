# Les injustices territoriales en France

Où se cumulent les désavantages en France, et touchent-ils davantage les territoires déjà modestes ?
Cette carte interactive réunit, pour chacune des 35 000 communes de métropole, des indicateurs de
situation sociale (pauvreté, niveau de vie), de moyens au regard des besoins (accès aux médecins,
fibre optique), d'exposition aux nuisances et aux risques (pollution de l'air, sites Seveso,
catastrophes naturelles) et de voix politique (abstention). Chacun choisit les critères qui lui
paraissent relever de l'injustice et leur poids, et la carte se redessine. Un tableau compare ce que
supportent les territoires les plus modestes et les plus aisés.

[Thierry Feuillet](https://tfeuillet.github.io/), Université de Caen Normandie, [UMR CNRS IDEES](https://umr-idees.fr/)  
[thierry.feuillet@unicaen.fr](mailto:thierry.feuillet@unicaen.fr)

## Refaire la carte chez soi

```r
install.packages(c("sf", "dplyr", "jsonlite", "data.table", "readxl", "melodi", "rmapshaper", "servr"))
source("run.R")          # télécharge les données et prépare docs/data/
servr::httd("docs")      # ouvre la carte
```

Toutes les données sont téléchargées automatiquement. Les jeux publiés sur data.gouv.fr sont
retrouvés par l'API du portail, si bien que leur dernière version est prise sans changer d'adresse.

Chaque indicateur est préparé dans son propre bloc de `R/01_donnees.R`. Si un serveur ne répond pas
ou si un fichier a changé de forme, le bloc échoue sans arrêter les autres, et le bilan affiché à la
fin dit ce qui manque. Le message d'erreur liste alors les colonnes du fichier, ce qui permet
d'adapter le motif de recherche en une ligne.

## Ce que contient le dépôt

Le dossier `R/` prépare les données. `01_donnees.R` les télécharge et calcule les indicateurs par
commune, `02_export.R` écrit les fichiers lus par la carte.

Le dossier `docs/` contient la page (`index.html`) et les calculs, faits dans le navigateur
(`moteur.js`).

Le fichier `.github/workflows/maj.yml` met les données à jour le premier jour de chaque mois.

## La méthode en quelques mots

Chaque indicateur est converti en rang de population, entre 0 et 100. Une commune au rang 80 est plus
défavorisée que des communes où vivent 80 % des habitants. Le score cumulé est la moyenne de ces rangs,
pondérée par les poids choisis. La carte peut aussi être calculée par intercommunalité. Le détail, les
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
