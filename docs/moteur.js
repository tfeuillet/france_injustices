// ------------------------------------------------------------------
// Calculs de la carte des injustices territoriales.
// Tout est fait dans le navigateur, à partir de docs/data/donnees.json.
// ------------------------------------------------------------------

// Dimensions de l'injustice. Chaque dimension cochée pèse autant dans le score, quel que soit
// le nombre de ses indicateurs : trois mesures du même phénomène ne comptent pas trois fois.
const DIMENSIONS = [
  { id: "niveau_vie", nom: "Niveau de vie" },
  { id: "soins", nom: "Accès aux soins" },
  { id: "numerique", nom: "Accès au numérique" },
  { id: "environnement", nom: "Environnement et risques" },
  { id: "pesticides", nom: "Pesticides et eau" },
  { id: "voix", nom: "Participation politique" },
  { id: "sante", nom: "Santé" },
  { id: "trajectoires", nom: "Trajectoires récentes (dix ans)" },
  { id: "temps_long", nom: "Trajectoires longues" }
];
// Pour un fichier de données plus ancien, sans les colonnes dimension, cumul et defaut
const ANCIEN = {
  pauvrete: ["niveau_vie", 0, 0], revenu: ["niveau_vie", 0, 0], edi: ["niveau_vie", 1, 1], apl: ["soins", 1, 1], scale: ["soins", 1, 1],
  fibre: ["numerique", 1, 1], no2: ["environnement", 1, 1], pm25: ["environnement", 1, 1], seveso: ["environnement", 1, 1],
  catnat: ["environnement", 1, 1], abstention: ["voix", 1, 1], icm: ["sante", 1, 0], emploi: ["trajectoires", 1, 0],
  population: ["trajectoires", 1, 0], revenu_long: ["temps_long", 1, 0], capital_long: ["temps_long", 1, 0],
  ift: ["pesticides", 1, 1], eau_pesticides: ["pesticides", 1, 1], eau_nitrates: ["pesticides", 1, 0],
  chomage: ["niveau_vie", 1, 1], chaleur: ["environnement", 1, 1], prematuree: ["sante", 1, 0]
};
// Nom de chaque indicateur avec son article, pour les phrases écrites automatiquement
const ARTICLES = {
  edi: "la défavorisation sociale (EDI)", pauvrete: "le taux de pauvreté", revenu: "le niveau de vie médian",
  chomage: "le taux de chômage", apl: "l'accès aux médecins généralistes", scale: "l'éloignement des soins de premier recours (SCALe)",
  fibre: "la part des locaux raccordables à la fibre", no2: "la pollution au dioxyde d'azote", pm25: "la pollution aux particules fines",
  seveso: "les sites industriels Seveso", catnat: "les catastrophes naturelles reconnues", chaleur: "les nuits chaudes",
  ift: "l'usage agricole de pesticides (IFT)", eau_pesticides: "les pesticides dans l'eau du robinet", eau_nitrates: "les nitrates dans l'eau du robinet",
  abstention: "l'abstention", icm: "la surmortalité", prematuree: "la mortalité prématurée", emploi: "l'évolution de l'emploi salarié privé",
  population: "l'évolution de la population", revenu_long: "l'évolution du rang de revenu", capital_long: "l'évolution du rang de capital immobilier"
};
// Indicateurs supplémentaires : plus fragiles ou en partie redondants, rangés à part (repliés)
const SUPPLEMENTAIRES = new Set(["pauvrete", "revenu", "eau_nitrates", "chaleur", "revenu_long", "capital_long", "seveso", "abstention"]);
// Sélection proposée : un indicateur par dimension, le premier de cette liste présent dans la dimension
const PROPOSES = ["edi", "scale", "fibre", "pm25", "eau_pesticides", "icm", "emploi"];
function normaliser(D) {
  for (const ind of D.indicateurs) {
    const a = ANCIEN[ind.id] || ["niveau_vie", 1, 0];
    if (!ind.dimension) ind.dimension = a[0];
    if (ind.cumul === undefined) ind.cumul = a[1];
    if (ind.defaut === undefined) ind.defaut = a[2];
    ind.cumul = +ind.cumul; ind.defaut = +ind.defaut;
    // période des évolutions, lue dans l'unité (« points de centile entre 1965 et 2022 ») et ajoutée au nom
    const per = /entre (\d{4}) et (\d{4})/.exec(ind.unite || "");
    if (per && !ind.nom.includes(per[1])) ind.nom = ind.nom.replace(/ sur le long terme$/, "") + ` (${per[1]}-${per[2]})`;
    ind.supplementaire = SUPPLEMENTAIRES.has(ind.id);
  }
  for (const d of DIMENSIONS) {
    const liste = D.indicateurs.filter(ind => ind.dimension === d.id && ind.cumul && !ind.supplementaire);
    const choisi = PROPOSES.find(id => liste.some(ind => ind.id === id)) || (liste[0] && liste[0].id);
    for (const ind of D.indicateurs.filter(ind => ind.dimension === d.id)) ind.defaut = ind.id === choisi ? 1 : 0;
  }
  return D;
}
const PART_MINIMALE = 0.5;   // part des dimensions cochées qui doit être renseignée pour qu'un score soit calculé
const TRANCHE = 0.2;         // les 20 % les plus modestes et les 20 % les plus aisés
const REDONDANCE = 0.7;      // corrélation au-delà de laquelle deux indicateurs cochés sont signalés

