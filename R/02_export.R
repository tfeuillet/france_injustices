# ------------------------------------------------------------------
# 2. Export pour la carte interactive (dossier docs/data)
#
#    Les indicateurs sous licence restreinte (IFT d'Adonis, Solagro) ne vont jamais dans docs/,
#    qui est publié. S'il y en a, une copie complète de la carte est écrite dans prive/, que
#    git ignore, pour un usage interne : servr::httd("prive")
# ------------------------------------------------------------------
library(sf)
library(jsonlite)
indicateurs_prives <- c("ift")
dir.create("docs/data", recursive = TRUE, showWarnings = FALSE)

com <- st_read("data/communes.gpkg", quiet = TRUE)
epci <- st_read("data/epci.gpkg", quiet = TRUE)
x <- readRDS("data/indicateurs.rds")

# Contours allégés : la carte doit rester fluide avec 35 000 communes
alleger <- function(g, garder) {
  g <- st_make_valid(g)
  g <- rmapshaper::ms_simplify(g, keep = garder, keep_shapes = TRUE)
  st_transform(g, 4326)
}
# bassins de vie et zones d'emploi, s'ils ont pu être lus (voir 01_donnees.R)
zonages <- x$zonages[intersect(names(x$zonages), names(com))]
com_l <- alleger(com[c("code", "dep", names(zonages))], 0.12)
epci_l <- alleger(epci["code"], 0.2)
# contours des départements, tracés par-dessus les communes : ils guident l'œil sans hacher la carte
dep_l <- rmapshaper::ms_dissolve(com_l, "dep")
com_l$i <- seq_len(nrow(com_l)) - 1          # rang de la commune dans donnees.json
ecrire <- function(g, fichier) st_write(g, fichier, delete_dsn = TRUE, quiet = TRUE,
                                        layer_options = c("COORDINATE_PRECISION=4", "RFC7946=YES"))
ecrire(com_l["i"], "docs/data/communes.geojson")
ecrire(epci_l["code"], "docs/data/epci.geojson")
ecrire(rmapshaper::ms_innerlines(dep_l), "docs/data/departements.geojson")
# contours des bassins de vie et des zones d'emploi : réunion des communes allégées, qui se raccordent sans trou
for (n in names(zonages)) {
  z <- rmapshaper::ms_dissolve(com_l[!is.na(com_l[[n]]), ], n)
  names(z)[names(z) == n] <- "code"
  ecrire(z["code"], paste0("docs/data/", n, ".geojson"))
}

# Un point dans chaque commune : en degrés pour la carte, en kilomètres (Lambert 93) pour
# les calculs de distance des corrélations locales
pts <- st_point_on_surface(st_transform(st_geometry(com), 2154))
l93 <- st_coordinates(pts) / 1000
centre <- st_coordinates(st_transform(pts, 4326))
arrondir <- function(v, d) ifelse(is.na(v), NA, round(v, d + 1))
ind <- x$indicateurs
liste <- lapply(seq_len(nrow(ind)), function(k) {
  id <- ind$id[k]
  r <- c(as.list(ind[k, ]), list(valeurs = arrondir(x$valeurs[[id]], ind$decimales[k]),
                                 impute = if (is.null(x$impute[[id]])) integer(0) else x$impute[[id]]))
  # valeurs calculées directement pour un niveau (ségrégation entre collèges, par exemple), dans
  # l'ordre des codes de ce niveau : la page les prend au lieu de faire la moyenne des communes
  p <- x$par_niveau[[id]]
  if (length(p)) r$niveaux <- lapply(setNames(names(p), names(p)), function(n) {
    codes <- if (n == "epci") epci$code else zonages[[n]]$code
    arrondir(as.numeric(p[[n]][codes]), ind$decimales[k])
  })
  r
})

donnees <- function(garder) list(
  date = x$date,
  communes = c(list(code = com$code, nom = com$nom, pop = com$population, epci = com$epci, dep = com$dep,
                    lon = round(centre[, 1], 4), lat = round(centre[, 2], 4),
                    x = round(l93[, 1], 2), y = round(l93[, 2], 2)),
               lapply(setNames(names(zonages), names(zonages)), function(n) com[[n]])),
  epci = list(code = epci$code, nom = epci$nom),
  zonages = lapply(zonages, function(z) list(code = z$code, nom = z$nom)),
  indicateurs = liste[ind$id %in% garder],
  rapport = as.list(x$rapport[names(x$rapport) %in% c(garder, setdiff(names(x$rapport), ind$id))])
)
publics <- setdiff(ind$id, indicateurs_prives)
write_json(donnees(publics), "docs/data/donnees.json", auto_unbox = TRUE, na = "null", digits = NA)
cat("Fichiers écrits dans docs/data :\n")
print(file.info(list.files("docs/data", full.names = TRUE))[, "size", drop = FALSE])

# Copie privée, avec tous les indicateurs : la page et ses scripts sont recopiés de docs/
if (any(ind$id %in% indicateurs_prives)) {
  dir.create("prive/data", recursive = TRUE, showWarnings = FALSE)
  file.copy(list.files("docs", "\\.(html|js|css)$", full.names = TRUE), "prive", overwrite = TRUE)
  file.copy(list.files("docs/data", "\\.geojson$", full.names = TRUE), "prive/data", overwrite = TRUE)
  write_json(donnees(ind$id), "prive/data/donnees.json", auto_unbox = TRUE, na = "null", digits = NA)
  if (!file.exists("prive/solagro.png")) message("Logo de Solagro absent : le déposer sous le nom prive/solagro.png (il est exigé sur les cartes qui utilisent Adonis)")
  cat("Copie privée, avec", paste(intersect(ind$id, indicateurs_prives), collapse = ", "), ": dossier prive/ (servr::httd(\"prive\"))\n")
}