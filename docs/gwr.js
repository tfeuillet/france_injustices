// ------------------------------------------------------------------
// Régression géographiquement pondérée bivariée (GWR) et corrélation locale.
// Fonctionne dans un Web Worker (le calcul ne bloque pas la page), dans la page
// elle-même si le Worker n'est pas disponible, et dans Node pour les tests.
//
// Pour chaque territoire i, on estime y = a_i + b_i x par moindres carrés pondérés.
// Le poids d'un voisin j vaut K(d_ij / h_i), multiplié par sa population si on le
// demande. Les formules du chapeau (trace de S, AICc) et des écarts types locaux
// suivent Fotheringham, Brunsdon et Charlton (2002), comme le paquet R GWmodel.
// ------------------------------------------------------------------

const GWR = (() => {
  // Les noyaux sont écrits en fonction de u² = (d / h)², ce qui évite les racines carrées.
  // portee : au-delà de portee x h, le poids est nul (ou, pour le noyau gaussien,
  // inférieur à 0,03 % du poids total) et le voisin n'est pas lu.
  const NOYAUX = {
    bicarre:  { nom: "bicarré",  portee: 1 },
    tricube:  { nom: "tricube",  portee: 1 },
    gaussien: { nom: "gaussien", portee: 4 },
    uniforme: { nom: "uniforme", portee: 1 }
  };
  // noyau gaussien : table de valeurs avec interpolation linéaire, quatre fois plus rapide
  // que Math.exp (écart relatif inférieur à 1e-6)
  const PAS = 16 / 8192, TABLE = Float64Array.from({ length: 8194 }, (_, q) => Math.exp(-0.5 * q * PAS));
  function poidsNoyau(noyau, u2) {
    switch (noyau) {
      case "gaussien": { const z = u2 / PAS, q = z | 0; return q >= 8193 ? 0 : TABLE[q] + (z - q) * (TABLE[q + 1] - TABLE[q]); }
      case "tricube": { if (u2 >= 1) return 0; const v = 1 - u2 * Math.sqrt(u2); return v * v * v; }
      case "uniforme": return u2 <= 1 ? 1 : 0;
      default: { if (u2 >= 1) return 0; const v = 1 - u2; return v * v; }
    }
  }

  // ---------- Grille pour trouver vite les voisins ----------
  function grille(X, Y) {
    const n = X.length;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let i = 0; i < n; i++) { x0 = Math.min(x0, X[i]); x1 = Math.max(x1, X[i]); y0 = Math.min(y0, Y[i]); y1 = Math.max(y1, Y[i]); }
    // environ deux points par cellule
    const cote = Math.max(1e-6, Math.sqrt(((x1 - x0) * (y1 - y0) || 1) / Math.max(1, n / 2)));
    const nx = Math.floor((x1 - x0) / cote) + 1, ny = Math.floor((y1 - y0) / cote) + 1;
    const cel = new Int32Array(n), debut = new Int32Array(nx * ny + 1);
    for (let i = 0; i < n; i++) { cel[i] = Math.floor((X[i] - x0) / cote) + nx * Math.floor((Y[i] - y0) / cote); debut[cel[i] + 1]++; }
    for (let c = 0; c < nx * ny; c++) debut[c + 1] += debut[c];
    const place = debut.slice(0, nx * ny), membres = new Int32Array(n);
    for (let i = 0; i < n; i++) membres[place[cel[i]]++] = i;
    // coordonnées recopiées dans l'ordre des cellules : la lecture des voisins est plus rapide
    const gx = new Float64Array(n), gy = new Float64Array(n);
    for (let q = 0; q < n; q++) { gx[q] = X[membres[q]]; gy[q] = Y[membres[q]]; }
    return { n, x0, y0, cote, nx, ny, debut, membres, gx, gy, idx: new Int32Array(n), d2: new Float64Array(n), tri: new Float64Array(n) };
  }

  // Voisins de (px, py) à moins de R : renvoie leur nombre, rangés dans G.idx (rang dans la grille) et G.d2
  function autour(G, px, py, R) {
    const { cote, nx, debut, gx, gy, idx, d2 } = G;
    const r = Math.ceil(R / cote), cx = Math.floor((px - G.x0) / cote), cy = Math.floor((py - G.y0) / cote), R2 = R * R;
    const xa = Math.max(0, cx - r), xb = Math.min(nx - 1, cx + r), ya = Math.max(0, cy - r), yb = Math.min(G.ny - 1, cy + r);
    let m = 0;
    for (let ly = ya; ly <= yb; ly++) {
      // les cellules d'une même ligne se suivent : un seul intervalle à parcourir
      const q0 = debut[xa + nx * ly], q1 = debut[xb + nx * ly + 1];
      for (let q = q0; q < q1; q++) {
        const dx = gx[q] - px, dy = gy[q] - py, e = dx * dx + dy * dy;
        if (e <= R2) { idx[m] = q; d2[m++] = e; }
      }
    }
    return m;
  }

  // k-ième plus petite valeur de a[0..m-1] (a est modifié)
  function kieme(a, m, k) {
    let g = 0, dr = m - 1;
    while (g < dr) {
      const pivot = a[(g + dr) >> 1];
      let i = g, j = dr;
      while (i <= j) { while (a[i] < pivot) i++; while (a[j] > pivot) j--; if (i <= j) { const t = a[i]; a[i] = a[j]; a[j] = t; i++; j--; } }
      if (k <= j) dr = j; else if (k >= i) g = i; else return a[k];
    }
    return a[k];
  }

  // Distance au k-ième voisin (le point lui-même compte, comme dans GWmodel).
  // R est une première estimation ; les voisins trouvés restent dans G.idx et G.d2.
  function distanceK(G, px, py, k, R) {
    for (;;) {
      const m = autour(G, px, py, R);
      if (m >= k || m === G.n) {
        for (let q = 0; q < m; q++) G.tri[q] = G.d2[q];
        return { h: Math.sqrt(kieme(G.tri, m, Math.min(k, m) - 1)), m, R };
      }
      R *= 1.5;
    }
  }

  // ---------- Le calcul ----------
  // o : { cx, cy : coordonnées (km) ; x, y : valeurs ; p : poids (ou null) ;
  //       noyau ; adaptatif ; k (voisins) ; h (km) ; complet : écarts types et corrélations }
  // Les valeurs manquantes (NaN) sont ignorées et reçoivent NaN en sortie.
  function calculer(o, progres) {
    const N = o.x.length, garde = [];
    for (let i = 0; i < N; i++) if (Number.isFinite(o.x[i]) && Number.isFinite(o.y[i]) && Number.isFinite(o.cx[i]) && Number.isFinite(o.cy[i]) && (!o.p || o.p[i] > 0)) garde.push(i);
    const n = garde.length;
    if (n < 10) return { erreur: "Trop peu de territoires renseignés pour les deux indicateurs." };
    const CX = new Float64Array(n), CY = new Float64Array(n), x = new Float64Array(n), y = new Float64Array(n), P = new Float64Array(n);
    let mx = 0, my = 0, mp = 0;
    garde.forEach((i, q) => { CX[q] = o.cx[i]; CY[q] = o.cy[i]; x[q] = o.x[i]; y[q] = o.y[i]; P[q] = o.p ? o.p[i] : 1; mx += x[q]; my += y[q]; mp += P[q]; });
    mx /= n; my /= n; mp /= n;
    for (let q = 0; q < n; q++) { x[q] -= mx; y[q] -= my; P[q] /= mp; }   // centrer : calcul plus stable

    const noyau = NOYAUX[o.noyau] ? o.noyau : "bicarre", portee = NOYAUX[noyau].portee, G = grille(CX, CY);
    const k = Math.max(2, Math.min(n, Math.round(o.k || 0))), complet = o.complet !== false;
    // valeurs recopiées dans l'ordre de la grille
    const gxv = new Float64Array(n), gyv = new Float64Array(n), gp = new Float64Array(n);
    for (let q = 0; q < n; q++) { const j = G.membres[q]; gxv[q] = x[j]; gyv[q] = y[j]; gp[q] = P[j]; }
    const b = new Float64Array(n).fill(NaN), a = new Float64Array(n).fill(NaN), r = new Float64Array(n).fill(NaN), t = new Float64Array(n).fill(NaN);
    const vb = new Float64Array(n).fill(NaN), hloc = new Float64Array(n), res = new Float64Array(n).fill(NaN);
    let trS = 0, trSS = 0, rss = 0, voisins = 0, echecs = 0;
    const aire = G.nx * G.ny * G.cote * G.cote;
    let Rk = Math.sqrt(aire * k / (Math.PI * n)) + G.cote;

    // on suit l'ordre de la grille : deux territoires successifs sont proches,
    // et la distance au k-ième voisin du précédent est une bonne première estimation
    for (let s = 0; s < n; s++) {
      const i = G.membres[s];
      if (progres && s % 2000 === 0) progres(s / n);
      let h, m;
      if (o.adaptatif) {
        const res = distanceK(G, CX[i], CY[i], k, Rk);
        h = Math.max(1e-9, res.h); m = res.m;
        Rk = Math.max(h * 1.1, 1e-6);
        if (portee * h > res.R) m = autour(G, CX[i], CY[i], portee * h);
      } else { h = o.h; m = autour(G, CX[i], CY[i], portee * h); }
      hloc[i] = h;
      const h2 = h * h, idx = G.idx, d2 = G.d2;
      let S0 = 0, Sx = 0, Sy = 0, Sxx = 0, Sxy = 0, Syy = 0, Q0 = 0, Qx = 0, Qxx = 0, nb = 0;
      for (let q = 0; q < m; q++) {
        const u2 = d2[q] / h2;
        if (u2 > portee * portee) continue;
        const j = idx[q], w = poidsNoyau(noyau, u2) * gp[j];
        if (w <= 0) continue;
        nb++;
        const xj = gxv[j], yj = gyv[j], wx = w * xj;
        S0 += w; Sx += wx; Sy += w * yj; Sxx += wx * xj; Sxy += wx * yj; Syy += w * yj * yj;
        if (complet) { const w2 = w * w; Q0 += w2; Qx += w2 * xj; Qxx += w2 * xj * xj; }
      }
      voisins += nb;
      const det = S0 * Sxx - Sx * Sx;
      if (nb < 3 || !(det > 1e-12 * S0 * S0 * (1 + Sxx / S0))) { echecs++; continue; }
      b[i] = (S0 * Sxy - Sx * Sy) / det;
      a[i] = (Sxx * Sy - Sx * Sxy) / det;
      const e = y[i] - a[i] - b[i] * x[i];
      res[i] = e;
      rss += P[i] * e * e;
      // diagonale du chapeau : S_ii = w_ii x_i' (X'WX)^-1 x_i, avec w_ii = K(0) p_i = p_i
      const u0 = (Sxx - Sx * x[i]) / det, u1 = (S0 * x[i] - Sx) / det;
      trS += P[i] * (u0 + u1 * x[i]);
      if (complet) {
        trSS += Q0 * u0 * u0 + 2 * Qx * u0 * u1 + Qxx * u1 * u1;   // somme des S_ij² sur la ligne i
        const g0 = -Sx / det, g1 = S0 / det;
        vb[i] = Q0 * g0 * g0 + 2 * Qx * g0 * g1 + Qxx * g1 * g1;     // [(X'WX)^-1 X'W²X (X'WX)^-1]_22
        const cxy = Sxy / S0 - (Sx / S0) * (Sy / S0), vx = Sxx / S0 - (Sx / S0) ** 2, vy = Syy / S0 - (Sy / S0) ** 2;
        r[i] = vx > 0 && vy > 0 ? Math.max(-1, Math.min(1, cxy / Math.sqrt(vx * vy))) : NaN;
      }
    }
    const ne = n - echecs;
    const aicc = ne * Math.log(rss / ne) + ne * Math.log(2 * Math.PI) + ne * (ne + trS) / (ne - 2 - trS);
    const sortie = { n: ne, trS, aicc: ne - 2 - trS > 0 ? aicc : Infinity, rss, voisins: voisins / Math.max(1, ne), hMoyen: hloc.reduce((s, v) => s + v, 0) / n, echecs };
    if (!complet) return sortie;

    // écarts types locaux de la pente
    const ddl = ne - 2 * trS + trSS, sigma2 = rss / ddl;
    for (let i = 0; i < n; i++) if (Number.isFinite(b[i])) t[i] = b[i] / Math.sqrt(sigma2 * vb[i]);
    // seuil de significativité corrigé des tests multiples (da Silva et Fotheringham, 2016)
    const alpha = 0.05 * Math.min(1, 2 / trS);
    const tCritique = quantileNormal(1 - alpha / 2);

    // modèle global (moindres carrés pondérés par p), pour comparer
    let S0 = 0, Sx = 0, Sy = 0, Sxx = 0, Sxy = 0, Syy = 0;
    for (let i = 0; i < n; i++) { const w = P[i]; S0 += w; Sx += w * x[i]; Sy += w * y[i]; Sxx += w * x[i] * x[i]; Sxy += w * x[i] * y[i]; Syy += w * y[i] * y[i]; }
    const cxy = Sxy / S0 - Sx * Sy / S0 / S0, vx = Sxx / S0 - (Sx / S0) ** 2, vy = Syy / S0 - (Sy / S0) ** 2;
    const bg = cxy / vx, ag = Sy / S0 - bg * Sx / S0;
    let rssG = 0;
    for (let i = 0; i < n; i++) { const e = y[i] - ag - bg * x[i]; rssG += P[i] * e * e; }
    const aiccG = n * Math.log(rssG / n) + n * Math.log(2 * Math.PI) + n * (n + 2) / (n - 4);

    // remettre les sorties dans l'ordre des territoires de départ
    const remettre = v => { const s = new Float64Array(N).fill(NaN); garde.forEach((i, q) => s[i] = v[q]); return s; };
    for (let q = 0; q < n; q++) if (Number.isFinite(a[q])) a[q] = a[q] + my - b[q] * mx;   // ordonnée à l'origine dans les unités d'origine
    const r2 = r.map(v => v * v);
    let positifs = 0, negatifs = 0;
    for (let q = 0; q < n; q++) { if (t[q] >= tCritique) positifs++; else if (t[q] <= -tCritique) negatifs++; }
    return Object.assign(sortie, {
      b: remettre(b), a: remettre(a), r: remettre(r), r2: remettre(r2), t: remettre(t), h: remettre(hloc), e: remettre(res),
      trSS, sigma2, tCritique, alpha, positifs, negatifs,
      global: { b: bg, a: ag + my - bg * mx, r: cxy / Math.sqrt(vx * vy), aicc: aiccG, rss: rssG }
    });
  }

  // ---------- Largeur de bande optimale (AICc minimal, section dorée) ----------
  function optimiser(o, progres) {
    const n = o.x.filter((v, i) => Number.isFinite(v) && Number.isFinite(o.y[i])).length;
    const crit = v => calculer(Object.assign({}, o, o.adaptatif ? { k: Math.round(v) } : { h: v }, { complet: false })).aicc;
    // bornes : de quelques voisins à une large part du territoire
    let g = o.adaptatif ? Math.min(n - 1, Math.max(10, o.noyau === "gaussien" ? 6 : 12)) : o.hMin || 3;
    // le noyau gaussien lit beaucoup plus de voisins : on borne la recherche plus bas
    let d = o.adaptatif ? Math.min(n - 1, o.noyau === "gaussien" ? 1500 : 3000) : o.hMax || 400;
    const or = (Math.sqrt(5) - 1) / 2, cache = new Map(), essais = [];
    const f = v => { const c = o.adaptatif ? Math.round(v) : +v.toPrecision(4); if (!cache.has(c)) { const s = crit(c); cache.set(c, s); essais.push([c, s]); } return cache.get(c); };
    // on cherche sur l'échelle logarithmique : les petites largeurs sont les plus sensibles
    let lg = Math.log(g), ld = Math.log(d), l1 = ld - or * (ld - lg), l2 = lg + or * (ld - lg), f1 = f(Math.exp(l1)), f2 = f(Math.exp(l2)), etape = 0;
    while (ld - lg > (o.adaptatif ? 0.01 : 0.005) && etape < 40) {
      if (progres) progres(Math.min(0.99, etape / 22));
      if (f1 < f2) { ld = l2; l2 = l1; f2 = f1; l1 = ld - or * (ld - lg); f1 = f(Math.exp(l1)); }
      else { lg = l1; l1 = l2; f1 = f2; l2 = lg + or * (ld - lg); f2 = f(Math.exp(l2)); }
      etape++;
      if (o.adaptatif && Math.round(Math.exp(ld)) - Math.round(Math.exp(lg)) <= 1) break;
    }
    let meilleur = null;
    for (const [c, s] of cache) if (meilleur === null || s < meilleur[1]) meilleur = [c, s];
    essais.sort((p, q) => p[0] - q[0]);
    return { valeur: meilleur[0], aicc: meilleur[1], essais };
  }

  // Quantile de la loi normale (Acklam), assez précis pour les seuils de test
  function quantileNormal(p) {
    const a = [-39.6968302866538, 220.946098424521, -275.928510446969, 138.357751867269, -30.6647980661472, 2.50662827745924];
    const b = [-54.4760987982241, 161.585836858041, -155.698979859887, 66.8013118877197, -13.2806815528857];
    const c = [-0.00778489400243029, -0.322396458041136, -2.40075827716184, -2.54973253934373, 4.37466414146497, 2.93816398269878];
    const d = [0.00778469570904146, 0.32246712907004, 2.445134137143, 3.75440866190742];
    const pl = 0.02425;
    if (p < pl) { const q = Math.sqrt(-2 * Math.log(p)); return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1); }
    if (p > 1 - pl) return -quantileNormal(1 - p);
    const q = p - 0.5, r = q * q;
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  }

  return { NOYAUX, calculer, optimiser, quantileNormal, outils: { grille, autour, distanceK, poidsNoyau } };
})();

// ---------- Dans un Web Worker ----------
if (typeof self !== "undefined" && typeof window === "undefined" && typeof importScripts === "function") {
  self.onmessage = e => {
    const { id, quoi, o } = e.data;
    const progres = p => self.postMessage({ id, progres: p });
    try {
      if (quoi === "optimiser") {
        const opt = GWR.optimiser(o, progres);
        o[o.adaptatif ? "k" : "h"] = opt.valeur;
        self.postMessage({ id, opt, res: GWR.calculer(o, progres) });
      } else self.postMessage({ id, res: GWR.calculer(o, progres) });
    } catch (err) { self.postMessage({ id, res: { erreur: String(err) } }); }
  };
}
if (typeof module !== "undefined") module.exports = GWR;