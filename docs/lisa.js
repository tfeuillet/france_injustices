// ------------------------------------------------------------------
// Indicateurs locaux d'autocorrélation spatiale (LISA) : I de Moran local, univarié
// ou bivarié (Anselin, 1995 ; Anselin, Syabri et Smirnov, 2002), avec des permutations
// conditionnelles pour la significativité, comme le module esda de PySAL.
// Fonctionne dans un Web Worker, dans la page, et dans Node pour les tests.
// ------------------------------------------------------------------

const LISA = (() => {
  // Générateur pseudo-aléatoire à graine fixe : la même carte à chaque calcul
  function alea(graine) {
    let s = (graine >>> 0) || 1;
    return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
  }

  // ---------- Voisinages ----------
  // Contiguïté « reine » : deux unités sont voisines si elles partagent au moins un sommet.
  // Les contours simplifiés gardent les mêmes sommets de part et d'autre d'une frontière.
  function reine(features, indice, n) {
    const sommets = new Map();
    for (const f of features) {
      const u = indice(f);
      if (u === undefined || u < 0 || !f.geometry) continue;
      const g = f.geometry, polys = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
      for (const p of polys) for (const anneau of p) for (const c of anneau) {
        const k = Math.round((c[0] + 180) * 1e4) * 4e6 + Math.round((c[1] + 90) * 1e4);
        const l = sommets.get(k);
        if (!l) sommets.set(k, [u]); else if (!l.includes(u)) l.push(u);
      }
    }
    const V = Array.from({ length: n }, () => new Set());
    for (const l of sommets.values()) if (l.length > 1) for (const a of l) for (const b of l) if (a !== b) V[a].add(b);
    return V.map(v => Int32Array.from(v));
  }

  // Ordres supérieurs (cumulés) : voisins des voisins, jusqu'à l'ordre k
  function ordre(V, k) {
    if (k <= 1) return V;
    return V.map((v0, i) => {
      const vu = new Set([i]); let front = [i];
      for (let o = 0; o < k; o++) {
        const suite = [];
        for (const a of front) for (const b of V[a]) if (!vu.has(b)) { vu.add(b); suite.push(b); }
        front = suite;
      }
      vu.delete(i);
      return Int32Array.from(vu);
    });
  }

  // Grille pour les voisinages fondés sur la distance
  function grille(X, Y) {
    const n = X.length, ok = [];
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let i = 0; i < n; i++) if (Number.isFinite(X[i]) && Number.isFinite(Y[i])) { ok.push(i); x0 = Math.min(x0, X[i]); x1 = Math.max(x1, X[i]); y0 = Math.min(y0, Y[i]); y1 = Math.max(y1, Y[i]); }
    const cote = Math.max(1e-6, Math.sqrt(((x1 - x0) * (y1 - y0) || 1) / Math.max(1, ok.length / 2)));
    const nx = Math.floor((x1 - x0) / cote) + 1, ny = Math.floor((y1 - y0) / cote) + 1, cellules = new Map();
    for (const i of ok) { const c = Math.floor((X[i] - x0) / cote) + nx * Math.floor((Y[i] - y0) / cote); if (!cellules.has(c)) cellules.set(c, []); cellules.get(c).push(i); }
    const autour = (i, R) => {
      const r = Math.ceil(R / cote), cx = Math.floor((X[i] - x0) / cote), cy = Math.floor((Y[i] - y0) / cote), res = [];
      for (let gy = Math.max(0, cy - r); gy <= Math.min(ny - 1, cy + r); gy++)
        for (let gx = Math.max(0, cx - r); gx <= Math.min(nx - 1, cx + r); gx++) {
          const l = cellules.get(gx + nx * gy);
          if (l) for (const j of l) { if (j === i) continue; const d = Math.hypot(X[j] - X[i], Y[j] - Y[i]); if (d <= R) res.push([j, d]); }
        }
      return res;
    };
    return { ok, autour, cote, n: ok.length, aire: (x1 - x0) * (y1 - y0) };
  }
  function distance(X, Y, R) {
    const G = grille(X, Y), V = Array.from({ length: X.length }, () => new Int32Array(0));
    for (const i of G.ok) V[i] = Int32Array.from(G.autour(i, R).map(p => p[0]));
    return V;
  }
  function plusProches(X, Y, k) {
    const G = grille(X, Y), V = Array.from({ length: X.length }, () => new Int32Array(0));
    for (const i of G.ok) {
      let R = Math.sqrt(G.aire * (k + 1) / (Math.PI * G.n)) + G.cote, l;
      for (;;) { l = G.autour(i, R); if (l.length >= k || l.length >= G.n - 1) break; R *= 1.5; }
      l.sort((a, b) => a[1] - b[1]);
      V[i] = Int32Array.from(l.slice(0, k).map(p => p[0]));
    }
    return V;
  }
  // Unités sans voisin (îles) : on leur donne leur plus proche voisin, pour qu'elles restent dans le calcul
  function sansIsoles(V, X, Y) {
    const isoles = [];
    V.forEach((v, i) => { if (!v.length && Number.isFinite(X[i])) isoles.push(i); });
    if (!isoles.length) return { V, isoles: 0 };
    const P = plusProches(X, Y, 1);
    const W = V.slice();
    for (const i of isoles) W[i] = P[i];
    return { V: W, isoles: isoles.length };
  }
  // Format compact (CSR) pour l'envoi au Worker
  function compacter(V) {
    const debut = new Int32Array(V.length + 1);
    V.forEach((v, i) => debut[i + 1] = debut[i] + v.length);
    const liste = new Int32Array(debut[V.length]);
    V.forEach((v, i) => liste.set(v, debut[i]));
    return { debut, liste };
  }

  // ---------- I de Moran local ----------
  // o : { x, y (null en univarié), debut, liste (voisins), permutations, graine }
  // Bivarié : I_i = z_x,i × moyenne des z_y des voisins (« x ici, y autour »).
  function calculer(o, progres) {
    const N = o.x.length, biv = !!o.y;
    // unités retenues : valeurs renseignées
    const garde = new Int32Array(N).fill(-1), ids = [];
    for (let i = 0; i < N; i++) if (Number.isFinite(o.x[i]) && (!biv || Number.isFinite(o.y[i]))) { garde[i] = ids.length; ids.push(i); }
    const n = ids.length;
    if (n < 10) return { erreur: "Trop peu de territoires renseignés." };
    const standard = v => {
      let m = 0; for (const i of ids) m += v[i]; m /= n;
      let s = 0; for (const i of ids) s += (v[i] - m) ** 2; s = Math.sqrt(s / n) || 1;
      const z = new Float64Array(n); ids.forEach((i, q) => z[q] = (v[i] - m) / s); return z;
    };
    const zx = standard(o.x), zy = biv ? standard(o.y) : zx;
    // voisins en indices compacts (seulement ceux qui sont renseignés)
    const deb = new Int32Array(n + 1), tmp = [];
    ids.forEach((i, q) => { for (let p = o.debut[i]; p < o.debut[i + 1]; p++) { const j = garde[o.liste[p]]; if (j >= 0) tmp.push(j); } deb[q + 1] = tmp.length; });
    const vois = Int32Array.from(tmp);
    // retard spatial (moyenne des voisins : poids standardisés en ligne)
    const lag = new Float64Array(n).fill(NaN), I = new Float64Array(n).fill(NaN);
    const f = (n - 1) / n;   // même échelle que esda (PySAL)
    for (let q = 0; q < n; q++) {
      const k = deb[q + 1] - deb[q];
      if (!k) continue;
      let s = 0; for (let p = deb[q]; p < deb[q + 1]; p++) s += zy[vois[p]];
      lag[q] = s / k; I[q] = f * zx[q] * lag[q];
    }
    // permutations conditionnelles : on tire k autres unités au hasard pour chaque unité.
    // Le tirage est sans remise quand il y a peu d'unités ; au-delà, deux fois la même unité
    // parmi k tirages est si rare (moins de 0,5 % des cas) qu'on ne le vérifie pas.
    const P = o.permutations || 999, pval = new Float64Array(n).fill(NaN), tirage = new Int32Array(1024);
    const sansRemise = n < 3000;
    let st = (o.graine || 12345) >>> 0;
    for (let q = 0; q < n; q++) {
      if (progres && q % 2000 === 0) progres(q / n);
      const k = deb[q + 1] - deb[q];
      if (!k || Number.isNaN(I[q])) continue;
      const seuil = I[q] / (f * zx[q] / k);   // I_perm >= I  <=>  somme tirée >= seuil (si z_x > 0)
      const positif = zx[q] > 0;
      let plusGrand = 0;
      for (let r = 0; r < P; r++) {
        let somme = 0;
        for (let a = 0; a < k; a++) {
          let j;
          for (;;) {
            st ^= st << 13; st >>>= 0; st ^= st >>> 17; st ^= st << 5; st >>>= 0;
            j = Math.floor(st / 4294967296 * n);
            if (j === q) continue;
            if (sansRemise) { let deja = false; for (let b = 0; b < a; b++) if (tirage[b] === j) { deja = true; break; } if (deja) continue; tirage[a] = j; }
            break;
          }
          somme += zy[j];
        }
        if (zx[q] === 0 ? 0 >= I[q] : positif ? somme >= seuil : somme <= seuil) plusGrand++;
      }
      if (P - plusGrand < plusGrand) plusGrand = P - plusGrand;
      pval[q] = (plusGrand + 1) / (P + 1);
    }
    const R = alea(o.graine || 12345);
    // I global et sa significativité (permutations totales)
    let num = 0, den = 0, avecVoisins = 0;
    for (let q = 0; q < n; q++) { den += zx[q] * zx[q]; if (!Number.isNaN(lag[q])) { num += zx[q] * lag[q]; avecVoisins++; } }
    const Iglobal = num / den;
    let plus = 0;
    const PG = Math.min(P, 199), perm = Int32Array.from({ length: n }, (_, q) => q);
    for (let r = 0; r < PG; r++) {
      for (let q = n - 1; q > 0; q--) { const j = Math.floor(R() * (q + 1)); const t = perm[q]; perm[q] = perm[j]; perm[j] = t; }
      let s = 0;
      for (let q = 0; q < n; q++) { const k = deb[q + 1] - deb[q]; if (!k) continue; let l = 0; for (let p = deb[q]; p < deb[q + 1]; p++) l += zy[perm[vois[p]]]; s += zx[q] * l / k; }
      if (s / den >= Iglobal) plus++;
    }
    if (PG - plus < plus) plus = PG - plus;
    // remettre dans l'ordre des territoires de départ
    const remettre = v => { const s = new Float64Array(N).fill(NaN); ids.forEach((i, q) => s[i] = v[q]); return s; };
    let k = 0; for (let q = 0; q < n; q++) k += deb[q + 1] - deb[q];
    return { n, I: remettre(I), lag: remettre(lag), z: remettre(zx), p: remettre(pval), permutations: P,
      global: { I: Iglobal, p: (plus + 1) / (PG + 1), permutations: PG }, voisinsMoyens: k / n };
  }

  // Quadrant et significativité : 1 haut-haut, 2 bas-haut, 3 bas-bas, 4 haut-bas, 0 non significatif.
  // correction "fdr" : taux de fausses découvertes de Benjamini et Hochberg.
  function classer(r, alpha, correction) {
    let seuil = alpha;
    if (correction === "fdr") {
      const p = Array.from(r.p).filter(Number.isFinite).sort((a, b) => a - b), m = p.length;
      seuil = 0;
      for (let k = 1; k <= m; k++) if (p[k - 1] <= alpha * k / m) seuil = p[k - 1];
    }
    const c = new Int8Array(r.p.length).fill(-1);
    for (let i = 0; i < r.p.length; i++) {
      if (!Number.isFinite(r.p[i]) || Number.isNaN(r.lag[i])) continue;
      if (r.p[i] > seuil || seuil === 0) { c[i] = 0; continue; }
      const h = r.z[i] > 0, l = r.lag[i] > 0;
      c[i] = h && l ? 1 : !h && l ? 2 : !h && !l ? 3 : 4;
    }
    return { classe: c, seuil };
  }

  return { reine, ordre, distance, plusProches, sansIsoles, compacter, calculer, classer };
})();

// ---------- Dans un Web Worker ----------
if (typeof self !== "undefined" && typeof window === "undefined" && typeof importScripts === "function") {
  self.onmessage = e => {
    const { id, o } = e.data;
    try { self.postMessage({ id, res: LISA.calculer(o, p => self.postMessage({ id, progres: p })) }); }
    catch (err) { self.postMessage({ id, res: { erreur: String(err) } }); }
  };
}
if (typeof module !== "undefined") module.exports = LISA;
