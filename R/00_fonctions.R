# ------------------------------------------------------------------
# Fonctions communes
# ------------------------------------------------------------------

# Télécharger un fichier, sans le retélécharger s'il a moins de `jours` jours.
# En cas d'échec, on réessaie trois fois ; si le serveur ne répond toujours pas,
# on garde la copie déjà téléchargée, s'il y en a une.
telecharger <- function(url, fichier, jours = 25, essais = 3) {
  if (file.exists(fichier) && difftime(Sys.time(), file.mtime(fichier), units = "days") < jours) return(fichier)
  temporaire <- paste0(fichier, ".tmp")
  for (k in seq_len(essais)) {
    ok <- tryCatch({ download.file(url, temporaire, mode = "wb", quiet = TRUE); TRUE },
                   error = function(e) FALSE, warning = function(w) FALSE)
    if (ok && file.size(temporaire) > 0) { file.rename(temporaire, fichier); return(fichier) }
    message("Téléchargement impossible (essai ", k, " sur ", essais, ") : ", url)
    Sys.sleep(10 * k)
  }
  unlink(temporaire)
  if (file.exists(fichier)) {
    warning("Serveur injoignable, on garde la copie du ", format(file.mtime(fichier), "%d/%m/%Y"), " : ", fichier)
    return(fichier)
  }
  stop("Serveur injoignable et aucune copie locale : ", url)
}

# Adresse de la ressource la plus récente d'un jeu de données de data.gouv.fr.
# On passe par l'API du portail : l'adresse suit donc les mises à jour du producteur.
# `motif` filtre sur le titre (ou l'adresse) de la ressource, `format` sur son format.
ressource_datagouv <- function(jeu, motif = NULL, format = NULL) {
  meta <- fromJSON(paste0("https://www.data.gouv.fr/api/1/datasets/", jeu, "/"))
  r <- meta$resources
  ok <- rep(TRUE, nrow(r))
  if (!is.null(motif)) ok <- ok & grepl(motif, paste(r$title, r$url), ignore.case = TRUE)
  if (!is.null(format)) ok <- ok & grepl(format, r$format, ignore.case = TRUE)
  if (!any(ok)) stop("Aucune ressource ne correspond dans le jeu « ", meta$title, " ». Ressources disponibles : ",
                     paste0(r$title, " (", r$format, ")", collapse = " | "))
  r <- r[ok, ]
  r <- r[order(r$last_modified, decreasing = TRUE), ]
  cat("   ressource retenue :", r$title[1], "\n")
  r$url[1]
}

# Trouver une colonne d'après son nom. En cas d'échec, l'erreur affiche les colonnes
# disponibles : il suffit alors d'adapter le motif.
colonne <- function(d, motif, exclure = NULL) {
  n <- names(d)
  ok <- grepl(motif, n, ignore.case = TRUE)
  if (!is.null(exclure)) ok <- ok & !grepl(exclure, n, ignore.case = TRUE)
  if (!any(ok)) stop("Aucune colonne ne correspond à « ", motif, " ». Colonnes : ", paste(n, collapse = " | "))
  n[which(ok)[1]]
}

# Lire un tableau csv, txt ou Excel, quel que soit son séparateur ou son encodage.
# Pour Excel, `entete` est un motif qui repère la ligne des titres (les fichiers
# officiels commencent souvent par plusieurs lignes de notes).
lire_tableau <- function(fichier, feuille = 1, entete = NULL) {
  debut <- readBin(fichier, "raw", 4)
  if (identical(debut[1:2], as.raw(c(0x50, 0x4b))) || grepl("\\.xlsx?$", fichier)) {
    if (is.null(entete)) return(as.data.frame(readxl::read_excel(fichier, feuille)))
    brut <- readxl::read_excel(fichier, feuille, col_names = FALSE, n_max = 60)
    ligne <- which(apply(brut, 1, function(x) any(grepl(entete, x, ignore.case = TRUE))))[1]
    if (is.na(ligne)) return(NULL)
    return(as.data.frame(readxl::read_excel(fichier, feuille, skip = ligne - 1)))
  }
  data.table::fread(fichier, data.table = FALSE, encoding = "UTF-8", fill = TRUE, colClasses = "character")
}

# Nombre à partir d'un texte (virgule décimale, espaces, %)
nombre <- function(x) suppressWarnings(as.numeric(gsub(",", ".", gsub("[ %  ]", "", as.character(x)))))

# Code commune Insee sur cinq caractères (le zéro initial disparaît souvent dans Excel)
code_commune <- function(x) {
  x <- trimws(as.character(x))
  ifelse(grepl("^[0-9]{4}$", x), paste0("0", x), x)
}

# Paris, Lyon et Marseille : si la commune entière manque mais que ses arrondissements
# sont présents, on prend la moyenne des arrondissements pondérée par `poids` (ou simple).
completer_plm <- function(v, poids = NULL) {
  arr <- list("75056" = sprintf("751%02d", 1:20), "69123" = sprintf("6938%d", 1:9), "13055" = sprintf("132%02d", 1:16))
  for (c in names(arr)) if (is.na(v[c]) || !c %in% names(v)) {
    a <- v[intersect(arr[[c]], names(v))]
    a <- a[!is.na(a)]
    if (length(a)) v[c] <- if (is.null(poids)) mean(a) else weighted.mean(a, poids[names(a)])
  }
  v
}
