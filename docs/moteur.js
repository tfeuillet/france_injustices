// ------------------------------------------------------------------
// Calculs de la carte des injustices territoriales.
// Tout est fait dans le navigateur, à partir de docs/data/donnees.json.
// ------------------------------------------------------------------

const FAMILLES = [
  { id: "situation", nom: "Situation sociale" },
  { id: "moyens", nom: "Moyens au regard des besoins" },
  { id: "exposition", nom: "Exposition aux nuisances et aux risques" },
  { id: "voix", nom: "Voix politique" }
];
// Poids proposés au départ. Le niveau de vie est à 0 car il redouble le taux de pauvreté ;
// il sert surtout à distinguer les territoires modestes des territoires aisés.
const POIDS_DEFAUT = { pauvrete: 5, revenu: 0, apl: 5, fibre: 2, no2: 3, pm25: 3, seveso: 2, catnat: 2, abstention: 5 };
const PART_MINIMALE = 0.5;   // part des poids qui doit être renseignée pour qu'un score soit calculé
const TRANCHE = 0.2;         // les 20 % les plus modestes et les 20 % les plus aisés

// Unités de la carte : les communes, ou les intercommunalités (moyennes pondérées par la population)
function unites(D, echelle) {
  const C = D.communes, n = C.code.length;
  if (echelle !== "epci") {
    return { echelle, n, code: C.code, nom: C.nom, pop: C.pop,
      valeurs: Object.fromEntries(D.indicateurs.map(ind => [ind.id, ind.valeurs.map(v => v === null ? NaN : v)])),
      impute: Object.fromEntries(D.indicateurs.map(ind => [ind.id, new Set(ind.impute)])) };
  }
  const rang = new Map(D.epci.code.map((c, k) => [c, k])), m = D.epci.code.length;
  const pop = new Array(m).fill(0), membre = new Int32Array(n).fill(-1);
  for (let i = 0; i < n; i++) { const k = rang.get(C.epci[i]); if (k !== undefined) { membre[i] = k; pop[k] += C.pop[i]; } }
  const valeurs = {};
  for (const ind of D.indicateurs) {
    const s = new Float64Array(m), w = new Float64Array(m);
    ind.valeurs.forEach((v, i) => { const k = membre[i]; if (k < 0 || v === null) return; const p = C.pop[i] || 0.001; s[k] += p * v; w[k] += p; });
    valeurs[ind.id] = Array.from(s, (x, k) => w[k] > 0 ? x / w[k] : NaN);
  }
  return { echelle, n: m, code: D.epci.code, nom: D.epci.nom, pop, valeurs, impute: {} };
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

// Score cumulé : moyenne pondérée des rangs. Une unité où trop d'indicateurs manquent n'a pas de score.
function calculer(D, U, poids) {
  const actifs = D.indicateurs.filter(ind => (poids[ind.id] || 0) > 0);
  const R = {};
  for (const ind of D.indicateurs) R[ind.id] = rangs(U.valeurs[ind.id], U.pop, ind.sens);
  const somme = actifs.reduce((s, ind) => s + poids[ind.id], 0);
  const score = new Float64Array(U.n).fill(NaN);
  if (somme > 0) for (let i = 0; i < U.n; i++) {
    let s = 0, w = 0;
    for (const ind of actifs) { const r = R[ind.id][i]; if (!Number.isNaN(r)) { s += poids[ind.id] * r; w += poids[ind.id]; } }
    if (w >= PART_MINIMALE * somme) score[i] = s / w;
  }
  return { rangs: R, score, actifs };
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

if (typeof module !== "undefined") module.exports = { FAMILLES, POIDS_DEFAUT, PART_MINIMALE, TRANCHE, unites, rangs, calculer, tranches, quantile };
