// ------------------------------------------------------------------
// Calculs de la carte des injustices territoriales.
// Tout est fait dans le navigateur, à partir de docs/data/donnees.json.
// ------------------------------------------------------------------

// Dimensions de l'injustice. Chaque dimension cochée pèse autant dans le score, quel que soit
// le nombre de ses indicateurs : trois mesures du même phénomène ne comptent pas trois fois.
const DIMENSIONS = [
  { id: "niveau_vie", nom: "Niveau de vie" },
  { id: "services", nom: "Accès aux services" },
  { id: "numerique", nom: "Accès au numérique" },
  { id: "education", nom: "Éducation" },
  { id: "environnement", nom: "Environnement et risques" },
  { id: "pesticides", nom: "Pesticides et eau" },
  { id: "voix", nom: "Participation politique" },
  { id: "sante", nom: "Santé" },
  { id: "trajectoires", nom: "Trajectoires récentes (dix ans)" },
  { id: "temps_long", nom: "Trajectoires longues" }
];
// Niveaux géographiques. Tous, sauf la commune, sont calculés dans la page à partir des communes.
// f : nom féminin (pour accorder les phrases automatiques).
const NIVEAUX = {
  commune: { titre: "Communes", un: "commune", des: "communes", f: true, par: "Par commune" },
  epci: { titre: "Intercommunalités", un: "intercommunalité", des: "intercommunalités", f: true, par: "Par intercommunalité" },
  bv: { titre: "Bassins de vie", un: "bassin de vie", des: "bassins de vie", f: false, par: "Par bassin de vie" },
  ze: { titre: "Zones d'emploi", un: "zone d'emploi", des: "zones d'emploi", f: true, par: "Par zone d'emploi" }
};
// Codes et noms des unités d'un niveau supra-communal (null s'il manque au fichier de données)
const zonesDe = (D, niv) => niv === "epci" ? D.epci : (D.zonages && D.zonages[niv] && D.communes[niv]) ? D.zonages[niv] : null;

