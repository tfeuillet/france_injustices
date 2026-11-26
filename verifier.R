# ------------------------------------------------------------------
# Vérification des indicateurs, à lancer après 01_donnees.R
#   Sorties : data/verification.csv (un tableau de contrôle par indicateur)
#             data/verification.pdf (pour chaque indicateur, une carte et un histogramme)
#   La console affiche aussi les valeurs de quelques villes repères et les liens attendus
#   entre indicateurs. Rien n'est modifié dans les données.
# ------------------------------------------------------------------
library(sf)
source("R/00_fonctions.R")

x <- readRDS("data/indicateurs.rds")
communes <- st_read("data/communes.gpkg", quiet = TRUE)
v <- x$valeurs
communes <- communes[match(v$code, communes$code), ]
pop <- communes$population
ind <- x$indicateurs

# ---- 1. Tableau de contrôle --------------------------------------
# Bornes plausibles de chaque indicateur : une valeur en dehors mérite d'être regardée
bornes <- list(edi = c(-10, 20), pauvrete = c(0, 60), chomage = c(0, 60), revenu = c(10000, 70000),
               apl = c(0, 10), scale = c(-50, 200), fibre = c(0, 100), superieur = c(0, 80), lycee = c(0, 60),
               segregation = c(0, 40), no2 = c(1, 60), pm25 = c(1, 25), seveso = c(0, 30), catnat = c(0, 200),
               chaleur = c(0, 80), ift = c(0, 30), eau_pesticides = c(0, 5), eau_depassements = c(0, 100), eau_nitrates = c(0, 100), inondation = c(0, 100),
               abstention = c(0, 80), icm = c(30, 300), emploi = c(-90, 500), population = c(-70, 300),
               revenu_long = c(-100, 100), capital_long = c(-100, 100))

# quantile pondéré par la population
qp <- function(x, p, q) { ok <- !is.na(x) & !is.na(p); o <- order(x[ok]); c <- cumsum(p[ok][o]) / sum(p[ok]); sapply(q, function(k) x[ok][o][which(c >= k)[1]]) }

tableau <- do.call(rbind, lapply(ind$id, function(id) {
  x_ <- v[[id]]; ok <- !is.na(x_)
  if (!any(ok)) return(NULL)
  imp <- length(x$impute[[id]])
  q <- qp(x_, pop, c(0.1, 0.5, 0.9))
  frequente <- names(which.max(table(round(x_[ok], 6))))
  b <- bornes[[id]]
  data.frame(id = id, nom = ind$nom[ind$id == id], unite = ind$unite[ind$id == id],
             communes = sum(ok), part_communes = round(100 * mean(ok), 1),
             part_population = round(100 * sum(pop[ok]) / sum(pop), 1),
             completees = imp, part_completees = round(100 * imp / max(1, sum(ok)), 1),
             min = signif(min(x_, na.rm = TRUE), 4), p10 = signif(q[1], 4), mediane = signif(q[2], 4),
             p90 = signif(q[3], 4), max = signif(max(x_, na.rm = TRUE), 4),
             moyenne_ponderee = signif(sum(x_[ok] * pop[ok]) / sum(pop[ok]), 4),
             valeur_frequente = frequente,
             part_pop_valeur_frequente = round(100 * sum(pop[ok][round(x_[ok], 6) == as.numeric(frequente)]) / sum(pop[ok]), 1),
             hors_bornes = if (is.null(b)) NA else sum(x_[ok] < b[1] | x_[ok] > b[2]),
             rapport = sub("\\s*\\(repris.*", "", x$rapport[id]), source = ind$source[ind$id == id])
}))
write.csv(tableau, "data/verification.csv", row.names = FALSE, fileEncoding = "UTF-8")
cat("\n==== Tableau de contrôle (détail dans data/verification.csv) ====\n")
print(tableau[, c("id", "part_population", "part_completees", "p10", "mediane", "p90", "max", "part_pop_valeur_frequente", "hors_bornes")], row.names = FALSE)
cat("\nÀ regarder : une couverture faible, beaucoup de valeurs complétées, une valeur fréquente qui réunit\n",
    "une grande part de la population (ex æquo), des valeurs hors bornes, une médiane surprenante.\n")