// Unités de la carte : les communes, ou les intercommunalités (moyennes pondérées par la population)
function unites(D, echelle) {
  const C = D.communes, n = C.code.length;
  // coordonnées en kilomètres (Lambert 93), pour les distances des corrélations locales.
  // Si le fichier de données est ancien, on les déduit de la longitude et de la latitude.
  const cx = C.x || C.lon.map(v => v * 111.32 * Math.cos(46.5 * Math.PI / 180));
  const cy = C.y || C.lat.map(v => v * 110.57);
  if (echelle !== "epci") {
    return { echelle, n, code: C.code, nom: C.nom, pop: C.pop, cx, cy,
      valeurs: Object.fromEntries(D.indicateurs.map(ind => [ind.id, ind.valeurs.map(v => v === null ? NaN : v)])),
      impute: Object.fromEntries(D.indicateurs.map(ind => [ind.id, new Set(ind.impute)])) };
  }
  const rang = new Map(D.epci.code.map((c, k) => [c, k])), m = D.epci.code.length;
  const pop = new Array(m).fill(0), membre = new Int32Array(n).fill(-1);
  const sx = new Float64Array(m), sy = new Float64Array(m), sw = new Float64Array(m);
  for (let i = 0; i < n; i++) {
    const k = rang.get(C.epci[i]);
    if (k === undefined) continue;
    membre[i] = k; pop[k] += C.pop[i];
    const p = C.pop[i] || 0.001; sx[k] += p * cx[i]; sy[k] += p * cy[i]; sw[k] += p;   // centre de gravité de la population
  }
  const valeurs = {};
  for (const ind of D.indicateurs) {
    const s = new Float64Array(m), w = new Float64Array(m);
    ind.valeurs.forEach((v, i) => { const k = membre[i]; if (k < 0 || v === null) return; const p = C.pop[i] || 0.001; s[k] += p * v; w[k] += p; });
    valeurs[ind.id] = Array.from(s, (x, k) => w[k] > 0 ? x / w[k] : NaN);
  }
  return { echelle, n: m, code: D.epci.code, nom: D.epci.nom, pop, valeurs, impute: {},
    cx: Array.from(sx, (v, k) => sw[k] > 0 ? v / sw[k] : NaN), cy: Array.from(sy, (v, k) => sw[k] > 0 ? v / sw[k] : NaN) };
}

// Rang de chaque unité, entre 0 et 1 : part de la population qui vit dans une unité mieux lotie,
// plus la moitié de celle qui vit dans une unité à égalité. 0,8 veut dire « plus défavorisée
// que 80 % de la population ». Les valeurs manquantes restent manquantes (NaN).
function rangs(valeurs, pop, sens) {
  const idx = [];
  valeurs.forEach((v, i) => { if (!Number.isNaN(v)) idx.push(i); });
  idx.sort((a, b) => sens * (valeurs[a] - valeurs[b]));
  const total = idx.reduce((s, i) => s + pop[i], 0) || 1, r = new Float64Array(valeurs.length).fill(NaN);
  let avant = 0;
  for (let a = 0; a < idx.length;) {
    let b = a, groupe = 0;
    while (b < idx.length && valeurs[idx[b]] === valeurs[idx[a]]) groupe += pop[idx[b++]];
    for (let k = a; k < b; k++) r[idx[k]] = (avant + groupe / 2) / total;
    avant += groupe; a = b;
  }
  return r;
}