// Pour un fichier de données plus ancien, sans les colonnes dimension, cumul et defaut
const ANCIEN = {
  pauvrete: ["niveau_vie", 0, 0], revenu: ["niveau_vie", 0, 0], edi: ["niveau_vie", 1, 1], apl: ["services", 1, 1], scale: ["services", 1, 1],
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
  eau_depassements: "les dépassements des limites de pesticides dans l'eau", inondation: "la population en zone inondable",
  abstention: "l'abstention", icm: "la surmortalité", prematuree: "la mortalité prématurée", emploi: "l'évolution de l'emploi salarié privé",
  superieur: "l'éloignement des formations post-bac", lycee: "l'éloignement du lycée général", segregation: "la ségrégation sociale entre collèges",
  population: "l'évolution de la population", revenu_long: "l'évolution du rang de revenu", capital_long: "l'évolution du rang de capital immobilier"
};
// Indicateurs supplémentaires : plus fragiles ou en partie redondants, rangés à part (repliés)
// catnat : les arrêtés dépendent aussi des démarches des communes ; la population en zone inondable mesure mieux l'exposition
// fibre : elle couvre désormais presque tout le territoire et ne distingue plus guère les territoires (près de
// la moitié de la population vit dans une commune raccordée à plus de 98 %)
const SUPPLEMENTAIRES = new Set(["pauvrete", "revenu", "fibre", "revenu_long", "capital_long", "seveso", "abstention", "catnat"]);
// Sélection proposée : dans chaque dimension, les indicateurs de cette liste qui y figurent (à défaut, le premier
// indicateur de la dimension). Une dimension dont tous les indicateurs sont supplémentaires n'est pas cochée.
const PROPOSES = ["edi", "scale", "segregation", "pm25", "chaleur", "eau_depassements", "eau_nitrates", "icm", "emploi"];
function normaliser(D) {
  for (const ind of D.indicateurs) {
    const a = ANCIEN[ind.id] || ["niveau_vie", 1, 0];
    if (!ind.dimension) ind.dimension = a[0];
    // fichiers de données antérieurs au 24 novembre 2026 : les distances (soins, lycée, études) forment
    // désormais une seule dimension « Accès aux services »
    if (ind.dimension === "soins" || ["lycee", "superieur"].includes(ind.id)) ind.dimension = "services";
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
    let choisis = liste.filter(ind => PROPOSES.includes(ind.id)).map(ind => ind.id);
    if (!choisis.length && liste.length) choisis = [liste[0].id];
    for (const ind of D.indicateurs.filter(ind => ind.dimension === d.id)) ind.defaut = choisis.includes(ind.id) ? 1 : 0;
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
  if (echelle === "commune") {
    return { echelle, n, code: C.code, nom: C.nom, pop: C.pop, cx, cy,
      details: Object.fromEntries(D.indicateurs.filter(ind => ind.detail).map(ind => [ind.id,
        { noms: ind.detail.noms, valeurs: ind.detail.valeurs.map(v => v.map(x => x === null ? NaN : x)) }])),
      valeurs: Object.fromEntries(D.indicateurs.map(ind => [ind.id, ind.valeurs.map(v => v === null ? NaN : v)])),
      impute: Object.fromEntries(D.indicateurs.map(ind => [ind.id, new Set(ind.impute)])) };
  }
  const Z = zonesDe(D, echelle), appartient = C[echelle];
  const rang = new Map(Z.code.map((c, k) => [c, k])), m = Z.code.length;
  const pop = new Array(m).fill(0), membre = new Int32Array(n).fill(-1);
  const sx = new Float64Array(m), sy = new Float64Array(m), sw = new Float64Array(m);
  for (let i = 0; i < n; i++) {
    const k = rang.get(appartient[i]);
    if (k === undefined) continue;
    membre[i] = k; pop[k] += C.pop[i];
    const p = C.pop[i] || 0.001; sx[k] += p * cx[i]; sy[k] += p * cy[i]; sw[k] += p;   // centre de gravité de la population
  }
  const valeurs = {}, details = {};
  // moyenne des communes de chaque unité, pondérée par leur population
  const moyenneUnites = serie => {
    const s = new Float64Array(m), w = new Float64Array(m);
    serie.forEach((v, i) => { const k = membre[i]; if (k < 0 || v === null || Number.isNaN(v)) return; const p = C.pop[i] || 0.001; s[k] += p * v; w[k] += p; });
    return Array.from(s, (x, k) => w[k] > 0 ? x / w[k] : NaN);
  };
  // décomposition d'un indicateur (types de catastrophes naturelles), moyennée comme l'indicateur
  for (const ind of D.indicateurs) if (ind.detail) details[ind.id] = { noms: ind.detail.noms, valeurs: ind.detail.valeurs.map(moyenneUnites) };
  for (const ind of D.indicateurs) {
    const s = new Float64Array(m), w = new Float64Array(m);
    ind.valeurs.forEach((v, i) => { const k = membre[i]; if (k < 0 || v === null) return; const p = C.pop[i] || 0.001; s[k] += p * v; w[k] += p; });
    const moyenne = Array.from(s, (x, k) => w[k] > 0 ? x / w[k] : NaN);
    // valeur calculée directement pour ce niveau (ségrégation entre collèges, par exemple). Là où elle
    // manque (un seul collège dans la zone), on prend la moyenne de ses communes.
    const propre = ind.niveaux && ind.niveaux[echelle];
    valeurs[ind.id] = propre ? propre.map((v, k) => v === null || Number.isNaN(v) ? moyenne[k] : v) : moyenne;
  }
  return { echelle, n: m, code: Z.code, nom: Z.nom, pop, valeurs, details, impute: {}, membre,
    cx: Array.from(sx, (v, k) => sw[k] > 0 ? v / sw[k] : NaN), cy: Array.from(sy, (v, k) => sw[k] > 0 ? v / sw[k] : NaN) };
}

// Paliers. Pour les pesticides et les nitrates dans l'eau, les petites différences n'ont pas de sens :
// en bas de l'échelle, elles tiennent aux seuils de quantification des laboratoires, et les rangs les
// étireraient (0,03 et 0,06 µg/L de pesticides seraient aux rangs 50 et 75). La valeur est donc d'abord
// ramenée à son palier, fixé d'après les limites de qualité de l'eau, puis le palier est converti en rang
// de population. Tous les territoires d'un même palier ont le même rang. Le premier palier est au rang 0,
// comme une absence d'exposition. Les valeurs elles-mêmes restent affichées dans les fiches.
//   pesticides : limite de 0,1 µg/L par substance, de 0,5 µg/L pour le total
//   nitrates : 25 mg/L, ancienne valeur guide européenne ; 40 mg/L, seuil de vigilance ; 50 mg/L, limite de
//   qualité. Sous 25 mg/L, les écarts ne départagent pas les territoires.
const PALIERS = { eau_pesticides: [0.1, 0.5], eau_nitrates: [25, 40, 50] };
// Couleur de chaque palier quand la carte montre l'indicateur lui-même : vert sous le premier seuil,
// puis du jaune au rouge foncé (sans bleu)
const PALIERS_COULEURS = { eau_pesticides: ["#1a9850", "#f46d43", "#a50026"],
  eau_nitrates: ["#1a9850", "#fdae61", "#d73027", "#a50026"] };
const palier = (id, v) => Number.isNaN(v) ? NaN : PALIERS[id].filter(s => v >= s).length;
const pourRangs = (id, valeurs) => PALIERS[id] ? Array.from(valeurs, v => palier(id, v)) : valeurs;
// Indicateurs où beaucoup de territoires sont à égalité, souvent faute d'exposition : aucune nuit
// chaude, aucun site Seveso, aucun arrêté de catastrophe naturelle, tous les locaux raccordables à la
// fibre. Comme pour les paliers, les territoires les mieux lotis, à égalité, sont au rang 0, et non au
// milieu de leur groupe : les non-exposés sont à 0.
const PLANCHER = new Set([...Object.keys(PALIERS), "chaleur", "seveso", "catnat", "fibre", "inondation", "eau_depassements"]);

// Rang de chaque unité, entre 0 et 1 : part de la population qui vit dans une unité mieux lotie,
// plus la moitié de celle qui vit dans une unité à égalité. 0,8 veut dire « plus défavorisée
// que 80 % de la population ». Les valeurs manquantes restent manquantes (NaN).
// plancher = true : le groupe le mieux loti (les non-exposés, à égalité) est au rang 0 au lieu du milieu
// de son groupe. Les autres groupes à égalité gardent le rang du milieu de leur groupe.
function rangs(valeurs, pop, sens, plancher = false) {
  const idx = [];
  valeurs.forEach((v, i) => { if (!Number.isNaN(v)) idx.push(i); });
  idx.sort((a, b) => sens * (valeurs[a] - valeurs[b]));
  const total = idx.reduce((s, i) => s + pop[i], 0) || 1, r = new Float64Array(valeurs.length).fill(NaN);
  let avant = 0;
  for (let a = 0; a < idx.length;) {
    let b = a, groupe = 0;
    while (b < idx.length && valeurs[idx[b]] === valeurs[idx[a]]) groupe += pop[idx[b++]];
    for (let k = a; k < b; k++) r[idx[k]] = plancher && a === 0 ? 0 : (avant + groupe / 2) / total;
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
  for (const ind of D.indicateurs) R[ind.id] = rangs(pourRangs(ind.id, U.valeurs[ind.id]), U.pop, ind.sens, PLANCHER.has(ind.id));
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
    // rang de la dimension, pour la carte et les fiches, avec la même règle que les indicateurs : une
    // dimension faite d'un seul indicateur à paliers garde ainsi ses non-exposés au rang 0.
    rangDim[d.id] = rangs(Array.from(v), U.pop, 1, true);
  }
  const brut = new Float64Array(U.n).fill(NaN), compte = new Float64Array(U.n).fill(NaN);
  for (let i = 0; i < U.n; i++) {
    let s = 0, k = 0, c = 0;
    for (const d of dims) { const v = parDim[d.id][i]; if (!Number.isNaN(v)) { s += v; k++; if (rangDim[d.id][i] >= 1 - seuil) c++; } }
    if (dims.length && k >= PART_MINIMALE * dims.length) { brut[i] = s / k; compte[i] = c; }
  }
  // même règle pour les ex æquo que pour les indicateurs et les dimensions
  const score = rangs(Array.from(brut), U.pop, 1, true);
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
    // les rangs sont orientés (1 = le plus défavorable) : seule une corrélation positive fait compter
    // deux fois un même désavantage ; une corrélation négative oppose deux désavantages qui se compensent
    if (r >= REDONDANCE) paires.push({ a: res.actifs[a], b: res.actifs[b], r });
  }
  return paires.sort((p, q) => q.r - p.r);
}

