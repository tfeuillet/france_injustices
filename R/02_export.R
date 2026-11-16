# ------------------------------------------------------------------
# 2. Export pour la carte interactive (dossier docs/data)
# ------------------------------------------------------------------
library(sf)
library(jsonlite)
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
com_l <- alleger(com["code"], 0.12)
epci_l <- alleger(epci["code"], 0.2)
com_l$i <- seq_len(nrow(com_l)) - 1          # rang de la commune dans donnees.json
ecrire <- function(g, fichier) st_write(g, fichier, delete_dsn = TRUE, quiet = TRUE,
                                        layer_options = c("COORDINATE_PRECISION=4", "RFC7946=YES"))
ecrire(com_l["i"], "docs/data/communes.geojson")
ecrire(epci_l["code"], "docs/data/epci.geojson")

centre <- st_coordinates(st_point_on_surface(st_transform(st_geometry(com), 4326)))
arrondir <- function(v, d) ifelse(is.na(v), NA, round(v, d + 1))
ind <- x$indicateurs
liste <- lapply(seq_len(nrow(ind)), function(k) {
  id <- ind$id[k]
  c(as.list(ind[k, ]), list(valeurs = arrondir(x$valeurs[[id]], ind$decimales[k]),
                            impute = if (is.null(x$impute[[id]])) integer(0) else x$impute[[id]]))
})

write_json(list(
  date = x$date,
  communes = list(code = com$code, nom = com$nom, pop = com$population, epci = com$epci, dep = com$dep,
                  lon = round(centre[, 1], 4), lat = round(centre[, 2], 4)),
  epci = list(code = epci$code, nom = epci$nom),
  indicateurs = liste,
  rapport = as.list(x$rapport)
), "docs/data/donnees.json", auto_unbox = TRUE, na = "null", digits = NA)

cat("Fichiers écrits dans docs/data :\n")
print(file.info(list.files("docs/data", full.names = TRUE))[, "size", drop = FALSE])
