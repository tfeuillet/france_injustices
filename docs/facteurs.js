// ------------------------------------------------------------------
// Hiérarchie des facteurs associés à un indicateur.
//
// Global : corrélation de chaque facteur avec la cible, puis décomposition du R² de la
// régression multiple entre les facteurs (méthode LMG, ou valeur de Shapley : la part d'un
// facteur est son apport moyen au R² sur tous les ordres d'entrée possibles ; Lindeman, Merenda
// et Gold, 1980 ; Grömping, 2006). Des facteurs corrélés se partagent ce qu'ils expliquent en
// commun au lieu de le compter plusieurs fois.
//
// Local : la même décomposition, refaite pour chaque territoire sur une matrice de corrélation
// géographiquement pondérée (noyau et voisinage comme dans l'onglet GWR). On en tire le facteur
// dominant de chaque territoire.
//
// Tout se calcule à partir de la matrice de corrélation : le R² d'un sous-ensemble S de facteurs
// vaut r' R_SS⁻¹ r, soit ||L⁻¹ r||² avec R_SS = L L' (Cholesky).
// Fonctionne dans un Web Worker, dans la page, et dans Node pour les tests.
// ------------------------------------------------------------------

const FACTEURS = (() => {
  const MAX_GLOBAL = 16, MAX_LOCAL = 10;

  // R² de tous les sous-ensembles de facteurs. C : matrice de corrélation (p+1) x (p+1), la cible
  // en position 0. R2[S] pour S codé en bits (bit j = facteur j).
  // Calcul incrémental : la factorisation de Cholesky de S est celle de S privé de son dernier
  // facteur, plus une ligne. On ne calcule donc qu'une ligne par sous-ensemble, et le R² de S est
  // celui de S' plus le carré du nouveau terme de L⁻¹ r.
  const PLANS = {};
  function plan(p) {
    if (PLANS[p]) return PLANS[p];
    const N = 1 << p, taille = new Int32Array(N), debut = new Int32Array(N + 1), dernier = new Int32Array(N), avant = new Int32Array(N);
    for (let S = 1; S < N; S++) {
      let k = 0, h = 0; for (let j = 0; j < p; j++) if (S >> j & 1) { k++; h = j; }
      taille[S] = k; dernier[S] = h; avant[S] = S & ~(1 << h);
      debut[S + 1] = debut[S] + k;
    }
    return PLANS[p] = { N, taille, debut, dernier, avant, lignes: debut[N] };
  }
  function r2Tous(C, p, R2 = new Float64Array(1 << p), T = {}) {
    const q = p + 1, P = plan(p);
    const ligne = T.ligne || (T.ligne = new Float64Array(P.lignes)), zd = T.zd || (T.zd = new Float64Array(P.N));
    const pref = T.pref || (T.pref = new Int32Array(p)), elt = T.elt || (T.elt = new Int32Array(p));
    R2[0] = 0;
    for (let S = 1; S < P.N; S++) {
      const m = P.taille[S], h = P.dernier[S] + 1, o = P.debut[S];
      // préfixes de S (sous-ensembles de ses a+1 premiers facteurs) et leurs facteurs
      let a = m - 1; for (let t = S; t; t = P.avant[t]) { pref[a] = t; elt[a] = P.dernier[t] + 1; a--; }
      let ss = 0, zz = C[h];
      for (let b = 0; b < m - 1; b++) {
        const lb = P.debut[pref[b]];            // ligne b de L : nouvelle ligne du préfixe b
        let v = C[h * q + elt[b]];
        for (let c = 0; c < b; c++) v -= ligne[o + c] * ligne[lb + c];
        v /= ligne[lb + b];
        ligne[o + b] = v; ss += v * v; zz -= v * zd[pref[b]];
      }
      const diag = Math.sqrt(Math.max(C[h * q + h] - ss, 1e-9));   // facteurs presque colinéaires : on borne
      ligne[o + m - 1] = diag;
      zd[S] = zz / diag;
      R2[S] = Math.min(1, R2[P.avant[S]] + zd[S] * zd[S]);
    }
    return R2;
  }

  // Parts de Shapley : pour chaque facteur j, moyenne de R²(S ∪ j) − R²(S), pondérée par
  // |S|! (p − |S| − 1)! / p!
  const FACT = [1]; for (let k = 1; k <= 20; k++) FACT[k] = FACT[k - 1] * k;
  function poidsShapley(p) { return Float64Array.from({ length: p }, (_, k) => FACT[k] * FACT[p - k - 1] / FACT[p]); }
  function shapley(R2, p, w = poidsShapley(p), part = new Float64Array(p)) {
    part.fill(0);
    const N = 1 << p;
    for (let S = 0; S < N; S++) {
      let k = 0; for (let t = S; t; t &= t - 1) k++;
      if (k === p) continue;
      const base = R2[S], c = w[k];
      for (let j = 0; j < p; j++) if (!(S >> j & 1)) part[j] += c * (R2[S | 1 << j] - base);
    }
    return part;
  }

  // Matrice de corrélation pondérée de (y, x1..xp) à partir des sommes accumulées
  function correlation(S0, Sv, Svv, q, C) {
    for (let a = 0; a < q; a++) for (let b = 0; b <= a; b++) {
      const c = Svv[a * q + b] / S0 - (Sv[a] / S0) * (Sv[b] / S0);
      C[a * q + b] = C[b * q + a] = c;
    }
    const sd = new Float64Array(q);
    for (let a = 0; a < q; a++) sd[a] = Math.sqrt(Math.max(C[a * q + a], 0));
    for (let a = 0; a < q; a++) for (let b = 0; b < q; b++) C[a * q + b] = sd[a] > 0 && sd[b] > 0 ? C[a * q + b] / (sd[a] * sd[b]) : (a === b ? 1 : 0);
    return sd;
  }

  // Territoires renseignés pour la cible et tous les facteurs
  function complets(o) {
    const N = o.y.length, garde = [];
    for (let i = 0; i < N; i++) {
      if (!Number.isFinite(o.y[i]) || (o.p && !(o.p[i] > 0))) continue;
      if (o.cx && !(Number.isFinite(o.cx[i]) && Number.isFinite(o.cy[i]))) continue;
      let ok = true;
      for (const x of o.X) if (!Number.isFinite(x[i])) { ok = false; break; }
      if (ok) garde.push(i);
    }
    return garde;
  }

  // ---------- Global ----------
  // o : { y, X (liste de séries), p (poids ou null) }
  function global(o) {
    const p = o.X.length, q = p + 1;
    if (!p) return { erreur: "Aucun facteur retenu." };
    if (p > MAX_GLOBAL) return { erreur: `Au plus ${MAX_GLOBAL} facteurs à la fois.` };
    const garde = complets(o), n = garde.length;
    if (n < 3 * q) return { erreur: "Trop peu de territoires renseignés pour la cible et tous les facteurs." };
    let S0 = 0; const Sv = new Float64Array(q), Svv = new Float64Array(q * q), v = new Float64Array(q);
    for (const i of garde) {
      const w = o.p ? o.p[i] : 1;
      v[0] = o.y[i]; for (let j = 0; j < p; j++) v[j + 1] = o.X[j][i];
      S0 += w;
      for (let a = 0; a < q; a++) { Sv[a] += w * v[a]; for (let b = 0; b <= a; b++) Svv[a * q + b] += w * v[a] * v[b]; }
    }
    const C = new Float64Array(q * q);
    correlation(S0, Sv, Svv, q, C);
    const R2 = r2Tous(C, p), part = shapley(R2, p), r2 = R2[(1 << p) - 1];
    // coefficients standardisés du modèle complet : R_xx β = r_xy
    const A = Array.from({ length: p }, (_, a) => Array.from({ length: p }, (_, b) => C[(a + 1) * q + b + 1]));
    const beta = resoudre(A, Array.from({ length: p }, (_, a) => C[a + 1]));
    return { n, r2, r: Array.from({ length: p }, (_, j) => C[j + 1]), part: Array.from(part), beta, C: Array.from(C) };
  }

  // Petit système linéaire (pivot de Gauss)
  function resoudre(A, b) {
    const n = b.length, M = A.map((l, i) => [...l, b[i]]);
    for (let c = 0; c < n; c++) {
      let m = c; for (let l = c + 1; l < n; l++) if (Math.abs(M[l][c]) > Math.abs(M[m][c])) m = l;
      [M[c], M[m]] = [M[m], M[c]];
      if (Math.abs(M[c][c]) < 1e-12) return new Array(n).fill(NaN);
      for (let l = 0; l < n; l++) if (l !== c) { const f = M[l][c] / M[c][c]; for (let k = c; k <= n; k++) M[l][k] -= f * M[c][k]; }
    }
    return M.map((l, i) => l[n] / l[i]);
  }

  // ---------- Local ----------
  // o : { cx, cy (km), y, X, p (poids ou null), noyau, k (voisins, largeur adaptative) }
  function local(o, progres) {
    const p = o.X.length, q = p + 1, N = o.y.length;
    if (!p) return { erreur: "Aucun facteur retenu." };
    if (p > MAX_LOCAL) return { erreur: `Au plus ${MAX_LOCAL} facteurs pour la carte locale.` };
    const garde = complets(o), n = garde.length;
    if (n < 3 * q) return { erreur: "Trop peu de territoires renseignés pour la cible et tous les facteurs." };
    const T = GWR.outils, noyau = GWR.NOYAUX[o.noyau] ? o.noyau : "bicarre", portee = GWR.NOYAUX[noyau].portee;
    const CX = new Float64Array(n), CY = new Float64Array(n);
    garde.forEach((i, s) => { CX[s] = o.cx[i]; CY[s] = o.cy[i]; });
    const G = T.grille(CX, CY);
    // valeurs dans l'ordre de la grille, centrées (calcul plus stable)
    const V = new Float64Array(n * q), P = new Float64Array(n), moy = new Float64Array(q);
    for (let s = 0; s < n; s++) { const i = garde[G.membres[s]]; V[s * q] = o.y[i]; for (let j = 0; j < p; j++) V[s * q + j + 1] = o.X[j][i]; P[s] = o.p ? o.p[i] : 1; }
    for (let s = 0; s < n; s++) for (let a = 0; a < q; a++) moy[a] += V[s * q + a] / n;
    for (let s = 0; s < n; s++) for (let a = 0; a < q; a++) V[s * q + a] -= moy[a];
    let mp = 0; for (let s = 0; s < n; s++) mp += P[s] / n;
    for (let s = 0; s < n; s++) P[s] /= mp;
    const k = Math.max(q + 2, Math.min(n, Math.round(o.k || 500)));
    const dominant = new Int8Array(N).fill(-1), r2 = new Float64Array(N).fill(NaN), parts = Array.from({ length: p }, () => new Float64Array(N).fill(NaN));
    const C = new Float64Array(q * q), Sv = new Float64Array(q), Svv = new Float64Array(q * q);
    const R2 = new Float64Array(1 << p), travail = {}, w = poidsShapley(p), part = new Float64Array(p);
    const aire = G.nx * G.ny * G.cote * G.cote;
    let Rk = Math.sqrt(aire * k / (Math.PI * n)) + G.cote, echecs = 0, voisins = 0;
    for (let t = 0; t < n; t++) {
      const s = t, i = garde[G.membres[s]];          // on suit l'ordre de la grille
      if (progres && t % 1000 === 0) progres(t / n);
      const res = T.distanceK(G, G.gx[s], G.gy[s], k, Rk);
      const h = Math.max(1e-9, res.h);
      Rk = Math.max(h * 1.1, 1e-6);
      const m = portee * h > res.R ? T.autour(G, G.gx[s], G.gy[s], portee * h) : res.m;
      const h2 = h * h, I = G.idx, d2 = G.d2;
      let S0 = 0, nb = 0; Sv.fill(0); Svv.fill(0);
      for (let e = 0; e < m; e++) {
        const u2 = d2[e] / h2;
        if (u2 > portee * portee) continue;
        const j = I[e], wj = T.poidsNoyau(noyau, u2) * P[j];
        if (wj <= 0) continue;
        nb++; S0 += wj;
        const b0 = j * q;
        for (let a = 0; a < q; a++) { const va = wj * V[b0 + a]; Sv[a] += va; for (let b = 0; b <= a; b++) Svv[a * q + b] += va * V[b0 + b]; }
      }
      voisins += nb;
      if (nb < q + 2) { echecs++; continue; }
      const sd = correlation(S0, Sv, Svv, q, C);
      if (!(sd[0] > 0)) { echecs++; continue; }
      r2Tous(C, p, R2, travail);
      shapley(R2, p, w, part);
      let best = 0;
      for (let j = 0; j < p; j++) { parts[j][i] = R2[(1 << p) - 1] > 0 ? part[j] / R2[(1 << p) - 1] : 0; if (part[j] > part[best]) best = j; }
      r2[i] = R2[(1 << p) - 1]; dominant[i] = best;
    }
    return { n, k, dominant, r2, parts, voisins: voisins / Math.max(1, n - echecs), echecs };
  }

  return { MAX_GLOBAL, MAX_LOCAL, global, local, r2Tous, shapley };
})();

// ---------- Dans un Web Worker ----------
if (typeof self !== "undefined" && typeof window === "undefined" && typeof importScripts === "function") {
  importScripts("gwr.js");          // grille de voisinage et noyaux (gwr.js installe son propre gestionnaire, remplacé ici)
  self.onmessage = e => {
    const { id, o } = e.data;
    try { self.postMessage({ id, res: FACTEURS.local(o, p => self.postMessage({ id, progres: p })) }); }
    catch (err) { self.postMessage({ id, res: { erreur: String(err) } }); }
  };
}
if (typeof module !== "undefined") module.exports = FACTEURS;