// Nombre effectif de dimensions : p² / Σ r², où r parcourt la matrice de corrélation (pondérée par la
// population) des rangs des dimensions cochées. Il vaut p si les dimensions sont indépendantes, 1 si
// elles disent toutes la même chose. C'est (Σλ)² / Σλ² pour les valeurs propres λ de cette matrice.
function dimensionsEffectives(res, U) {
  const ids = res.dims.map(d => d.id), p = ids.length;
  if (p < 2) return p;
  let somme = 0;
  for (let a = 0; a < p; a++) for (let b = 0; b < p; b++) {
    if (a === b) { somme += 1; continue; }
    const x = res.rangDim[ids[a]], y = res.rangDim[ids[b]];
    let w = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    for (let i = 0; i < U.n; i++) {
      if (Number.isNaN(x[i]) || Number.isNaN(y[i])) continue;
      const q = U.pop[i] || 0; w += q; sx += q * x[i]; sy += q * y[i]; sxx += q * x[i] * x[i]; syy += q * y[i] * y[i]; sxy += q * x[i] * y[i];
    }
    if (!w) continue;
    const r = (sxy / w - sx * sy / w / w) / Math.sqrt((sxx / w - (sx / w) ** 2) * (syy / w - (sy / w) ** 2));
    if (Number.isFinite(r)) somme += r * r;
  }
  return p * p / somme;
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

if (typeof module !== "undefined") module.exports = { PALIERS, PALIERS_COULEURS, PLANCHER, palier, DIMENSIONS, normaliser, dimensionsEffectives, PART_MINIMALE, TRANCHE, REDONDANCE, unites, rangs, calculer, redondances, tranches, quantile };