# ------------------------------------------------------------------
# 1. Téléchargement et préparation des données (maille : commune)
#    Sorties : data/communes.gpkg, data/epci.gpkg, data/indicateurs.rds
#
#    Chaque indicateur est calculé dans son propre bloc. Si un serveur
#    ne répond pas ou si un fichier a changé de forme, le bloc échoue,
#    le message s'affiche à la fin et la carte se construit sans lui.
# ------------------------------------------------------------------
library(sf)
library(dplyr)
library(jsonlite)
source("R/00_fonctions.R")
options(timeout = 1800)
dir.create("data/brut", recursive = TRUE, showWarnings = FALSE)

# ---- Ne refaire que certains indicateurs ----------------------------
# Les autres sont repris du passage précédent (data/indicateurs.rds), ce qui évite de
# tout recalculer. Par exemple : refaire <- c("scale", "fibre", "air", "catnat")
# NULL : tout refaire. Quand la liste des communes change (arrondissements ajoutés, par
# exemple), tout est refait de toute façon.
refaire <- NULL

# ---- Adresses des serveurs (tout est ici) -------------------------
url_communes <- "https://geo.api.gouv.fr/communes?fields=code,nom,population,codeEpci,codeDepartement,codeRegion&format=json"
url_contours <- "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/communes-100m.geojson"
url_epci     <- "https://etalab-datasets.geo.data.gouv.fr/contours-administratifs/latest/geojson/epci-100m.geojson"
url_air      <- "https://zenodo.org/records/5043645/files/Indicateurs_QualiteAir_France_Commune_2000-2015_Ineris_v.Sep2020.zip?download=1"
jeu_revenus  <- "DS_FILOSOFI_CC"          # Insee, catalogue Melodi
# Jeux de data.gouv.fr (identifiant ou nom court) : la ressource la plus récente est prise automatiquement
jeu_apl      <- "laccessibilite-potentielle-localisee-apl"
jeu_catnat   <- "arretes-de-catastrophe-naturelle-par-commune"
jeu_icpe     <- "66631f6d5ff38efa62d385ac"
jeu_fibre    <- "le-marche-du-haut-et-tres-haut-debit-fixe-deploiements"
jeu_election <- "62581fdf02e05e365ea227a1"   # présidentielle 2022, 1er tour, résultats définitifs
jeu_scale    <- "5d2c72768b4c4131e30d4e01"   # SCALe, Inserm U1086 et UMR IDEES (zones résidentielles, équipements de 2013)
url_edi      <- "https://odisse.santepubliquefrance.fr/api/explore/v2.1/catalog/datasets/french-european-deprivation-index-f-edi-2021-par-iris/exports/csv?delimiter=%3B"
url_urssaf   <- "https://open.urssaf.fr/api/explore/v2.1/catalog/datasets/etablissements-et-effectifs-salaries-au-niveau-commune-x-ape-last"
jeu_population <- "DS_POPULATIONS_HISTORIQUES"   # Insee, catalogue Melodi, géographie communale récente
jeu_deces    <- "DS_ETAT_CIVIL_DECES_COMMUNES"   # Insee, décès domiciliés par commune et par an
jeu_age      <- "DS_RP_POPULATION_PRINC"         # Insee, recensement, population par âge
jeu_actifs   <- "DS_RP_EMPLOI_LR_PRINC"          # Insee, recensement, population active et chômage
url_eurostat <- "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/"
annee_mortalite <- 2019   # année des taux de mortalité nationaux par âge (avant le covid)
duree_mortalite <- 10     # années de décès cumulées pour l'indice comparatif de mortalité
# Mortalité prématurée (décès avant 65 ans). L'Insee ne publie pas les décès par âge et par commune
# de domicile. L'Observatoire des territoires diffuse un « Taux de mortalité prématurée » : le
# télécharger à la main (observatoire-des-territoires.gouv.fr, bouton Télécharger), à la maille la
# plus fine proposée, et déposer le fichier (csv ou xlsx) dans ce dossier.
dossier_prematuree <- "data/brut/mortalite_prematuree"
# Paris, Lyon et Marseille découpées en arrondissements municipaux
avec_arrondissements <- TRUE
url_arm      <- "https://geo.api.gouv.fr/communes?type=arrondissement-municipal&fields=code,nom,population,codeDepartement&format=json"
# Données de Julia Cagé et Thomas Piketty (unehistoireduconflitpolitique.fr/telecharger.html).
# Le site ne donne pas d'adresse fixe : télécharger à la main les bases « Revenus » et
# « Capital immobilier » et les déposer (zip ou csv) dans ce dossier.
dossier_piketty <- "data/brut/piketty"
# Pour chaque indicateur : le fichier à lire (sans .csv) et le motif du nom de la variable à
# suivre dans le temps. Le bilan affiche les variables du fichier : il suffit d'adapter le motif.
piketty_fichiers <- c(revenu_long = "revcommunes", capital_long = "capitalimmobiliercommunes")
piketty <- c(revenu_long = "^revmoy|^rev", capital_long = "capital|immo|prix|valeur")
duree_dynamique <- 10   # années sur lesquelles on mesure les évolutions
seuil_emploi <- 50      # en dessous de 50 salariés au départ, l'évolution d'une commune n'a guère de sens :
# elle reçoit celle de son intercommunalité
# Le fichier SCALe pèse 550 Mo (un million de zones résidentielles). Il n'est traité qu'une fois,
# le résultat par commune est gardé dans data/brut/scale_communes.rds.
avec_scale   <- TRUE
# Le service de Géorisques qui diffuse les sites Seveso est très lent (plus de 15 minutes).
# Mettre TRUE pour l'essayer quand on a le temps ; le résultat est ensuite gardé 25 jours.
avec_seveso  <- FALSE
# Contrôle sanitaire de l'eau du robinet (ministère de la Santé et ARS) : un zip d'environ 300 Mo
# par année. Chaque année n'est lue qu'une fois. Le résumé par réseau est gardé dans
# data/brut/eau_<année>.rds et le zip est ensuite effacé.
jeu_eau      <- "resultats-du-controle-sanitaire-de-leau-distribuee-commune-par-commune"
annees_eau   <- 2023:2025
# Carte Adonis de Solagro (indice de fréquence de traitement par commune). Les données sont
# fournies sur demande par Solagro (solagro.org) : déposer le fichier reçu (csv ou xlsx) dans ce
# dossier. Sans fichier, l'indicateur est simplement absent de la carte.
avec_adonis  <- FALSE   # TRUE pour l'utiliser (licence restreinte : jamais publié, voir 02_export.R)
dossier_adonis <- "data/brut/adonis"
motif_ift    <- "ift"   # motif du nom de la colonne de l'IFT total, à adapter d'après le bilan
# Réanalyse Safran de Météo-France (SIM2), un fichier d'environ 140 Mo par année. Comme pour
# l'eau, chaque année n'est lue qu'une fois : le résumé est gardé dans data/brut/chaleur_<année>.rds.
jeu_sim      <- "donnees-changement-climatique-sim-quotidienne"
annees_chaleur <- 2016:2025
seuil_nuit   <- 20      # une nuit chaude (ou tropicale) : la température ne descend pas sous 20 °C
# Éducation. Distances moyennes des habitants, à vol d'oiseau, jusqu'au lycée proposant la voie générale le plus proche
# (annuaire de l'éducation) et jusqu'à la formation post-bac la plus proche (toutes les formations
# de Parcoursup). Ségrégation entre collèges : indices de position sociale (IPS) de la DEPP.
# Où vivent les habitants : population des carreaux de 1 km du recensement (Insee, RP 2021, 33 Mo).
# Les centres des carreaux habités sont rattachés une fois pour toutes à leur commune (data/brut/carreaux_1km.rds).
# Bassins de vie et zones d'emploi de chaque commune : table d'appartenance géographique de l'Insee
url_appartenance <- "https://www.insee.fr/fr/statistiques/fichier/7671844/table-appartenance-geo-communes-2026.zip"
url_carreaux <- "https://www.insee.fr/fr/statistiques/fichier/8272002/rp2021_carreaux_1km_csv.zip"
url_annuaire  <- "https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-annuaire-education/exports/csv?delimiter=%3B"
# seules les deux colonnes utiles sont demandées : le fichier complet est très lourd
url_parcoursup <- "https://data.enseignementsup-recherche.gouv.fr/api/explore/v2.1/catalog/datasets/fr-esr-cartographie_formations_parcoursup/exports/csv?delimiter=%3B&select=annee%2Cetab_gps"
jeu_ips      <- "664d7247ce9d483d0ee5a98b"   # IPS des collèges (à partir de 2023), DEPP
url_effectifs_colleges <- "https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-college-effectifs-niveau-sexe-lv/exports/csv?delimiter=%3B"