# ---- 2. Villes repères --------------------------------------------
# Comparer ces valeurs à celles publiées ailleurs (Insee, comparateur de territoires ; résultats
# des élections ; qualité de l'eau sur le site du ministère de la Santé…). Le nom affiché sert à
# vérifier que le code correspond bien à la commune voulue.
reperes <- c("75101", "75119", "13203", "69381", "31555", "33063", "44109", "35238", "59350", "59512", "59172",
             "67482", "06088", "34172", "38185", "76540", "14118", "35196", "93066", "91286", "69256",
             "92051", "78646", "23096")
k <- match(reperes, v$code); k <- k[!is.na(k)]
villes <- round(t(as.matrix(v[k, ind$id])), 2)
colnames(villes) <- communes$nom[k]
cat("\n==== Villes repères ====\n")
print(villes)

# ---- 3. Liens attendus entre indicateurs ---------------------------
# Corrélation des rangs, pondérée par la population. Un signe contraire à celui attendu signale
# presque toujours une erreur (sens inversé, mauvaise colonne, unité).
correl <- function(a, b) {
  ok <- !is.na(v[[a]]) & !is.na(v[[b]]) & !is.na(pop)
  ra <- rang_pop(v[[a]][ok], pop[ok]); rb <- rang_pop(v[[b]][ok], pop[ok]); w <- pop[ok] / sum(pop[ok])
  ma <- sum(w * ra); mb <- sum(w * rb)
  sum(w * (ra - ma) * (rb - mb)) / sqrt(sum(w * (ra - ma)^2) * sum(w * (rb - mb)^2))
}
# (la fibre n'y figure pas : les réseaux publics ont souvent raccordé les campagnes avant les grandes villes)
attendus <- data.frame(a = c("pauvrete", "edi", "chomage", "edi", "no2", "lycee", "apl", "icm", "abstention", "population"),
                       b = c("revenu", "pauvrete", "pauvrete", "revenu", "pm25", "superieur", "scale", "edi", "edi", "emploi"),
                       signe = c(-1, 1, 1, -1, 1, 1, -1, 1, 1, 1))
attendus <- attendus[attendus$a %in% names(v) & attendus$b %in% names(v), ]
attendus$r <- round(mapply(correl, attendus$a, attendus$b), 2)
attendus$verdict <- ifelse(sign(attendus$r) == attendus$signe, "ok", "À VÉRIFIER")
cat("\n==== Liens attendus (corrélation des rangs) ====\n")
print(attendus, row.names = FALSE)

# ---- 4. Cartes et histogrammes ---------------------------------------
# Une page par indicateur. Sur la carte, une rupture nette le long d'une limite de département ou de
# région trahit souvent une différence de source ou de méthode (contrôles de l'eau par les ARS, par
# exemple), plutôt qu'une réalité.
couleurs <- c("#006837", "#1a9850", "#66bd63", "#a6d96a", "#d9ef8b", "#fee08b", "#fdae61", "#f46d43", "#d73027", "#a50026")
geom <- st_geometry(communes)
# cairo_pdf sait écrire le symbole € et les autres caractères spéciaux
(if (capabilities("cairo")) cairo_pdf else pdf)("data/verification.pdf", width = 11.7, height = 8.3, onefile = TRUE)
for (id in ind$id) {
  x_ <- v[[id]]; sens <- ind$sens[ind$id == id]
  r <- rang_pop(sens * x_, pop)
  layout(matrix(1:2, 1), widths = c(2, 1))
  par(mar = c(0, 0, 3, 0))
  plot(geom, col = ifelse(is.na(r), "grey85", couleurs[pmin(10, floor(10 * r) + 1)]), border = NA,
       main = paste0(ind$nom[ind$id == id], "\n(rouge = défavorable, gris = manquant)"))
  par(mar = c(5, 4, 4, 1))
  hist(x_, breaks = 80, col = "grey70", border = NA, main = "Distribution (communes)", xlab = ind$unite[ind$id == id], ylab = "communes")
  abline(v = qp(x_, pop, 0.5), col = "#a50026", lwd = 2)
  mtext("trait rouge : médiane de la population", side = 3, cex = 0.8)
}
dev.off()
cat("\nCartes et histogrammes : data/verification.pdf\n")