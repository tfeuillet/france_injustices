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
  if (!is.null(motif)) ok <- ok & (grepl(motif, r$title, ignore.case = TRUE) | grepl(motif, r$url, ignore.case = TRUE))
  if (!is.null(format)) ok <- ok & grepl(format, r$format, ignore.case = TRUE)
  if (!any(ok)) stop("Aucune ressource ne correspond dans le jeu « ", meta$title, " ». Ressources disponibles : ",
                     paste0(r$title, " (", r$format, ", ", r$url, ")", collapse = " | "))
  r <- r[ok, ]
  # la plus récente d'abord : d'après le titre s'il contient une date (2026T2…), sinon d'après la mise à jour
  annee <- regmatches(r$title, regexpr("20[0-9]{2}(T[1-4])?", r$title))
  if (length(annee) == nrow(r)) r <- r[order(annee, decreasing = TRUE), ] else r <- r[order(r$last_modified, decreasing = TRUE), ]
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
  # Fichier texte : si `entete` est donné, on saute les lignes de notes qui précèdent les titres
  saut <- 0; sep <- "auto"
  if (!is.null(entete)) {
    lignes <- readLines(fichier, n = 60, warn = FALSE)
    ko <- !validUTF8(lignes); lignes[ko] <- iconv(lignes[ko], "latin1", "UTF-8")
    ligne <- grep(entete, lignes, ignore.case = TRUE)[1]
    if (is.na(ligne)) return(NULL)
    saut <- ligne - 1
    # séparateur : le plus fréquent dans la ligne des titres (les titres contiennent souvent des espaces)
    n <- sapply(c(";", ",", "\t", "|"), function(x) lengths(regmatches(lignes[ligne], gregexpr(x, lignes[ligne], fixed = TRUE))))
    sep <- names(which.max(n))
  }
  # header = TRUE : avec colClasses = "character", fread ne reconnaît plus seul la ligne des titres
  d <- data.table::fread(fichier, data.table = FALSE, encoding = "UTF-8", fill = TRUE, colClasses = "character",
                         header = TRUE, skip = saut, sep = sep)
  en_utf8(d)
}

# Beaucoup de fichiers officiels sont encore encodés en Latin-1 : on convertit en UTF-8
# les noms de colonnes et les textes qui ne sont pas de l'UTF-8 valide
en_utf8 <- function(d) {
  conv <- function(x) { ko <- !is.na(x) & !validUTF8(x); x[ko] <- iconv(x[ko], "latin1", "UTF-8"); x }
  names(d) <- conv(names(d))
  for (v in names(d)) if (is.character(d[[v]])) d[[v]] <- conv(d[[v]])
  d
}

# Lire quelques colonnes d'un ou plusieurs gros fichiers texte de même forme. `motifs` est un
# vecteur nommé : le nom est celui qu'aura la colonne, la valeur le motif de son nom dans le fichier.
lire_colonnes <- function(f, motifs) {
  noms <- names(data.table::fread(f[1], nrows = 0))
  garder <- sapply(motifs, function(m) grep(m, noms, ignore.case = TRUE, value = TRUE)[1])
  if (anyNA(garder)) stop("Colonne « ", motifs[is.na(garder)][1], " » absente de ", basename(f[1]), ". Colonnes : ", paste(noms, collapse = " | "))
  d <- do.call(rbind, lapply(f, data.table::fread, select = unname(garder), colClasses = "character", data.table = FALSE))
  setNames(d[unname(garder)], names(motifs))
}

# Décompresser un fichier .gz sans paquet supplémentaire
degonfler <- function(gz, sortie) {
  entree <- gzfile(gz, "rb"); on.exit(close(entree))
  out <- file(sortie, "wb"); on.exit(close(out), add = TRUE)
  while (length(b <- readBin(entree, "raw", 1e7))) writeBin(b, out)
  sortie
}

# Nombre à partir d'un texte (virgule décimale, espaces, %)
nombre <- function(x) suppressWarnings(as.numeric(gsub(",", ".", gsub("[ %  ]", "", as.character(x)))))

