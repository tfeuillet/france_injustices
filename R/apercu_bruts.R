# ------------------------------------------------------------------
# Aperçu des données brutes, pour le vademecum détaillé.
# Pour chaque source, les 15 premières lignes du fichier tel que le producteur le diffuse,
# lues dans data/brut. Rien n'est téléchargé : une source absente est simplement signalée.
# À lancer depuis le dossier du projet :  source("R/apercu_bruts.R")
# Résultat : data/apercu_bruts.json, à m'envoyer.
# ------------------------------------------------------------------
library(jsonlite)

n <- 15
largeur <- 400          # les lignes très longues sont coupées
apercu <- list()

couper <- function(x) ifelse(nchar(x) > largeur, paste0(substr(x, 1, largeur), " […]"), x)

# lignes d'un tableau déjà lu (Excel, rds)
lignes_tableau <- function(d) {
  d <- head(as.data.frame(d), n)
  couper(capture.output(write.table(d, sep = ";", row.names = FALSE, quote = FALSE)))
}
# lignes d'un fichier texte, sans le relire en entier
lignes_texte <- function(f) couper(readLines(f, n = n + 1, warn = FALSE, encoding = "UTF-8"))
# lignes du premier tableau d'une archive zip (ou de celui dont le nom correspond au motif)
lignes_zip <- function(z, motif = "\\.(csv|txt)$") {
  noms <- unzip(z, list = TRUE)$Name
  f <- grep(motif, noms, value = TRUE, ignore.case = TRUE)[1]
  if (is.na(f)) return(paste("Archive sans tableau lisible. Contenu :", paste(head(noms, 10), collapse = ", ")))
  con <- unz(z, f); on.exit(close(con))
  c(paste0("[fichier ", f, "]"), couper(readLines(con, n = n + 1, warn = FALSE, encoding = "UTF-8")))
}

ajouter <- function(id, fichier, lire) {
  cat(id, ":", fichier, "\n")
  apercu[[id]] <<- if (!file.exists(fichier)) list(fichier = fichier, lignes = "fichier absent de data/brut")
    else tryCatch(list(fichier = fichier, lignes = lire(fichier)),
                  error = function(e) list(fichier = fichier, lignes = paste("lecture impossible :", conditionMessage(e))))
}

melodi <- function(f) lignes_tableau(readRDS(f))     # jeux de l'Insee gardés par melodi_cache()

ajouter("revenus (pauvrete, revenu)", "data/brut/DS_FILOSOFI_CC.rds", melodi)
ajouter("edi", "data/brut/edi.csv", lignes_texte)
ajouter("chomage", "data/brut/DS_RP_EMPLOI_LR_PRINC.rds", melodi)
ajouter("apl", "data/brut/apl.xlsx", function(f) {
  s <- readxl::excel_sheets(f)
  c(paste0("[feuilles : ", paste(s, collapse = ", "), "]"), lignes_tableau(readxl::read_excel(f, sheet = s[length(s)], n_max = n + 10, col_names = FALSE)))
})
ajouter("scale", "data/brut/scale_points.rds", function(f) {
  p <- readRDS(f)
  c("[fichier intermédiaire : centre de chaque zone résidentielle, valeur de l'indice (v) et poids (p), lus dans le shapefile de l'archive scale.zip]",
    lignes_tableau(cbind(sf::st_drop_geometry(p), sf::st_coordinates(p))))
})
ajouter("fibre", "data/brut/fibre.zip", function(f) lignes_zip(f, "\\.(csv|txt|dbf)$"))
ajouter("air (no2, pm25)", "data/brut/air_communes.csv", lignes_texte)
ajouter("chaleur", "data/brut/chaleur_2025.rds", function(f)
  c("[fichier intermédiaire : pour chaque point de la grille Safran, jours lus et nuits à au moins 20 °C en 2025 ; le fichier quotidien d'origine est effacé après lecture]",
    lignes_tableau(readRDS(f))))
ajouter("seveso", "data/brut/icpe.gpkg", function(f) lignes_tableau(sf::st_drop_geometry(sf::st_read(f, quiet = TRUE))))
ajouter("catnat", "data/brut/catnat.csv", lignes_texte)
ajouter("inondation (cours d'eau)", "data/brut/ONRN_Population_EAIP_CE.zip", lignes_zip)
ajouter("inondation (submersion marine)", "data/brut/ONRN_Population_EAIP_SM.zip", lignes_zip)
ajouter("abstention", "data/brut/election.xlsx", function(f) lignes_tableau(readxl::read_excel(f, n_max = n)))
ajouter("emploi", c(tail(sort(list.files("data/brut", "^urssaf_.*\\.csv$", full.names = TRUE)), 1), "data/brut/urssaf.csv")[1], lignes_texte)
ajouter("population", "data/brut/DS_POPULATIONS_HISTORIQUES.rds", melodi)
ajouter("icm (population par âge)", "data/brut/DS_RP_POPULATION_PRINC.rds", melodi)
ajouter("icm (décès)", "data/brut/DS_ETAT_CIVIL_DECES_COMMUNES.rds", melodi)
ajouter("revenu_long", "data/brut/piketty", function(d) lignes_texte(list.files(d, "^revcommunes\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)[1]))
ajouter("capital_long", "data/brut/piketty", function(d) lignes_texte(list.files(d, "^capitalimmobiliercommunes\\.csv$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)[1]))
ajouter("eau (pesticides, dépassements, nitrates)", "data/brut/eau_controles_2025.rds", function(f) {
  r <- readRDS(f)
  c("[fichier intermédiaire de 2025 : l'archive du contrôle sanitaire est effacée après lecture. Communes desservies par chaque réseau :]",
    lignes_tableau(r$udi), "[nombre de prélèvements (n) et somme des valeurs (somme), par mesure et par réseau :]", lignes_tableau(r$mesures))
})
ajouter("lycee", "data/brut/annuaire_education.csv", lignes_texte)
ajouter("superieur", "data/brut/parcoursup.csv", lignes_texte)
ajouter("lycee et superieur (population au carreau)", "data/brut/carreaux_1km.zip", lignes_zip)
ajouter("segregation (IPS)", "data/brut/ips_colleges.csv", lignes_texte)
ajouter("segregation (effectifs)", "data/brut/effectifs_colleges.csv", lignes_texte)

write_json(apercu, "data/apercu_bruts.json", auto_unbox = TRUE, pretty = TRUE)
cat("\nÉcrit : data/apercu_bruts.json (", length(apercu), "sources )\n")