// Score cumulé, en trois temps :
// 1. chaque indicateur est converti en rang de population (0 = le plus favorable, 1 = le plus défavorable) ;
// 2. le score d'une dimension est la moyenne des rangs de ses indicateurs cochés ;
// 3. le score cumulé est la moyenne des dimensions, puis il est lui-même converti en rang de
//    population, pour que chaque couleur de la carte réunisse bien 10 % des habitants.
// Le comptage dit dans combien de dimensions le territoire fait partie des `seuil` (20 %) de la
// population la plus défavorisée.
function calculer(D, U, coches, seuil = 0.2) {
  const R = {};
  for (const ind of D.indicateurs) R[ind.id] = rangs(U.valeurs[ind.id], U.pop, ind.sens);
  const actifs = D.indicateurs.filter(ind => ind.cumul && coches.has(ind.id));
  const dims = DIMENSIONS.filter(d => actifs.some(ind => ind.dimension === d.id));
  const parDim = {}, rangDim = {};
  for (const d of dims) {
    const liste = actifs.filter(ind => ind.dimension === d.id), v = new Float64Array(U.n).fill(NaN);
    for (let i = 0; i < U.n; i++) {
      let s = 0, k = 0;
      for (const ind of liste) { const r = R[ind.id][i]; if (!Number.isNaN(r)) { s += r; k++; } }
      if (k) v[i] = s / k;
    }
    parDim[d.id] = v;
    rangDim[d.id] = rangs(Array.from(v), U.pop, 1);
  }
  const brut = new Float64Array(U.n).fill(NaN), compte = new Float64Array(U.n).fill(NaN);
  for (let i = 0; i < U.n; i++) {
    let s = 0, k = 0, c = 0;
    for (const d of dims) { const v = parDim[d.id][i]; if (!Number.isNaN(v)) { s += v; k++; if (rangDim[d.id][i] >= 1 - seuil) c++; } }
    if (dims.length && k >= PART_MINIMALE * dims.length) { brut[i] = s / k; compte[i] = c; }
  }
  const score = rangs(Array.from(brut), U.pop, 1);
  return { rangs: R, score, brut, compte, dims, parDim, rangDim, actifs, seuil };
}

// Corrélations entre les indicateurs cochés (sur leurs rangs, pondérées par la population).
// Renvoie les paires dont la corrélation dépasse REDONDANCE.
function redondances(res, U) {
  const ids = res.actifs.map(ind => ind.id), paires = [];
  for (let a = 0; a < ids.length; a++) for (let b = a + 1; b < ids.length; b++) {
    const x = res.rangs[ids[a]], y = res.rangs[ids[b]];
    let w = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    for (let i = 0; i < U.n; i++) {
      if (Number.isNaN(x[i]) || Number.isNaN(y[i])) continue;
      const p = U.pop[i] || 0; w += p; sx += p * x[i]; sy += p * y[i]; sxx += p * x[i] * x[i]; syy += p * y[i] * y[i]; sxy += p * x[i] * y[i];
    }
    if (!w) continue;
    const r = (sxy / w - sx * sy / w / w) / Math.sqrt((sxx / w - (sx / w) ** 2) * (syy / w - (sy / w) ** 2));
    if (Math.abs(r) >= REDONDANCE) paires.push({ a: res.actifs[a], b: res.actifs[b], r });
  }
  return paires.sort((p, q) => Math.abs(q.r) - Math.abs(p.r));
}

// Moyenne d'une série dans les 20 % de la population qui vivent dans les unités les plus modestes,
// dans les 20 % qui vivent dans les plus aisées, et pour l'ensemble. Le classement suit le niveau de vie médian.
function tranches(U, serie) {
  const revenu = U.valeurs.revenu;
  if (!revenu) return null;
  const idx = [];
  for (let i = 0; i < U.n; i++) if (!Number.isNaN(revenu[i])) idx.push(i);
  idx.sort((a, b) => revenu[a] - revenu[b]);
  const total = idx.reduce((s, i) => s + U.pop[i], 0);
  const moyenne = liste => { let s = 0, w = 0; for (const [i, p] of liste) if (!Number.isNaN(serie[i])) { s += p * serie[i]; w += p; } return w > 0 ? s / w : NaN; };
  const prendre = ordre => { const l = []; let cumul = 0;
    for (const i of ordre) { if (cumul >= TRANCHE * total) break; const p = Math.min(U.pop[i], TRANCHE * total - cumul); l.push([i, p]); cumul += p; }
    return l; };
  return { modestes: moyenne(prendre(idx)), aises: moyenne(prendre([...idx].reverse())), ensemble: moyenne(idx.map(i => [i, U.pop[i]])) };
}

// Valeur seuil d'une série pour une part donnée de la population (pour la légende)
function quantile(valeurs, pop, sens, q) {
  const idx = [];
  valeurs.forEach((v, i) => { if (!Number.isNaN(v)) idx.push(i); });
  idx.sort((a, b) => sens * (valeurs[a] - valeurs[b]));
  const total = idx.reduce((s, i) => s + pop[i], 0);
  let cumul = 0;
  for (const i of idx) { cumul += pop[i]; if (cumul >= q * total) return valeurs[i]; }
  return NaN;
}

if (typeof module !== "undefined") module.exports = { DIMENSIONS, normaliser, PART_MINIMALE, TRANCHE, REDONDANCE, unites, rangs, calculer, redondances, tranches, quantile };