# Code commune Insee sur cinq caractères (le zéro initial disparaît souvent dans Excel)
code_commune <- function(x) {
  x <- trimws(as.character(x))
  ifelse(grepl("^[0-9]{4}$", x), paste0("0", x), x)
}

# Arrondissements de Paris, Lyon et Marseille rattachés à leur commune (pour faire des sommes)
code_plm <- function(x) {
  x[grepl("^751(0[1-9]|1[0-9]|20)$", x)] <- "75056"
  x[grepl("^6938[1-9]$", x)] <- "69123"
  x[grepl("^132(0[1-9]|1[0-6])$", x)] <- "13055"
  x
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

# Jeu de données du catalogue Melodi de l'Insee, gardé 25 jours dans data/brut
# (le téléchargement complet est long : inutile de le refaire à chaque passage)
melodi_cache <- function(jeu, jours = 25) {
  f <- file.path("data/brut", paste0(jeu, ".rds"))
  if (file.exists(f) && difftime(Sys.time(), file.mtime(f), units = "days") < jours) return(readRDS(f))
  d <- as.data.frame(melodi::get_all_data(jeu))
  saveRDS(d, f)
  d
}

# Dans un jeu Melodi, garder les totaux (_T) de toutes les dimensions sauf celles indiquées
# (par exemple l'âge, qu'on veut détailler)
totaux <- function(d, sauf = NULL) {
  fixes <- c("GEO", "GEO_OBJECT", "TIME_PERIOD", "OBS_VALUE", sauf)
  for (v in setdiff(names(d), fixes)) {
    if (grepl("LABEL|STATUS|FLAG|UNIT", v)) next
    x <- as.character(d[[v]])
    if ("_T" %in% x) d <- d[x == "_T", ]
  }
  d
}

# Rang de population (entre 0 et 1) : part de la population qui vit dans une commune
# où la valeur est plus faible, plus la moitié de celle de la commune elle-même
rang_pop <- function(v, p) {
  r <- rep(NA_real_, length(v))
  ok <- which(!is.na(v) & !is.na(p))
  o <- ok[order(v[ok])]
  cum <- cumsum(p[o])
  r[o] <- (cum - p[o] / 2) / sum(p[o])
  r
}

# Âge en classes : bornes [min, max) lues dans un code Insee ou Eurostat
# (Y_LT15, Y15T29, Y_GE75, Y42, Y_OPEN...). NA pour les totaux et les âges inconnus.
bornes_age <- function(code) {
  t(sapply(code, function(x) {
    if (grepl("^Y_LT([0-9]+)$", x)) return(c(0, as.numeric(sub("^Y_LT", "", x))))
    if (grepl("^Y_GE([0-9]+)$", x)) return(c(as.numeric(sub("^Y_GE", "", x)), Inf))
    if (grepl("^Y([0-9]+)T([0-9]+)$", x)) { a <- as.numeric(strsplit(sub("^Y", "", x), "T")[[1]]); return(c(a[1], a[2] + 1)) }
    if (grepl("^Y([0-9]+)$", x)) { a <- as.numeric(sub("^Y", "", x)); return(c(a, a + 1)) }
    if (x == "Y_OPEN") return(c(100, Inf))
    c(NA, NA)
  }))
}

# Parmi des classes d'âge qui se recouvrent (le recensement publie plusieurs découpages),
# choisir le découpage le plus fin qui couvre tous les âges sans recouvrement
decoupage_age <- function(codes) {
  b <- bornes_age(codes)
  ok <- !is.na(b[, 1]); codes <- codes[ok]; b <- b[ok, , drop = FALSE]
  meilleur <- list()   # depuis l'âge a : liste des codes du meilleur découpage jusqu'à Inf
  departs <- sort(unique(b[, 1]), decreasing = TRUE)
  for (a in departs) {
    for (k in which(b[, 1] == a)) {
      suite <- if (is.infinite(b[k, 2])) character(0) else meilleur[[as.character(b[k, 2])]]
      if (is.infinite(b[k, 2]) || !is.null(suite)) {
        cand <- c(codes[k], suite)
        if (is.null(meilleur[[as.character(a)]]) || length(cand) > length(meilleur[[as.character(a)]])) meilleur[[as.character(a)]] <- cand
      }
    }
  }
  meilleur[["0"]]
}