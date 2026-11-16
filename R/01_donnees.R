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

# ---- Les indicateurs ------------------------------------------------
# famille : situation, moyens, exposition, voix
# sens : +1 si une valeur élevée est défavorable, -1 si elle est favorable
INDICATEURS <- read.csv(text = "
id;nom;famille;sens;unite;decimales;source
pauvrete;Taux de pauvreté;situation;1;%;1;Insee, Filosofi
revenu;Niveau de vie médian;situation;-1;€ par an;0;Insee, Filosofi
apl;Accès aux médecins généralistes;moyens;-1;consultations par habitant et par an;1;DREES, accessibilité potentielle localisée (APL)
fibre;Locaux raccordables à la fibre;moyens;-1;%;0;Arcep, déploiements du très haut débit
no2;Pollution au dioxyde d'azote;exposition;1;µg/m³;1;Ineris, concentrations moyennes par commune
pm25;Pollution aux particules fines;exposition;1;µg/m³;1;Ineris, concentrations moyennes par commune
seveso;Sites industriels Seveso;exposition;1;sites dans la commune;0;Géorisques, installations classées
catnat;Catastrophes naturelles reconnues;exposition;1;arrêtés depuis 1982;0;Base Gaspar, arrêtés de catastrophe naturelle
abstention;Abstention;voix;1;% des inscrits;1;Ministère de l'Intérieur, présidentielle 2022 (1er tour)
", sep = ";", encoding = "UTF-8")

# ---- 1. Communes, population, contours ----------------------------
metropole <- c("11", "24", "27", "28", "32", "44", "52", "53", "75", "76", "84", "93", "94")
com <- fromJSON(telecharger(url_communes, "data/brut/communes.json")) |>
  filter(codeRegion %in% metropole) |>
  rename(epci = codeEpci, dep = codeDepartement)
com$population[is.na(com$population)] <- 0

contours <- st_read(telecharger(url_contours, "data/brut/communes.geojson"), quiet = TRUE) |>
  select(code) |>
  filter(code %in% com$code)
com <- com |> filter(code %in% contours$code) |> arrange(code)
contours <- contours[match(com$code, contours$code), ]
cat(nrow(com), "communes en métropole\n")

epci <- st_read(telecharger(url_epci, "data/brut/epci.geojson"), quiet = TRUE) |>
  select(code, nom) |>
  filter(code %in% com$epci)

# Tableau des valeurs : une colonne par indicateur, une ligne par commune
valeurs <- data.frame(code = com$code)
impute <- list()        # communes dont la valeur vient de leur intercommunalité
rapport <- character()  # ce qui s'est bien ou mal passé

# Ranger un indicateur : `v` est un vecteur nommé par code commune
ranger <- function(id, v) {
  v <- completer_plm(v)
  valeurs[[id]] <<- unname(v[valeurs$code])
  n <- sum(!is.na(valeurs[[id]]))
  rapport[id] <<- paste0("ok, ", n, " communes renseignées sur ", nrow(valeurs))
  cat("   ", id, ":", rapport[id], "\n")
}
# Lancer un bloc sans que son échec n'arrête tout
essayer <- function(id, bloc) {
  cat("--", id, "\n")
  tryCatch(bloc, error = function(e) {
    rapport[id] <<- paste("ÉCHEC :", conditionMessage(e))
    cat("   ", rapport[id], "\n")
  })
}

# ---- 2. Revenus et pauvreté (Insee, Filosofi) ---------------------
# Le secret statistique masque les petites communes : on leur donne alors la valeur
# de leur intercommunalité, et la carte le signale.
essayer("revenus", {
  filo <- melodi::get_all_data(jeu_revenus)
  filo$GEO <- as.character(filo$GEO)
  filo$OBS_VALUE <- as.numeric(filo$OBS_VALUE)
  filo <- filo[filo$TIME_PERIOD == max(filo$TIME_PERIOD), ]
  for (m in c(pauvrete = "PR_MD60", revenu = "MED_SL")) {
    d <- filo[filo$FILOSOFI_MEASURE == m, ]
    v <- setNames(d$OBS_VALUE[d$GEO_OBJECT %in% c("COM", "ARM")], d$GEO[d$GEO_OBJECT %in% c("COM", "ARM")])
    e <- d[d$GEO_OBJECT == "EPCI", ]
    v <- v[com$code]; names(v) <- com$code
    manque <- is.na(v)
    v[manque] <- e$OBS_VALUE[match(com$epci[manque], e$GEO)]
    id <- names(m)
    impute[[id]] <- which(manque & !is.na(v)) - 1      # indices à partir de 0, pour JavaScript
    ranger(id, v)
  }
})

# ---- 3. Accès aux médecins généralistes (DREES, APL) --------------
essayer("apl", {
  f <- telecharger(ressource_datagouv(jeu_apl, "g[ée]n[ée]ralist", "xls"), "data/brut/apl.xlsx")
  # la feuille la plus récente est en général la dernière qui contient « Code commune »
  for (s in rev(readxl::excel_sheets(f))) { d <- lire_tableau(f, s, entete = "^code commune"); if (!is.null(d)) break }
  cat("   feuille :", s, "\n")
  code <- code_commune(d[[colonne(d, "^code commune")]])
  apl <- nombre(d[[colonne(d, "APL", exclure = "65|moins|code")]])
  ranger("apl", setNames(apl, code))
})

# ---- 4. Fibre optique (Arcep) -------------------------------------
essayer("fibre", {
  f <- telecharger(ressource_datagouv(jeu_fibre, "commun", "csv|xls"), "data/brut/fibre")
  d <- lire_tableau(f, entete = "code")
  code <- code_commune(d[[colonne(d, "code.*(insee|commune)|^insee")]])
  locaux <- nombre(d[[colonne(d, "locaux", exclure = "raccord|[ée]ligib")]])
  racc <- names(d)[grepl("raccordable|ftth", names(d), ignore.case = TRUE)]
  if (!length(racc)) stop("Aucune colonne de locaux raccordables. Colonnes : ", paste(names(d), collapse = " | "))
  fibre <- pmin(100, 100 * nombre(d[[tail(racc, 1)]]) / locaux)     # dernière colonne = trimestre le plus récent
  ranger("fibre", setNames(fibre, code))
})

# ---- 5. Pollution de l'air (Ineris) --------------------------------
essayer("air", {
  f <- telecharger(url_air, "data/brut/air.zip", jours = 3650)
  unzip(f, exdir = "data/brut/air")
  fichiers <- list.files("data/brut/air", "\\.(csv|txt|xlsx?)$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  for (p in c(no2 = "NO2", pm25 = "PM2[._]?5")) {
    essayer(names(p), {
      fp <- fichiers[grepl(p, basename(fichiers), ignore.case = TRUE)]
      if (!length(fp)) stop("Aucun fichier pour ", p, ". Fichiers : ", paste(basename(fichiers), collapse = " | "))
      d <- lire_tableau(fp[1])
      code <- code_commune(d[[colonne(d, "insee|code|com")]])
      # la colonne de l'année la plus récente, sinon la moyenne
      annees <- grep("20[0-9]{2}", names(d), value = TRUE)
      cv <- if (length(annees)) annees[which.max(as.numeric(sub(".*(20[0-9]{2}).*", "\\1", annees)))] else colonne(d, "moy|mean|valeur")
      cat("   fichier :", basename(fp[1]), "| colonne :", cv, "\n")
      ranger(names(p), setNames(nombre(d[[cv]]), code))
    })
  }
})

# ---- 6. Sites Seveso (Géorisques) ---------------------------------
essayer("seveso", {
  f <- telecharger(ressource_datagouv(jeu_icpe, NULL, "csv"), "data/brut/icpe.csv")
  d <- lire_tableau(f)
  s <- d[[colonne(d, "seveso")]]
  d <- d[grepl("haut|bas", s, ignore.case = TRUE) & !grepl("non", s, ignore.case = TRUE), ]
  code <- code_commune(d[[colonne(d, "insee|code.*com|cd_com")]])
  n <- table(factor(code, levels = com$code))
  ranger("seveso", setNames(as.numeric(n), names(n)))
})

# ---- 7. Catastrophes naturelles (base Gaspar) ---------------------
essayer("catnat", {
  f <- telecharger(ressource_datagouv(jeu_catnat, NULL, "csv"), "data/brut/catnat.csv")
  d <- lire_tableau(f)
  code <- code_commune(d[[colonne(d, "insee|code.*com|cod_commune")]])
  id <- tryCatch(d[[colonne(d, "arr[êe]t[ée]|^id|num")]], error = function(e) seq_len(nrow(d)))
  d <- unique(data.frame(code, id))             # on retire les doublons signalés dans la base
  n <- table(factor(d$code, levels = com$code))
  ranger("catnat", setNames(as.numeric(n), names(n)))
})

# ---- 8. Abstention (ministère de l'Intérieur) ---------------------
essayer("abstention", {
  f <- telecharger(ressource_datagouv(jeu_election, "commun", "xls"), "data/brut/election.xlsx", jours = 3650)
  d <- lire_tableau(f)
  dep <- as.character(d[[colonne(d, "code.*d[ée]partement")]])
  dep <- ifelse(grepl("^[0-9]$", dep), paste0("0", dep), dep)
  cm <- sprintf("%03s", as.character(d[[colonne(d, "code.*commune")]]))
  cm <- gsub(" ", "0", cm)
  abst <- 100 * nombre(d[[colonne(d, "^abstentions$")]]) / nombre(d[[colonne(d, "^inscrits$")]])
  ranger("abstention", setNames(abst, paste0(dep, cm)))
})

# ---- Bilan ---------------------------------------------------------
cat("\n==== Bilan des indicateurs ====\n")
for (id in names(rapport)) cat(sprintf("%-11s %s\n", id, rapport[id]))
INDICATEURS <- INDICATEURS[INDICATEURS$id %in% names(valeurs), ]

st_write(cbind(contours, com[, c("nom", "population", "epci", "dep")]), "data/communes.gpkg", delete_dsn = TRUE, quiet = TRUE)
st_write(epci, "data/epci.gpkg", delete_dsn = TRUE, quiet = TRUE)
saveRDS(list(valeurs = valeurs, impute = impute, rapport = rapport, indicateurs = INDICATEURS,
             date = format(Sys.Date())), "data/indicateurs.rds")