# ---- Les indicateurs ------------------------------------------------
# dimension : chaque dimension pèse autant dans le score, quel que soit son nombre d'indicateurs
#   niveau_vie, services, numerique, education, environnement, pesticides, voix, sante, trajectoires, temps_long
#   (services : éloignement des soins, du lycée et des études, qui suivent tous le gradient urbain-rural)
# cumul : 1 si l'indicateur peut entrer dans le cumul, 0 s'il ne sert qu'aux analyses
#   (taux de pauvreté et niveau de vie : trop redondants avec l'EDI)
# defaut : 1 s'il est coché au départ (un indicateur par dimension ; la page applique aussi cette règle)
# sens : +1 si une valeur élevée est défavorable, -1 si elle est favorable
INDICATEURS <- read.csv(text = "
id;nom;dimension;cumul;defaut;sens;unite;decimales;source
edi;Défavorisation sociale (EDI);niveau_vie;1;1;1;score;2;Inserm et Santé publique France, indice européen de défavorisation (EDI 2021, par IRIS)
pauvrete;Taux de pauvreté;niveau_vie;0;0;1;%;1;Insee, Filosofi
chomage;Taux de chômage;niveau_vie;1;0;1;% des actifs de 15 à 64 ans;1;Insee, recensement de la population
revenu;Niveau de vie médian;niveau_vie;0;0;-1;€ par an;0;Insee, Filosofi
apl;Accès aux médecins généralistes;services;1;0;-1;consultations par habitant et par an;1;DREES, accessibilité potentielle localisée (APL)
scale;Éloignement des soins de premier recours (SCALe);services;1;1;1;indice;1;Inserm U1086 et UMR IDEES, indice SCALe (équipements de 2013)
fibre;Locaux raccordables à la fibre;numerique;1;1;-1;%;0;Arcep, déploiements du très haut débit
superieur;Éloignement des formations post-bac;services;1;0;1;km à vol d'oiseau, moyenne des habitants;1;Ministère de l'Enseignement supérieur, cartographie des formations Parcoursup
lycee;Éloignement du lycée général;services;1;0;1;km à vol d'oiseau, moyenne des habitants;1;Ministère de l'Éducation nationale, annuaire de l'éducation
segregation;Ségrégation sociale entre collèges;education;1;1;1;écart-type de l'IPS des collèges de l'intercommunalité;1;DEPP, indices de position sociale des collèges
no2;Pollution au dioxyde d'azote;environnement;1;0;1;µg/m³;1;Ineris, concentrations moyennes par commune
pm25;Pollution aux particules fines;environnement;1;1;1;µg/m³;1;Ineris, concentrations moyennes par commune
seveso;Sites industriels Seveso;environnement;1;0;1;sites dans la commune;0;Géorisques, installations classées
catnat;Catastrophes naturelles reconnues;environnement;1;0;1;arrêtés depuis 1982;0;Base Gaspar, arrêtés de catastrophe naturelle
chaleur;Nuits chaudes (minimales d'au moins 20 °C);environnement;1;0;1;nuits par an;1;Météo-France, réanalyse Safran (SIM2)
ift;Usage agricole de pesticides (IFT);pesticides;1;0;1;doses de référence par hectare;2;Solagro, carte Adonis des indices de fréquence de traitement
eau_pesticides;Pesticides dans l'eau du robinet;pesticides;1;1;1;µg/L;3;Ministère de la Santé et ARS, contrôle sanitaire de l'eau distribuée
eau_nitrates;Nitrates dans l'eau du robinet;pesticides;1;0;1;mg/L;1;Ministère de la Santé et ARS, contrôle sanitaire de l'eau distribuée
abstention;Abstention;voix;1;1;1;% des inscrits;1;Ministère de l'Intérieur, présidentielle 2022 (1er tour)
icm;Surmortalité (indice comparatif de mortalité);sante;1;1;1;France = 100;0;Insee, décès domiciliés et recensement ; Eurostat, mortalité par âge
prematuree;Mortalité prématurée (avant 65 ans);sante;1;0;1;taux;1;Observatoire des territoires, taux de mortalité prématurée
emploi;Évolution de l'emploi salarié privé;trajectoires;1;1;-1;%;1;Urssaf, effectifs salariés du secteur privé au 31 décembre
population;Évolution de la population;trajectoires;1;0;-1;%;1;Insee, populations municipales
revenu_long;Évolution du rang de revenu sur le long terme;temps_long;1;0;-1;points de centile;1;Cagé et Piketty (2023), Une histoire du conflit politique
capital_long;Évolution du rang de capital immobilier sur le long terme;temps_long;1;0;-1;points de centile;1;Cagé et Piketty (2023), Une histoire du conflit politique
", sep = ";", encoding = "UTF-8")

# ---- 1. Communes, population, contours ----------------------------
metropole <- c("11", "24", "27", "28", "32", "44", "52", "53", "75", "76", "84", "93", "94")
com <- fromJSON(telecharger(url_communes, "data/brut/communes.json")) |>
  filter(codeRegion %in% metropole) |>
  rename(epci = codeEpci, dep = codeDepartement)
com$population[is.na(com$population)] <- 0

# le fichier d'Etalab contient aussi les arrondissements municipaux de Paris, Lyon et Marseille
tous_contours <- st_read(telecharger(url_contours, "data/brut/communes.geojson"), quiet = TRUE) |> select(code)
contours <- tous_contours |> filter(code %in% com$code)
# Paris, Lyon et Marseille : leurs arrondissements remplacent la commune entière
plm <- c("75056", "69123", "13055")
if (avec_arrondissements) {
  arm <- fromJSON(telecharger(url_arm, "data/brut/arrondissements.json"))
  arm <- arm[code_plm(arm$code) %in% plm, ]
  arm <- data.frame(code = arm$code, nom = arm$nom, population = arm$population, dep = substr(arm$code, 1, 2),
                    epci = com$epci[match(code_plm(arm$code), com$code)], codeRegion = com$codeRegion[match(code_plm(arm$code), com$code)])
  arm_contours <- tous_contours |> filter(code %in% arm$code)
  if (nrow(arm_contours) < 40) {
    message("Contours des arrondissements introuvables (", nrow(arm_contours), " trouvés) : Paris, Lyon et Marseille restent entières")
  } else {
    com <- bind_rows(com[!com$code %in% plm, ], arm[arm$code %in% arm_contours$code, ])
    contours <- rbind(contours[!contours$code %in% plm, ], arm_contours)
    cat(nrow(arm_contours), "arrondissements de Paris, Lyon et Marseille\n")
  }
}
rm(tous_contours)
com <- com |> filter(code %in% contours$code) |> arrange(code)
contours <- contours[match(com$code, contours$code), ]
cat(nrow(com), "communes en métropole\n")

# Bassins de vie (BV2022) et zones d'emploi (ZE2020) de chaque commune, d'après la table
# d'appartenance de l'Insee. Les arrondissements de Paris, Lyon et Marseille prennent ceux de leur
# ville. En cas d'échec, la carte se construit sans ces deux niveaux.
zonages <- list()
tryCatch({
  z <- telecharger(url_appartenance, "data/brut/appartenance.zip", jours = 365)
  dossier <- file.path(tempdir(), "appartenance")
  unzip(z, exdir = dossier)
  f <- list.files(dossier, "\\.xlsx?$", full.names = TRUE, recursive = TRUE)[1]
  tab <- lire_tableau(f, "COM", entete = "^CODGEO$")
  noms <- tryCatch(lire_tableau(f, grep("supra", readxl::excel_sheets(f), ignore.case = TRUE, value = TRUE)[1], entete = "^NIVGEO$"),
                   error = function(e) NULL)
  for (niv in c(bv = "^BV", ze = "^ZE")) {
    col <- colonne(tab, niv)
    k <- names(which(c(bv = "^BV", ze = "^ZE") == niv))
    com[[k]] <- as.character(tab[[col]])[match(code_plm(com$code), as.character(tab$CODGEO))]
    codes <- sort(unique(na.omit(com[[k]])))
    # nom de chaque zone : celui de l'Insee, à défaut celui de sa commune la plus peuplée
    nom <- if (!is.null(noms)) as.character(noms$LIBGEO)[match(paste(col, codes), paste(noms$NIVGEO, noms$CODGEO))] else rep(NA, length(codes))
    plus_grande <- tapply(seq_len(nrow(com)), com[[k]], function(i) com$nom[i[which.max(com$population[i])]])
    nom[is.na(nom)] <- plus_grande[codes[is.na(nom)]]
    zonages[[k]] <- data.frame(code = codes, nom = nom)
    cat("  ", nrow(zonages[[k]]), c(bv = "bassins de vie", ze = "zones d'emploi")[k], "(", col, ")\n")
  }
  unlink(dossier, recursive = TRUE)
}, error = function(e) message("Bassins de vie et zones d'emploi indisponibles : ", conditionMessage(e)))

epci <- st_read(telecharger(url_epci, "data/brut/epci.geojson"), quiet = TRUE) |>
  select(code, nom) |>
  filter(code %in% com$epci)

# Tableau des valeurs : une colonne par indicateur, une ligne par commune
valeurs <- data.frame(code = com$code)
impute <- list()        # communes dont la valeur vient de leur intercommunalité
par_niveau <- list()    # valeurs calculées directement par intercommunalité, bassin de vie ou zone d'emploi
rapport <- character()  # ce qui s'est bien ou mal passé

# Ranger un indicateur : `v` est un vecteur nommé par code commune.
# completer = TRUE : une commune sans valeur (fusionnée depuis la date des données, par
# exemple) reçoit la moyenne de son intercommunalité pondérée par la population, et la
# carte le signale.
ranger <- function(id, v, completer = FALSE) {
  v <- completer_plm(v)
  x <- unname(v[valeurs$code])
  # un arrondissement absent de la source reçoit la valeur de sa commune (Paris, Lyon, Marseille)
  parent <- code_plm(valeurs$code)
  manque_plm <- is.na(x) & parent != valeurs$code
  x[manque_plm] <- unname(v[parent[manque_plm]])
  if (any(manque_plm & !is.na(x))) impute[[id]] <<- sort(unique(c(impute[[id]], which(manque_plm & !is.na(x)) - 1)))
  if (completer) {
    ok <- !is.na(x)
    p <- pmax(com$population, 1)
    moy <- tapply(x[ok] * p[ok], com$epci[ok], sum) / tapply(p[ok], com$epci[ok], sum)
    manque <- is.na(x) & !is.na(com$epci)
    x[manque] <- moy[com$epci[manque]]
    impute[[id]] <<- sort(unique(c(impute[[id]], which(manque & !is.na(x)) - 1)))   # indices à partir de 0, pour JavaScript
  }
  valeurs[[id]] <<- x
  n <- sum(!is.na(x))
  rapport[id] <<- paste0("ok, ", n, " communes renseignées sur ", nrow(valeurs),
                         if (length(impute[[id]])) paste0(" (dont ", length(impute[[id]]), " complétées par leur intercommunalité ou leur ville)") else "")
  cat("   ", id, ":", rapport[id], "\n")
}
# Préciser l'unité ou la source d'un indicateur une fois les données lues (années, par exemple)
preciser <- function(id, unite = NULL, source = NULL) {
  k <- INDICATEURS$id == id
  if (!is.null(unite)) INDICATEURS$unite[k] <<- unite
  if (!is.null(source)) INDICATEURS$source[k] <<- source
}
# Reprendre des indicateurs du passage précédent, s'ils y avaient réussi
# Après un passage interrompu, data/en_cours.rds garde les blocs déjà calculés : ils sont repris
# automatiquement (sauf ceux listés dans `refaire`). Sinon, on part du dernier passage complet.
interrompu <- file.exists("data/en_cours.rds")
ancien <- if (interrompu) readRDS("data/en_cours.rds") else if (file.exists("data/indicateurs.rds")) readRDS("data/indicateurs.rds") else NULL
if (interrompu) cat("Passage précédent interrompu : les blocs déjà réussis sont repris\n")
reprendre <- function(ids) {
  if (is.null(ancien) || !identical(ancien$valeurs$code, valeurs$code)) return(FALSE)
  if (!all(ids %in% names(ancien$valeurs)) || !all(grepl("^ok", ancien$rapport[ids]))) return(FALSE)
  for (id in ids) {
    valeurs[[id]] <<- ancien$valeurs[[id]]
    if (!is.null(ancien$par_niveau[[id]])) par_niveau[[id]] <<- ancien$par_niveau[[id]]
    impute[[id]] <<- ancien$impute[[id]]
    rapport[id] <<- sub(" \\(repris.*", "", ancien$rapport[id])
    rapport[id] <<- paste(rapport[id], "(repris du passage précédent)")
    a <- ancien$indicateurs[ancien$indicateurs$id == id, ]
    if (nrow(a)) INDICATEURS[INDICATEURS$id == id, c("unite", "source")] <<- a[1, c("unite", "source")]
  }
  cat("    repris du passage précédent\n")
  TRUE
}
# Lancer un bloc sans que son échec n'arrête tout. `ids` : les indicateurs que le bloc produit.
essayer <- function(id, bloc, ids = id, reprise = TRUE) {
  cat("--", id, "\n")
  rapport <<- rapport[names(rapport) != id]   # efface un échec laissé par un passage précédent
  if (reprise && (interrompu || !is.null(refaire)) && !id %in% refaire && reprendre(ids)) return(invisible())
  tryCatch(bloc, error = function(e) {
    rapport[id] <<- paste("ÉCHEC :", conditionMessage(e))
    cat("   ", rapport[id], "\n")
  })
  # sauvegarde après chaque bloc : un passage interrompu pourra reprendre ici
  if (reprise) saveRDS(list(valeurs = valeurs, impute = impute, rapport = rapport, indicateurs = INDICATEURS, par_niveau = par_niveau), "data/en_cours.rds")
}

# ---- 2. Revenus et pauvreté (Insee, Filosofi) ---------------------
# Le secret statistique masque les petites communes : on leur donne alors la valeur
# de leur intercommunalité, et la carte le signale.
essayer("revenus", ids = c("pauvrete", "revenu"), bloc = {
  filo <- melodi_cache(jeu_revenus)
  filo$GEO <- as.character(filo$GEO)
  filo$OBS_VALUE <- as.numeric(filo$OBS_VALUE)
  filo <- filo[filo$TIME_PERIOD == max(filo$TIME_PERIOD), ]
  mesures <- c(pauvrete = "PR_MD60", revenu = "MED_SL")
  for (id in names(mesures)) {
    d <- filo[filo$FILOSOFI_MEASURE == mesures[[id]], ]
    v <- setNames(d$OBS_VALUE[d$GEO_OBJECT %in% c("COM", "ARM")], d$GEO[d$GEO_OBJECT %in% c("COM", "ARM")])
    e <- d[d$GEO_OBJECT == "EPCI", ]
    v <- v[com$code]; names(v) <- com$code
    manque <- is.na(v)
    v[manque] <- e$OBS_VALUE[match(com$epci[manque], e$GEO)]
    impute[[id]] <- which(manque & !is.na(v)) - 1      # indices à partir de 0, pour JavaScript
    ranger(id, v)
  }
})

# ---- 2 bis. Indice européen de défavorisation (EDI) ----------------
# Publié par Santé publique France (Odissé) pour chaque IRIS. Les IRIS comptent environ
# 2 000 habitants : on fait la moyenne simple des IRIS de chaque commune. Les communes
# non découpées n'ont qu'un IRIS, qui porte le code de la commune suivi de 0000.
essayer("edi", {
  d <- lire_tableau(telecharger(url_edi, "data/brut/edi.csv"))
  # colonne des codes IRIS : neuf caractères, dont les cinq premiers forment le code commune
  est_iris <- sapply(d, function(x) mean(grepl("^[0-9][0-9AB][0-9]{7}$", head(x, 2000))) > 0.8)
  if (!any(est_iris)) stop("Colonne des codes IRIS introuvable. Colonnes : ", paste(names(d), collapse = " | "))
  ci <- names(d)[which(est_iris)[1]]
  # le score continu s'il existe, sinon le quintile
  ce <- tryCatch(colonne(d, "edi|score", exclure = "quint|class|d[ée]cile|lib|nom|code|iris|ann"),
                 error = function(e) colonne(d, "quint"))
  cat("   codes IRIS :", ci, "| valeurs :", ce, "\n")
  m <- tapply(nombre(d[[ce]]), substr(d[[ci]], 1, 5), mean, na.rm = TRUE)
  ranger("edi", setNames(as.numeric(m), names(m)), completer = TRUE)
  if (grepl("quint", ce, ignore.case = TRUE)) preciser("edi", unite = "quintile moyen des IRIS")
})

# ---- 2 ter. Taux de chômage (Insee, recensement) -------------------
# Chômeurs rapportés aux actifs de 15 à 64 ans, au sens du recensement : c'est la seule mesure
# du chômage disponible pour chaque commune (le taux au sens du BIT s'arrête aux zones d'emploi).
essayer("chomage", {
  d <- totaux(melodi_cache(jeu_actifs), sauf = c("EMPSTA_ENQ", "AGE"))
  d <- d[d$GEO_OBJECT %in% c("COM", "ARM"), ]
  d <- d[d$TIME_PERIOD == max(d$TIME_PERIOD), ]
  if (!all(c("EMPSTA_ENQ", "AGE") %in% names(d))) stop("Colonnes EMPSTA_ENQ ou AGE absentes. Colonnes : ", paste(names(d), collapse = " | "))
  age <- if ("Y15T64" %in% d$AGE) "Y15T64" else "_T"
  d <- d[d$AGE == age, ]
  cat("   statuts :", paste(unique(d$EMPSTA_ENQ), collapse = ", "), "| âges :", age, "| recensement", max(d$TIME_PERIOD), "\n")
  somme <- function(statuts) { k <- d$EMPSTA_ENQ %in% statuts; tapply(as.numeric(d$OBS_VALUE[k]), as.character(d$GEO[k]), sum) }
  chomeurs <- somme("2")
  actifs <- if ("1T2" %in% d$EMPSTA_ENQ) somme("1T2") else somme(c("1", "2"))
  communes <- intersect(names(chomeurs), names(actifs))
  taux <- 100 * chomeurs[communes] / actifs[communes]
  taux[!is.finite(taux)] <- NA
  ranger("chomage", taux, completer = TRUE)
  preciser("chomage", unite = paste0("% des actifs de ", if (age == "Y15T64") "15 à 64 ans" else "15 ans ou plus", " (recensement ", max(d$TIME_PERIOD), ")"),
           source = paste0("Insee, recensement de la population ", max(d$TIME_PERIOD)))
})

# ---- 3. Accès aux médecins généralistes (DREES, APL) --------------
essayer("apl", {
  f <- telecharger(ressource_datagouv(jeu_apl, "m[ée]decins g[ée]n[ée]ralistes"), "data/brut/apl.xlsx")
  # une feuille par année : on prend la plus récente qui contient « Code commune »
  feuilles <- readxl::excel_sheets(f)
  an <- suppressWarnings(as.numeric(sub(".*(20[0-9]{2}).*", "\\1", feuilles)))
  feuilles <- feuilles[order(-ifelse(is.na(an), 0, an), -seq_along(feuilles))]
  for (s in feuilles) { d <- lire_tableau(f, s, entete = "^code commune"); if (!is.null(d)) break }
  cat("   feuille :", s, "\n")
  code <- code_commune(d[[colonne(d, "^code commune")]])
  apl <- nombre(d[[colonne(d, "APL", exclure = "65|moins|code")]])
  ranger("apl", setNames(apl, code))
})

# ---- 3 bis. Accessibilité aux soins de premier recours (SCALe) ------
# Indice calculé par la plateforme MapInMed (Inserm U1086) et l'UMR IDEES pour chaque
# zone résidentielle : distance moyenne aux équipements de premier recours, pondérée par la
# pression de la population sur chacun. Plus il est élevé, plus l'accès est difficile.
# Chaque zone est rattachée à la commune qui contient son centre, puis on fait la moyenne
# des zones de la commune, pondérée par leur surface. Le premier traitement est long
# (2,7 millions de zones) ; le résultat est ensuite gardé.
if (avec_scale) essayer("scale", {
  # la lecture des 2,7 millions de zones est longue : leurs centres sont gardés une fois pour toutes
  sortie <- "data/brut/scale_points.rds"
  if (!file.exists(sortie)) {
    f <- telecharger(ressource_datagouv(jeu_scale, NULL, "zip"), "data/brut/scale.zip", jours = 3650)
    unzip(f, exdir = "data/brut/scale")
    shp <- list.files("data/brut/scale", "\\.shp$", recursive = TRUE, full.names = TRUE)[1]
    if (is.na(shp)) stop("Aucun fichier .shp dans l'archive SCALe")
    z <- st_read(shp, quiet = TRUE)
    cat("   zones résidentielles :", nrow(z), "| colonnes :", paste(names(z), collapse = ", "), "\n")
    tab <- st_drop_geometry(z)
    # la valeur de l'indice (score_sant), et non ses tertiles (sante_3) ou déciles (sante_10)
    cv <- colonne(tab, "score|scale|acces|indice", exclure = "ter|dec|quint|class|^id|code")
    # chaque zone pèse selon sa surface bâtie, faute de population dans le fichier
    cp <- c(grep("^pop|hab", names(tab), ignore.case = TRUE, value = TRUE), grep("area|surf", names(tab), ignore.case = TRUE, value = TRUE))[1]
    cat("   colonne retenue :", cv, if (!is.na(cp)) paste("| poids :", cp), "\n")
    if (is.na(st_crs(z))) st_crs(z) <- 2154
    pts <- st_sf(v = nombre(tab[[cv]]), p = if (is.na(cp)) 1 else nombre(tab[[cp]]),
                 geometry = st_centroid(st_geometry(z)))
    rm(z, tab); gc()
    saveRDS(pts, sortie)
  }
  pts <- readRDS(sortie)
  dans <- st_drop_geometry(st_join(pts, st_transform(contours, st_crs(pts)), join = st_within))
  dans <- dans[!is.na(dans$code) & !is.na(dans$v) & !is.na(dans$p), ]
  m <- tapply(dans$v * dans$p, dans$code, sum) / tapply(dans$p, dans$code, sum)
  ranger("scale", setNames(as.numeric(m), names(m)), completer = TRUE)
})

# ---- 4. Fibre optique (Arcep) -------------------------------------
essayer("fibre", {
  f <- telecharger(ressource_datagouv(jeu_fibre, "-Commune$", "zip"), "data/brut/fibre.zip")
  unlink("data/brut/fibre", recursive = TRUE)
  unzip(f, exdir = "data/brut/fibre")
  tous <- list.files("data/brut/fibre", recursive = TRUE, full.names = TRUE)
  cat("   contenu de l'archive :", paste(basename(tous), collapse = ", "), "\n")
  for (z in grep("\\.zip$", tous, value = TRUE, ignore.case = TRUE)) unzip(z, exdir = "data/brut/fibre")   # archive dans l'archive
  # depuis 2026, l'archive contient une carte (shapefile) : on n'en garde que la table
  fichier <- list.files("data/brut/fibre", "\\.(csv|txt|xlsx?|shp)$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)[1]
  if (is.na(fichier)) stop("Aucun tableau dans l'archive. Contenu : ", paste(basename(list.files("data/brut/fibre", recursive = TRUE)), collapse = " | "))
  cat("   fichier :", basename(fichier), "\n")
  # la table du shapefile est en Latin-1 alors que son .cpg annonce de l'UTF-8 : si la lecture
  # échoue sur les accents, on demande à GDAL de convertir depuis Windows-1252
  lire_shp <- function(f) tryCatch(st_read(f, quiet = TRUE), error = function(e) st_read(f, quiet = TRUE, options = "ENCODING=WINDOWS-1252"))
  d <- if (grepl("\\.shp$", fichier, ignore.case = TRUE)) en_utf8(st_drop_geometry(lire_shp(fichier))) else lire_tableau(fichier, entete = "code")
  cat("   colonnes :", paste(names(d), collapse = ", "), "\n")
  code <- code_commune(d[[colonne(d, "code.*(insee|commune)|^insee")]])
  locaux <- nombre(d[[colonne(d, "locaux", exclure = "raccord|[ée]ligib")]])
  racc <- names(d)[grepl("raccordable|ftth", names(d), ignore.case = TRUE)]
  if (!length(racc)) stop("Aucune colonne de locaux raccordables. Colonnes : ", paste(names(d), collapse = " | "))
  fibre <- pmin(100, 100 * nombre(d[[tail(racc, 1)]]) / locaux)     # dernière colonne = trimestre le plus récent
  ranger("fibre", setNames(fibre, code))
})

# ---- 5. Pollution de l'air (Ineris) --------------------------------
essayer("air", ids = c("no2", "pm25"), bloc = {
  f <- telecharger(url_air, "data/brut/air.zip", jours = 3650)
  unzip(f, exdir = "data/brut/air")
  fichiers <- list.files("data/brut/air", "\\.(csv|txt)$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  # un fichier par année, avec tous les polluants en colonnes : on prend la dernière année
  an <- suppressWarnings(as.numeric(sub(".*_(20[0-9]{2})_.*", "\\1", basename(fichiers))))
  fichier <- fichiers[which.max(an)]
  # le fichier commence par une ligne de notes : les titres sont sur la première ligne qui cite le NO2
  d <- lire_tableau(fichier, entete = "NO2")
  if (is.null(d)) stop("Ligne des titres introuvable dans ", basename(fichier))
  cat("   fichier :", basename(fichier), "\n   colonnes :", paste(names(d), collapse = ", "), "\n")
  code <- code_commune(d[[colonne(d, "insee|code|com")]])
  polluants <- c(no2 = "NO2", pm25 = "PM2[._]?5")
  for (id in names(polluants)) {
    essayer(id, reprise = FALSE, bloc = {
      cols <- grep(polluants[[id]], names(d), ignore.case = TRUE, value = TRUE)
      if (!length(cols)) stop("Aucune colonne pour ", id, ". Colonnes : ", paste(names(d), collapse = " | "))
      # plusieurs colonnes : on préfère la moyenne pondérée par la population (l'exposition des
      # habitants plutôt que celle du territoire), sinon la moyenne simple
      cv <- c(grep("ponder", cols, ignore.case = TRUE, value = TRUE), grep("moy|mean", cols, ignore.case = TRUE, value = TRUE), cols)[1]
      cat("   colonne retenue :", cv, "\n")
      ranger(id, setNames(nombre(d[[cv]]), code))
    })
  }
})

# ---- 5 bis. Nuits chaudes (Météo-France, Safran) -------------------
# Nombre moyen de nuits par an où la température minimale reste d'au moins 20 °C, sur la grille
# de 8 km de la réanalyse Safran. Chaque commune reçoit la valeur du point de grille le plus
# proche d'un point situé à l'intérieur de son territoire.
essayer("chaleur", {
  for (a in annees_chaleur) {
    resume <- paste0("data/brut/chaleur_", a, ".rds")
    if (file.exists(resume)) next
    cat("   année", a, ": téléchargement et lecture\n")
    tryCatch({
      gz <- telecharger(ressource_datagouv(jeu_sim, paste0("QUOT_SIM2_", a, "(\\.csv\\.gz)?$")), paste0("data/brut/sim2_", a, ".csv.gz"), jours = 3650)
      csv <- degonfler(gz, file.path(tempdir(), paste0("sim2_", a, ".csv")))
      d <- lire_colonnes(csv, c(x = "^LAMBX$", y = "^LAMBY$", tmin = "^TINF_H(_Q)?$"))   # TINF_H : minimale sous abri
      d$tmin <- nombre(d$tmin)
      d <- d[!is.na(d$tmin), ]
      point <- paste(d$x, d$y)
      r <- data.frame(x = nombre(d$x), y = nombre(d$y))[!duplicated(point), ]
      k <- point[!duplicated(point)]
      r$jours <- as.numeric(table(point)[k])
      r$nuits <- as.numeric(tapply(d$tmin >= seuil_nuit, point, sum)[k])
      saveRDS(r, resume)
      cat("   ", a, ":", nrow(r), "points,", round(sum(r$nuits) / nrow(r), 1), "nuits chaudes en moyenne\n")
      rm(d, point); gc()
      unlink(csv); unlink(gz)
    }, error = function(e) {
      message("   année ", a, " non lue : ", conditionMessage(e))
      unlink(file.path(tempdir(), paste0("sim2_", a, ".csv")))   # le fichier décompressé est volumineux
    })
  }
  annees <- annees_chaleur[file.exists(paste0("data/brut/chaleur_", annees_chaleur, ".rds"))]
  if (!length(annees)) stop("aucune année de la réanalyse Safran n'a pu être lue")
  r <- do.call(rbind, lapply(paste0("data/brut/chaleur_", annees, ".rds"), readRDS))
  cle <- paste(r$x, r$y)
  g <- r[!duplicated(cle), c("x", "y")]
  g$v <- as.numeric((tapply(r$nuits, cle, sum) / tapply(r$jours, cle, sum))[paste(g$x, g$y)]) * 365.25
  # coordonnées en Lambert II étendu, en hectomètres dans les fichiers de Météo-France
  if (max(g$x) < 1e5) { g$x <- 100 * g$x; g$y <- 100 * g$y }
  grille <- st_transform(st_as_sf(g, coords = c("x", "y"), crs = 27572), 2154)
  centres <- st_point_on_surface(st_geometry(st_transform(contours, 2154)))
  proche <- st_nearest_feature(centres, grille)
  ranger("chaleur", setNames(grille$v[proche], com$code))
  periode <- if (length(annees) > 1) paste0(min(annees), "-", max(annees)) else annees
  preciser("chaleur", unite = paste0("nuits par an (moyenne ", periode, ")"),
           source = paste0("Météo-France, réanalyse Safran (SIM2), températures minimales ", periode))
})

# ---- 6. Sites Seveso (Géorisques) ---------------------------------
if (avec_seveso) essayer("seveso", {
  # les installations ne sont diffusées que par un service WFS : GDAL sait le lire directement
  fichier <- "data/brut/icpe.gpkg"
  if (!file.exists(fichier) || difftime(Sys.time(), file.mtime(fichier), units = "days") > 25) {
    wfs <- paste0("WFS:", sub("\\?.*", "", ressource_datagouv(jeu_icpe, NULL, "wfs")))
    couches <- st_layers(wfs)$name
    cat("   couches du service :", paste(couches, collapse = ", "), "\n")
    icpe <- st_read(wfs, layer = grep("InstallationsClassees", couches, value = TRUE)[1], quiet = TRUE)
    st_write(icpe, fichier, delete_dsn = TRUE, quiet = TRUE)
  }
  icpe <- st_read(fichier, quiet = TRUE)
  s <- st_drop_geometry(icpe)[[colonne(icpe, "seveso")]]
  icpe <- icpe[grepl("haut|bas", s, ignore.case = TRUE) & !grepl("non", s, ignore.case = TRUE), ]
  cat("   sites Seveso :", nrow(icpe), "\n")
  dans <- st_join(st_transform(icpe, 2154), st_transform(contours, 2154), join = st_within)
  n <- table(factor(dans$code, levels = com$code))
  ranger("seveso", setNames(as.numeric(n), names(n)))
})

# ---- 7. Catastrophes naturelles (base Gaspar) ---------------------
essayer("catnat", {
  f <- telecharger(ressource_datagouv(jeu_catnat, NULL, "csv"), "data/brut/catnat.csv")
  d <- lire_tableau(f)
  # le fichier n'a pas toujours de ligne de titres : on le relit alors sans
  if (any(grepl("^[0-9AB]{5}$", names(d)))) d <- data.table::fread(f, data.table = FALSE, encoding = "UTF-8", colClasses = "character", header = FALSE)
  # colonne des codes commune : celle dont les valeurs retrouvent le plus de communes actuelles
  part <- sapply(d, function(x) mean(code_commune(head(x, 5000)) %in% com$code))
  cc <- names(d)[which.max(part)]
  cat("   codes commune lus dans", cc, "(", round(100 * max(part)), "% retrouvés )\n")
  # un arrêté = une ligne ; la première colonne, si ses valeurs sont toutes différentes, n'est
  # qu'un numéro de ligne : on l'écarte avant de retirer les doublons signalés dans la base
  if (cc != names(d)[1] && !anyDuplicated(d[[1]])) d <- d[, -1, drop = FALSE]
  d <- unique(d)
  n <- table(factor(code_commune(d[[cc]]), levels = unique(c(com$code, plm))))
  v <- setNames(as.numeric(n), names(n))
  # arrêtés pris pour Paris, Lyon ou Marseille entières : valables pour chaque arrondissement
  v[names(v) != code_plm(names(v)) & v == 0] <- NA
  ranger("catnat", v)
})

# ---- 8. Abstention (ministère de l'Intérieur) ---------------------
essayer("abstention", {
  f <- telecharger(ressource_datagouv(jeu_election, "subcom", "xlsx"), "data/brut/election.xlsx", jours = 3650)
  d <- lire_tableau(f)
  dep <- as.character(d[[colonne(d, "code.*d[ée]partement")]])
  dep <- ifelse(grepl("^[0-9]$", dep), paste0("0", dep), dep)
  cm <- sprintf("%03s", as.character(d[[colonne(d, "code.*commune")]]))
  cm <- gsub(" ", "0", cm)
  abst <- 100 * nombre(d[[colonne(d, "^abstentions$")]]) / nombre(d[[colonne(d, "^inscrits$")]])
  ranger("abstention", setNames(abst, paste0(dep, cm)))
})

# ---- 9. Évolution de l'emploi salarié privé (Urssaf) --------------
# Effectifs au 31 décembre par commune et code APE. On demande au serveur de faire
# lui-même la somme par commune pour deux années seulement, ce qui donne un petit fichier.
essayer("emploi", {
  meta <- fromJSON(url_urssaf)
  champs <- c(meta$fields$name, meta$dataset$fields$name)
  annees <- as.numeric(sub("effectifs_salaries_", "", grep("^effectifs_salaries_[0-9]{4}$", champs, value = TRUE)))
  if (!length(annees)) stop("Champs d'effectifs introuvables. Champs : ", paste(champs, collapse = " | "))
  a1 <- max(annees); a0 <- max(min(annees), a1 - duree_dynamique)
  cc <- grep("^code_commune$|^code.*commune|codgeo", champs, value = TRUE)[1]
  if (is.na(cc)) stop("Champ du code commune introuvable. Champs : ", paste(champs, collapse = " | "))
  choix <- paste0(cc, " as code, sum(effectifs_salaries_", a0, ") as e0, sum(effectifs_salaries_", a1, ") as e1")
  adresse <- paste0(url_urssaf, "/exports/csv?delimiter=%3B&select=", URLencode(choix, reserved = TRUE), "&group_by=", cc)
  u <- lire_tableau(telecharger(adresse, paste0("data/brut/urssaf_", a0, "_", a1, ".csv")))
  code <- code_commune(u$code)
  e0 <- tapply(nombre(u$e0), code, sum, na.rm = TRUE)
  e1 <- tapply(nombre(u$e1), code, sum, na.rm = TRUE)[names(e0)]
  # intercommunalité de chaque code du fichier ; Paris, Lyon et Marseille entières comptent dans la leur
  epci_de <- setNames(com$epci, com$code)
  epci_de[plm] <- com$epci[match(plm, code_plm(com$code))]
  ep <- epci_de[names(e0)]
  evol_epci <- 100 * (tapply(e1, ep, sum, na.rm = TRUE) / tapply(e0, ep, sum, na.rm = TRUE) - 1)
  v <- ifelse(e0 >= seuil_emploi, 100 * (e1 / e0 - 1), NA)
  # communes trop petites : évolution de leur intercommunalité
  petites <- names(v)[is.na(v)]
  v[petites] <- evol_epci[ep[petites]]
  # communes absentes du fichier (sauf les arrondissements, qui prendront la valeur de leur ville) : idem
  absentes <- com$code[!com$code %in% names(v) & !(code_plm(com$code) %in% names(v))]
  v <- c(v, setNames(evol_epci[com$epci[match(absentes, com$code)]], absentes))
  v[!is.finite(v)] <- NA
  ranger("emploi", v)
  impute[["emploi"]] <- sort(unique(c(impute[["emploi"]], which(com$code %in% c(petites, absentes)) - 1)))
  rapport["emploi"] <- paste0(sub(" \\(dont.*", "", rapport["emploi"]), " (dont ", length(impute[["emploi"]]),
                              " qui reçoivent l'évolution de leur intercommunalité ou de leur ville, faute de ", seuil_emploi, " salariés au départ)")
  cat("   évolution nationale :", round(100 * (sum(e1, na.rm = TRUE) / sum(e0, na.rm = TRUE) - 1), 1), "% de", a0, "à", a1, "\n")
  preciser("emploi", unite = paste0("% entre ", a0, " et ", a1),
           source = paste0("Urssaf, effectifs salariés du secteur privé au 31 décembre (", a0, " et ", a1, ")"))
})

# ---- 10. Évolution de la population (Insee) -----------------------
# Séries historiques dans la géographie communale récente : les fusions sont déjà
# reportées sur les années anciennes, l'évolution est donc comparable.
essayer("population", {
  p <- melodi_cache(jeu_population)
  p <- p[p$GEO_OBJECT %in% c("COM", "ARM"), ]
  # s'il y a plusieurs mesures (population municipale, totale…), on garde la municipale
  mesure <- grep("MEASURE", names(p), value = TRUE)[1]
  if (!is.na(mesure) && length(unique(p[[mesure]])) > 1) {
    cat("   mesures :", paste(unique(p[[mesure]]), collapse = ", "), "\n")
    p <- p[grepl("PMUN|MUN", p[[mesure]]), ]
  }
  an <- as.numeric(substr(p$TIME_PERIOD, 1, 4))
  a1 <- max(an); a0 <- max(an[an <= a1 - duree_dynamique])
  pop <- function(a) tapply(as.numeric(p$OBS_VALUE[an == a]), as.character(p$GEO[an == a]), sum)
  p0 <- pop(a0); p1 <- pop(a1)
  communes <- intersect(names(p0), names(p1))
  evol <- 100 * (p1[communes] / p0[communes] - 1)
  evol[!is.finite(evol)] <- NA
  ranger("population", evol, completer = TRUE)
  preciser("population", unite = paste0("% entre ", a0, " et ", a1),
           source = paste0("Insee, populations municipales de ", a0, " et ", a1))
})

# ---- 11. Surmortalité : indice comparatif de mortalité (ICM) ------
# Décès observés pendant dix ans, rapportés aux décès attendus si chaque classe d'âge de la
# commune mourait au rythme national (standardisation indirecte). 100 = la France.
# Les petites communes ont trop peu de décès pour un indice fiable : on le lisse par la
# méthode bayésienne empirique (Clayton et Kaldor, 1987 ; Marshall, 1991), qui rapproche
# un indice de la moyenne d'autant plus que le nombre de décès attendus est faible.
essayer("icm", {
  # taux de mortalité nationaux par âge détaillé (Eurostat)
  eurostat <- function(table) {
    adresse <- paste0(url_eurostat, table, "?geo=FR&sex=T&unit=NR&time=", annee_mortalite)
    j <- fromJSON(telecharger(adresse, paste0("data/brut/", table, "_", annee_mortalite, ".json"), jours = 3650))
    pos <- unlist(j$dimension$age$category$index)
    val <- unlist(j$value)
    if (is.null(names(val))) names(val) <- seq_along(val) - 1
    setNames(as.numeric(val[as.character(pos)]), names(pos))
  }
  morts <- eurostat("demo_magec"); vivants <- eurostat("demo_pjan")
  ages <- intersect(names(morts), names(vivants))
  b <- bornes_age(ages); ok <- !is.na(b[, 1]) & !is.na(morts[ages]) & !is.na(vivants[ages])
  ages <- ages[ok]; b <- b[ok, , drop = FALSE]
  # population des communes par classe d'âge (recensement le plus récent)
  p <- totaux(melodi_cache(jeu_age), sauf = "AGE")
  p <- p[p$GEO_OBJECT %in% c("COM", "ARM"), ]
  p <- p[p$TIME_PERIOD == max(p$TIME_PERIOD), ]
  classes <- decoupage_age(unique(as.character(p$AGE)))
  if (is.null(classes)) stop("Classes d'âge du recensement inutilisables : ", paste(unique(p$AGE), collapse = ", "))
  cat("   classes d'âge :", paste(classes, collapse = ", "), "| recensement", max(p$TIME_PERIOD), "\n")
  bc <- bornes_age(classes)
  taux <- sapply(seq_along(classes), function(k) { a <- b[, 1] >= bc[k, 1] & b[, 1] < bc[k, 2]; sum(morts[ages][a]) / sum(vivants[ages][a]) })
  names(taux) <- classes
  p <- p[p$AGE %in% classes, ]
  attendus_an <- tapply(as.numeric(p$OBS_VALUE) * taux[as.character(p$AGE)], as.character(p$GEO), sum)
  # décès observés, cumulés sur les dernières années
  d <- totaux(melodi_cache(jeu_deces))
  d <- d[d$GEO_OBJECT %in% c("COM", "ARM"), ]
  an <- as.numeric(substr(d$TIME_PERIOD, 1, 4))
  annees <- sort(unique(an), decreasing = TRUE)[seq_len(min(duree_mortalite, length(unique(an))))]
  d <- d[an %in% annees, ]
  observes <- tapply(as.numeric(d$OBS_VALUE), as.character(d$GEO), sum, na.rm = TRUE)
  cat("   décès de", min(annees), "à", max(annees), "\n")
  communes <- intersect(names(observes), names(attendus_an))
  O <- observes[communes]; E <- attendus_an[communes] * length(annees)
  ok <- E > 0
  O <- O[ok]; E <- E[ok]
  # lissage bayésien empirique (méthode des moments de Marshall)
  m <- sum(O) / sum(E); theta <- O / E
  s2 <- max(0, sum(E * (theta - m)^2) / sum(E) - m / mean(E))
  lisse <- m + s2 / (s2 + m / E) * (theta - m)
  ranger("icm", setNames(as.numeric(100 * lisse / m), names(O)), completer = TRUE)
  preciser("icm", unite = "France = 100",
           source = paste0("Insee, décès domiciliés de ", min(annees), " à ", max(annees), " et recensement ", max(p$TIME_PERIOD),
                           " ; Eurostat, mortalité par âge en ", annee_mortalite))
})

# ---- 11 bis. Mortalité prématurée (Observatoire des territoires) ----
# Fichier téléchargé à la main. Le script reconnaît seul la maille (communes, intercommunalités
# ou départements) d'après les codes. Hors des communes, chaque commune reçoit la valeur de son
# territoire.
essayer("prematuree", {
  f <- list.files(dossier_prematuree, "\\.(csv|txt|xlsx?)$", full.names = TRUE, ignore.case = TRUE)
  if (!length(f)) stop("aucun fichier dans ", dossier_prematuree, " (à télécharger sur observatoire-des-territoires.gouv.fr)")
  d <- lire_tableau(f[1], entete = "codgeo|^code")
  if (is.null(d)) stop("ligne des titres (codgeo) introuvable dans ", basename(f[1]))
  cat("   fichier :", basename(f[1]), "\n   colonnes :", paste(names(d), collapse = ", "), "\n")
  cc <- colonne(d, "^codgeo$|^code")
  # une ligne par territoire et par période : on garde la plus récente
  ca <- grep("^an$|^ann[ée]e|^p[ée]riode|^date", names(d), ignore.case = TRUE, value = TRUE)[1]
  periode <- if (is.na(ca)) NA else max(as.character(d[[ca]]), na.rm = TRUE)
  if (!is.na(ca)) d <- d[as.character(d[[ca]]) == periode, ]
  # la valeur : la dernière colonne numérique, hors code, libellé et période
  num <- names(d)[sapply(d, function(x) mean(!is.na(nombre(x))) > 0.5)]
  num <- setdiff(num, c(cc, ca, grep("lib|nom", names(d), ignore.case = TRUE, value = TRUE)))
  if (!length(num)) stop("aucune colonne de valeurs. Colonnes : ", paste(names(d), collapse = " | "))
  cv <- tail(num, 1)
  code <- trimws(as.character(d[[cc]]))
  v <- nombre(d[[cv]])
  # maille du fichier : celle dont les codes retrouvent le plus de territoires
  part <- c(commune = mean(code_commune(code) %in% com$code), epci = mean(code %in% com$epci), dep = mean(code %in% com$dep))
  maille <- names(which.max(part))
  cat("   maille :", maille, "| colonne retenue :", cv, if (!is.na(periode)) paste("| période", periode), "\n")
  x <- switch(maille,
              commune = setNames(v, code_commune(code)),
              epci = setNames(v[match(com$epci, code)], com$code),
              dep = setNames(v[match(com$dep, code)], com$code))
  ranger("prematuree", x)
  preciser("prematuree", unite = paste0("taux", c(commune = "", epci = " de l'intercommunalité", dep = " du département")[maille]),
           source = paste0("Observatoire des territoires, taux de mortalité prématurée", if (!is.na(periode)) paste0(" (", periode, ")")))
})

# ---- 12. Trajectoires longues (Cagé et Piketty) -------------------
# Pour chaque variable, on compare le rang de population de la commune la première et la
# dernière année disponibles : un rang qui baisse signale un décrochage relatif, quelle
# que soit l'inflation ou la croissance générale.
essayer("piketty", ids = names(piketty), bloc = {
  for (id in names(piketty)) {
    f <- list.files(dossier_piketty, paste0("^", piketty_fichiers[[id]], "\\.csv$"), recursive = TRUE, full.names = TRUE, ignore.case = TRUE)[1]
    if (is.na(f)) { rapport[id] <- paste0("ÉCHEC : ", piketty_fichiers[[id]], ".csv absent de ", dossier_piketty); next }
    # on lit d'abord les seuls noms de colonnes : les fichiers pèsent plusieurs centaines de Mo
    noms <- en_utf8(data.table::fread(f, nrows = 0, data.table = FALSE)) |> names()
    cc <- grep("^codecommune$|^code_?commune|^codgeo|^insee", noms, ignore.case = TRUE, value = TRUE)[1]
    larges <- grep("(18|19|20)[0-9]{2}$", noms, value = TRUE)
    prefixe <- sub("_?(18|19|20)[0-9]{2}$", "", larges)
    variables <- if (length(larges)) unique(prefixe) else noms
    cat("   ", basename(f), ": variables", paste(variables, collapse = ", "), "\n")
    var <- grep(piketty[[id]], variables, ignore.case = TRUE, value = TRUE)[1]
    if (is.na(cc) || is.na(var)) { rapport[id] <- paste0("ÉCHEC : code commune ou variable « ", piketty[[id]], " » introuvable dans ", basename(f)); next }
    if (length(larges)) {                 # une colonne par année : revmoy1960, revmoy1961…
      cols <- larges[prefixe == var]
      d <- data.table::fread(f, select = c(cc, cols), colClasses = "character", data.table = FALSE)
      s <- data.frame(code = rep(code_commune(d[[cc]]), length(cols)), annee = rep(as.numeric(sub(".*((18|19|20)[0-9]{2})$", "\\1", cols)), each = nrow(d)),
                      valeur = nombre(unlist(d[cols], use.names = FALSE)))
    } else {                              # une colonne année
      ca <- grep("^annee$|^year$|^an$", noms, ignore.case = TRUE, value = TRUE)[1]
      d <- data.table::fread(f, select = c(cc, ca, var), colClasses = "character", data.table = FALSE)
      s <- data.frame(code = code_commune(d[[cc]]), annee = as.numeric(d[[ca]]), valeur = nombre(d[[var]]))
    }
    s <- s[!is.na(s$valeur) & s$code %in% com$code, ]
    # première et dernière années renseignées pour au moins 80 % des communes
    part <- tapply(s$code, s$annee, function(x) length(unique(x))) / nrow(com)
    annees <- as.numeric(names(part)[part >= 0.8])
    if (!length(annees)) annees <- as.numeric(names(part))
    a0 <- min(annees); a1 <- max(annees)
    cat("   ", id, ": variable", var, "de", a0, "à", a1, "\n")
    rang <- function(a) { x <- s[s$annee == a & !duplicated(paste(s$code, s$annee)), ]; setNames(rang_pop(x$valeur, com$population[match(x$code, com$code)]), x$code) }
    r0 <- rang(a0); r1 <- rang(a1)
    communes <- intersect(names(r0), names(r1))
    ranger(id, setNames(100 * (r1[communes] - r0[communes]), communes), completer = TRUE)
    preciser(id, unite = paste0("points de centile entre ", a0, " et ", a1),
             source = paste0("Cagé et Piketty (2023), Une histoire du conflit politique, variable ", var))
  }
})

# ---- 13. Pesticides et nitrates dans l'eau du robinet (ARS) -------
# Chaque prélèvement du contrôle sanitaire est fait sur une unité de distribution (UDI), un
# réseau où l'eau est de qualité homogène, et chaque UDI dessert une ou plusieurs communes.
# Pour une commune, on fait la moyenne de tous les prélèvements de ses réseaux pendant les
# années retenues. Deux paramètres : le total des pesticides analysés (code PESTOT, limite de
# qualité 0,5 µg/L) et les nitrates (code NO3, limite 50 mg/L).
essayer("eau", ids = c("eau_pesticides", "eau_nitrates"), bloc = {
  parametres <- c(eau_pesticides = "PESTOT", eau_nitrates = "NO3")
  for (a in annees_eau) {
    resume <- paste0("data/brut/eau_", a, ".rds")
    if (file.exists(resume)) next
    cat("   année", a, ": téléchargement et lecture, plusieurs minutes\n")
    tryCatch({
      z <- telecharger(ressource_datagouv(jeu_eau, paste0("^dis-", a, "\\.zip$")), paste0("data/brut/eau_", a, ".zip"), jours = 3650)
      dossier <- file.path(tempdir(), paste0("eau_", a))
      unzip(z, exdir = dossier)
      fichiers <- list.files(dossier, recursive = TRUE, full.names = TRUE)
      trouver <- function(m) {
        f <- fichiers[grepl(m, basename(fichiers), ignore.case = TRUE)]
        if (!length(f)) stop("fichier ", m, " absent du zip. Fichiers : ", paste(basename(fichiers), collapse = ", "))
        f
      }
      udi <- lire_colonnes(trouver("UDI"), c(code = "^insee", cdreseau = "^cdreseau$"))
      plv <- lire_colonnes(trouver("PLV"), c(referenceprel = "^referenceprel$", cdreseau = "^cdreseau$"))
      res <- lire_colonnes(trouver("RESULT"), c(referenceprel = "^referenceprel$", parametre = "^cdparametresiseeaux$", valeur = "^valtraduite$"))
      res$id <- names(parametres)[match(toupper(trimws(res$parametre)), parametres)]
      if (!any(!is.na(res$id))) stop("paramètres ", paste(parametres, collapse = " et "), " introuvables. Exemples : ", paste(head(unique(res$parametre), 30), collapse = ", "))
      res <- res[!is.na(res$id), ]
      res$valeur <- nombre(res$valeur)
      res$cdreseau <- plv$cdreseau[match(res$referenceprel, plv$referenceprel)]
      res <- res[!is.na(res$valeur) & !is.na(res$cdreseau), ]
      # nombre de prélèvements et somme des valeurs, par paramètre et par réseau
      cle <- paste(res$id, res$cdreseau)
      mesures <- res[!duplicated(cle), c("id", "cdreseau")]
      k <- paste(mesures$id, mesures$cdreseau)
      mesures$n <- as.numeric(table(cle)[k])
      mesures$somme <- as.numeric(tapply(res$valeur, cle, sum)[k])
      saveRDS(list(udi = unique(data.frame(code = code_commune(udi$code), cdreseau = udi$cdreseau)), mesures = mesures), resume)
      cat("   ", a, ":", nrow(res), "analyses retenues\n")
      rm(res, plv, udi); gc()
      unlink(dossier, recursive = TRUE); unlink(z)
    }, error = function(e) { message("   année ", a, " non lue : ", conditionMessage(e)) })
  }
  annees <- annees_eau[file.exists(paste0("data/brut/eau_", annees_eau, ".rds"))]
  if (!length(annees)) stop("aucune année du contrôle sanitaire n'a pu être lue")
  r <- lapply(paste0("data/brut/eau_", annees, ".rds"), readRDS)
  udi <- unique(do.call(rbind, lapply(r, `[[`, "udi")))
  m <- do.call(rbind, lapply(r, `[[`, "mesures"))
  periode <- if (length(annees) > 1) paste0(min(annees), "-", max(annees)) else annees
  for (id in names(parametres)) {
    x <- merge(udi, m[m$id == id, ], by = "cdreseau")   # une ligne par commune, réseau et année
    n <- tapply(x$n, x$code, sum)
    s <- tapply(x$somme, x$code, sum)
    ranger(id, setNames(as.numeric(s / n), names(n)), completer = TRUE)
    preciser(id, unite = paste0(if (id == "eau_nitrates") "mg/L" else "µg/L", ", moyenne des contrôles ", periode),
             source = paste0("Ministère de la Santé et ARS, contrôle sanitaire de l'eau distribuée (", periode, ")"))
  }
})

# ---- 13 bis. Accès au lycée et aux formations post-bac ------------
# Pour chaque carreau habité de 1 km, distance à vol d'oiseau entre son centre et l'établissement le
# plus proche : un lycée qui propose la voie générale, ou une formation de Parcoursup (BTS, BUT,
# licence, classe préparatoire, école…). Les établissements privés comptent aussi. La valeur d'une
# commune est la moyenne de ses carreaux, pondérée par leur population : c'est la distance que
# parcourt en moyenne un habitant, hameaux compris. Une petite commune sans centre de carreau sur son
# territoire reçoit la distance depuis un point situé à l'intérieur de ses limites.
essayer("education_acces", ids = c("lycee", "superieur"), bloc = {
  cont <- st_transform(contours, 2154)
  centres <- st_point_on_surface(st_geometry(cont))
  sortie <- "data/brut/carreaux_1km.rds"
  if (!file.exists(sortie)) {
    z <- telecharger(url_carreaux, "data/brut/carreaux_1km.zip", jours = 3650)
    unzip(z, exdir = file.path(tempdir(), "carreaux"))
    f <- list.files(file.path(tempdir(), "carreaux"), "\\.csv$", recursive = TRUE, full.names = TRUE)[1]
    g <- lire_colonnes(f, c(id = "^id_carreau", pop = "^pop$"))
    # l'identifiant donne le coin inférieur gauche du carreau (CRS3035RES1000mN2029000E4252000)
    n <- as.numeric(sub(".*N([0-9]+)E.*", "\\1", g$id)); e <- as.numeric(sub(".*E([0-9]+)$", "\\1", g$id))
    carreaux <- st_transform(st_as_sf(data.frame(pop = nombre(g$pop), x = e + 500, y = n + 500), coords = c("x", "y"), crs = 3035), 2154)
    carreaux$code <- cont$code[sapply(st_within(carreaux, cont), `[`, 1)]
    carreaux <- carreaux[!is.na(carreaux$code) & carreaux$pop > 0, ]
    saveRDS(carreaux, sortie)
    unlink(file.path(tempdir(), "carreaux"), recursive = TRUE)
  }
  carreaux <- readRDS(sortie)
  cat("   carreaux habités :", nrow(carreaux), "dans", length(unique(carreaux$code)), "communes\n")
  # distance moyenne des habitants de chaque commune à l'établissement le plus proche (en km)
  distance_moyenne <- function(lon, lat) {
    ok <- !is.na(lon) & !is.na(lat) & lat > 41 & lat < 52 & lon > -6 & lon < 10   # métropole
    etab <- st_transform(st_as_sf(data.frame(lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4326), 2154)
    d <- as.numeric(st_distance(carreaux, etab[st_nearest_feature(carreaux, etab), ], by_element = TRUE)) / 1000
    m <- tapply(d * carreaux$pop, carreaux$code, sum) / tapply(carreaux$pop, carreaux$code, sum)
    v <- setNames(as.numeric(m[com$code]), com$code)
    manque <- is.na(v)
    if (any(manque)) v[manque] <- as.numeric(st_distance(centres[manque], etab[st_nearest_feature(centres[manque], etab), ], by_element = TRUE)) / 1000
    v
  }
  a <- lire_colonnes(telecharger(url_annuaire, "data/brut/annuaire_education.csv"),
                     c(type = "^type_etablissement$", voie = "voie_generale", lat = "^latitude$", lon = "^longitude$"))
  lyc <- a[grepl("lyc", a$type, ignore.case = TRUE) & a$voie %in% c("1", "TRUE", "true", "Oui", "oui"), ]
  cat("   lycées avec une voie générale :", nrow(lyc), "\n")
  ranger("lycee", distance_moyenne(nombre(lyc$lon), nombre(lyc$lat)))
  p <- lire_colonnes(telecharger(url_parcoursup, "data/brut/parcoursup.csv"), c(annee = "^annee$|^session$", gps = "gps"))
  derniere <- max(p$annee, na.rm = TRUE)
  p <- p[p$annee == derniere, ]
  gps <- strsplit(p$gps, ",")
  cat("   formations post-bac de Parcoursup", derniere, ":", nrow(p), "\n")
  ranger("superieur", distance_moyenne(nombre(sapply(gps, `[`, 2)), nombre(sapply(gps, `[`, 1))))
  preciser("superieur", source = paste0("Ministère de l'Enseignement supérieur, cartographie des formations Parcoursup ", derniere, " ; Insee, population au carreau de 1 km (recensement 2021)"))
  preciser("lycee", source = "Ministère de l'Éducation nationale, annuaire de l'éducation ; Insee, population au carreau de 1 km (recensement 2021)")
})

# ---- 13 ter. Ségrégation sociale entre collèges (DEPP, IPS) --------
# Dans chaque intercommunalité, écart-type de l'indice de position sociale (IPS) moyen de ses
# collèges publics et privés, chacun pesant selon son nombre d'élèves. Un écart fort veut dire que
# les enfants d'un même territoire ne vont pas dans les mêmes collèges selon leur origine sociale.
# Toutes les communes reçoivent la valeur de leur intercommunalité ; avec un seul collège, elle est nulle.
essayer("segregation", {
  d <- lire_colonnes(telecharger(ressource_datagouv(jeu_ips, NULL, "csv"), "data/brut/ips_colleges.csv"),
                     c(rentree = "rentree", uai = "uai", code = "code_insee|code_commune", ips = "^ips"))
  rentree <- max(d$rentree)
  d <- d[d$rentree == rentree, ]
  d$uai <- toupper(d$uai); d$ips <- nombre(d$ips); d$code <- code_commune(d$code)
  # nombre d'élèves de chaque collège ; à défaut, chaque collège pèse autant
  d$poids <- tryCatch({
    e <- lire_colonnes(telecharger(url_effectifs_colleges, "data/brut/effectifs_colleges.csv"),
                       c(rentree = "rentree", uai = "numero|uai", total = "total"))
    e <- e[e$rentree == max(e$rentree), ]
    n <- tapply(nombre(e$total), toupper(e$uai), sum, na.rm = TRUE)
    as.numeric(n[d$uai])
  }, error = function(err) { message("   effectifs des collèges indisponibles, chaque collège pèse autant : ", conditionMessage(err)); 1 })
  d$poids[is.na(d$poids)] <- median(d$poids, na.rm = TRUE)
  # zone de chaque collège (intercommunalité, bassin de vie, zone d'emploi), d'après sa commune
  k <- match(d$code, com$code)
  k[is.na(k)] <- match(code_plm(d$code[is.na(k)]), code_plm(com$code))
  # écart-type de l'IPS entre les collèges de chaque zone, chacun pesant selon ses élèves
  ecart <- function(zone) {
    ok <- !is.na(zone) & !is.na(d$ips)
    z <- zone[ok]; ips <- d$ips[ok]; p <- d$poids[ok]
    m <- tapply(p * ips, z, sum) / tapply(p, z, sum)
    sqrt(tapply(p * (ips - m[z])^2, z, sum) / tapply(p, z, sum))
  }
  niveaux <- intersect(c("epci", "bv", "ze"), names(com))
  par_niveau$segregation <- lapply(setNames(niveaux, niveaux), function(n) ecart(com[[n]][k]))
  cat("   collèges :", sum(!is.na(k) & !is.na(d$ips)), "| rentrée", rentree, "\n")
  ranger("segregation", setNames(as.numeric(par_niveau$segregation$epci[com$epci]), com$code))
  preciser("segregation", source = paste0("DEPP, indices de position sociale des collèges (rentrée ", rentree, ")"))
})

# ---- 14. Usage agricole des pesticides (Solagro, Adonis) -----------
# L'indice de fréquence de traitement (IFT) compte le nombre de doses de référence appliquées
# en moyenne sur un hectare cultivé pendant une campagne. Solagro l'estime pour chaque commune à
# partir des cultures déclarées, de la part du bio et des IFT régionaux des enquêtes du ministère
# de l'Agriculture. Une commune sans terres cultivées n'a pas de valeur.
if (avec_adonis) essayer("adonis", ids = "ift", bloc = {
  f <- list.files(dossier_adonis, "\\.(csv|txt|xlsx?)$", full.names = TRUE, ignore.case = TRUE, recursive = TRUE)
  if (!length(f)) stop("aucun fichier dans ", dossier_adonis, " (données à demander à Solagro)")
  an <- suppressWarnings(as.numeric(sub(".*(20[0-9]{2}).*", "\\1", basename(f))))
  f <- f[order(-ifelse(is.na(an), 0, an))][1]
  d <- lire_tableau(f)
  cat("   fichier :", basename(f), "\n   colonnes :", paste(names(d), collapse = ", "), "\n")
  # une ligne par commune et par année : on garde la dernière année
  ca <- grep("^ann[ée]e|^year$|^campagne", names(d), ignore.case = TRUE, value = TRUE)[1]
  if (!is.na(ca)) d <- d[nombre(d[[ca]]) == max(nombre(d[[ca]]), na.rm = TRUE), ]
  cc <- colonne(d, "insee|codgeo|code_?com|^code$")
  # l'IFT total, pas l'IFT herbicides ni la part du bio ; s'il y a une colonne par année, la plus récente
  cols <- grep(motif_ift, names(d), ignore.case = TRUE, value = TRUE)
  cols <- cols[!grepl("herbi|_h$|hh|bio|class|rang|ref|r[ée]g|d[ée]p|nat|nom|surf|part", cols, ignore.case = TRUE)]
  if (!length(cols)) stop("aucune colonne d'IFT total (motif « ", motif_ift, " »). Colonnes : ", paste(names(d), collapse = " | "))
  an <- suppressWarnings(as.numeric(sub(".*(20[0-9]{2}).*", "\\1", cols)))
  ci <- cols[order(-ifelse(is.na(an), 0, an))][1]
  cat("   colonne retenue :", ci, "\n")
  ranger("ift", setNames(nombre(d[[ci]]), code_commune(d[[cc]])))
  annee <- c(if (!is.na(ca)) max(nombre(d[[ca]]), na.rm = TRUE), an[cols == ci], suppressWarnings(as.numeric(sub(".*(20[0-9]{2}).*", "\\1", basename(f)))))
  annee <- annee[!is.na(annee)][1]
  if (!is.na(annee)) preciser("ift", source = paste0("Solagro, carte Adonis des indices de fréquence de traitement (", annee, ")"))
})

# ---- Bilan ---------------------------------------------------------
cat("\n==== Bilan des indicateurs ====\n")
for (id in names(rapport)) cat(sprintf("%-11s %s\n", id, rapport[id]))
# on n'exporte que les indicateurs calculés, sans toucher à la table complète
# (sinon un indicateur qui a échoué une fois disparaîtrait des passages suivants)
indicateurs_ok <- INDICATEURS[INDICATEURS$id %in% names(valeurs), ]

st_write(cbind(contours, com[, intersect(c("nom", "population", "epci", "bv", "ze", "dep"), names(com))]), "data/communes.gpkg", delete_dsn = TRUE, quiet = TRUE)
st_write(epci, "data/epci.gpkg", delete_dsn = TRUE, quiet = TRUE)
unlink("data/en_cours.rds")   # passage complet : plus rien à reprendre
saveRDS(list(valeurs = valeurs, impute = impute, rapport = rapport, indicateurs = indicateurs_ok, par_niveau = par_niveau, zonages = zonages,
             date = format(Sys.Date())), "data/indicateurs.rds")