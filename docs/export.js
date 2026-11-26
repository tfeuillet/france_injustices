// ------------------------------------------------------------------
// Export de la carte affichée en image (PNG) ou en PDF (A4 paysage).
// La carte est redessinée proprement, sans le fond de carte (droits et qualité
// d'impression), avec son titre, sa légende, l'encart parisien et la source.
// ------------------------------------------------------------------

const EXPORT = { L: 3300, H: 2334, marge: 70 };

// Projection de Mercator, comme la carte à l'écran
const merc = (lon, lat) => [lon * Math.PI / 180, Math.log(Math.tan(Math.PI / 4 + lat * Math.PI / 360))];

function cadreur(bbox, x, y, l, h) {
  const [a0, b0] = merc(bbox[0], bbox[1]), [a1, b1] = merc(bbox[2], bbox[3]);
  const e = Math.min(l / (a1 - a0), h / (b1 - b0)), dx = x + (l - e * (a1 - a0)) / 2, dy = y + (h - e * (b1 - b0)) / 2;
  return (lon, lat) => { const [a, b] = merc(lon, lat); return [dx + e * (a - a0), dy + e * (b1 - b)]; };
}

function tracer(ctx, geom, proj) {
  const polys = geom.type === "Polygon" ? [geom.coordinates] : geom.type === "MultiPolygon" ? geom.coordinates : [];
  for (const p of polys) for (const anneau of p) anneau.forEach((c, k) => { const [x, y] = proj(c[0], c[1]); k ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
  const lignes = geom.type === "LineString" ? [geom.coordinates] : geom.type === "MultiLineString" ? geom.coordinates : [];
  for (const l of lignes) l.forEach((c, k) => { const [x, y] = proj(c[0], c[1]); k ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
}

function dessinerUnites(ctx, features, indice, proj, epaisseur, contourBlanc) {
  for (const f of features) {
    const i = indice(f), c = i === undefined ? MANQUE : couleurActuelle(i);
    ctx.beginPath(); tracer(ctx, f.geometry, proj);
    ctx.fillStyle = c; ctx.fill("evenodd");
    ctx.strokeStyle = "rgba(138,138,138,0.6)"; ctx.lineWidth = epaisseur; ctx.stroke();
  }
}

function bboxDe(features) {
  const b = [Infinity, Infinity, -Infinity, -Infinity];
  const voir = c => { b[0] = Math.min(b[0], c[0]); b[1] = Math.min(b[1], c[1]); b[2] = Math.max(b[2], c[0]); b[3] = Math.max(b[3], c[1]); };
  for (const f of features) {
    const g = f.geometry, polys = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
    for (const p of polys) for (const a of p) a.forEach(voir);
  }
  return b;
}

// Texte sur plusieurs lignes, coupé à la largeur donnée ; renvoie l'ordonnée suivante
// hauteur qu'occuperait un texte, sans l'écrire
function hauteurTexte(ctx, texte, largeur, interligne) {
  let n = 0, ligne = "";
  for (const m of String(texte).split(/\s+/)) { const e = ligne ? ligne + " " + m : m; if (ctx.measureText(e).width > largeur && ligne) { n++; ligne = m; } else ligne = e; }
  return (n + (ligne ? 1 : 0)) * interligne;
}
function ecrire(ctx, texte, x, y, largeur, interligne) {
  const mots = String(texte).split(/\s+/);
  let ligne = "";
  for (const m of mots) {
    const essai = ligne ? ligne + " " + m : m;
    if (ctx.measureText(essai).width > largeur && ligne) { ctx.fillText(ligne, x, y); y += interligne; ligne = m; }
    else ligne = essai;
  }
  if (ligne) { ctx.fillText(ligne, x, y); y += interligne; }
  return y;
}

// La légende est recopiée depuis celle de la page : titre, barres de couleurs, bornes, cases et notes
function dessinerLegende(ctx, x, y, largeur) {
  const L_ = document.getElementById("legende"), police = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";
  for (const el of L_.children) {
    if (el.tagName === "B") { ctx.font = `600 40px ${police}`; ctx.fillStyle = "#222"; y = ecrire(ctx, el.textContent, x, y + 40, largeur, 48) - 8; }
    else if (el.classList.contains("barre")) {
      const cases = [...el.children], l = largeur / cases.length;
      cases.forEach((c, k) => {
        ctx.fillStyle = getComputedStyle(c).backgroundColor; ctx.fillRect(x + k * l, y + 10, l + 0.5, 44);
        if (c.textContent.trim()) { ctx.fillStyle = getComputedStyle(c).color; ctx.font = `30px ${police}`; ctx.textAlign = "center"; ctx.fillText(c.textContent, x + (k + 0.5) * l, y + 43); ctx.textAlign = "left"; }
      });
      y += 60;
    } else if (el.classList.contains("bornes")) {
      const t = [...el.children]; ctx.font = `30px ${police}`; ctx.fillStyle = "#555";
      t.forEach((s, k) => { ctx.textAlign = t.length === 1 ? "left" : k === 0 ? "left" : k === t.length - 1 ? "right" : "center"; ctx.fillText(s.textContent, x + (t.length === 1 ? 0 : k * largeur / (t.length - 1)), y + 32); });
      ctx.textAlign = "left"; y += 46;
    } else if (el.querySelector && el.querySelector("span[style*='background']") && !el.classList.contains("petit")) {
      const s = el.querySelector("span[style*='background']");
      ctx.fillStyle = getComputedStyle(s).backgroundColor; ctx.fillRect(x, y + 12, 34, 30);
      ctx.font = `32px ${police}`; ctx.fillStyle = "#222"; y = ecrire(ctx, el.textContent.trim(), x + 48, y + 38, largeur - 48, 38) + 4;
    } else { ctx.font = `28px ${police}`; ctx.fillStyle = "#666"; y = ecrire(ctx, el.textContent.trim(), x, y + 36, largeur, 34) + 4; }
  }
  return y;
}

async function exporterCarte(format) {
  const { L: W, H, marge } = EXPORT, police = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";
  const cv = document.createElement("canvas"); cv.width = W; cv.height = H;
  const ctx = cv.getContext("2d");
  ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, H);
  // titre et précisions, repris du cartouche
  const lignes = document.getElementById("cartouche").innerText.split("\n").map(t => t.trim()).filter(Boolean);
  const pied = lignes.slice(-3), details = lignes.slice(1, -3);
  ctx.fillStyle = "#222"; ctx.font = `600 62px Georgia, serif`; ctx.fillText(lignes[0] || "", marge, marge + 52);
  ctx.font = `34px ${police}`; ctx.fillStyle = "#555";
  let y = marge + 110;
  for (const t of details) y = ecrire(ctx, t, marge, y, W - 2 * marge, 42);
  // carte principale
  const haut = Math.max(y + 10, 230), colonne = 900, largeurCarte = W - 3 * marge - colonne, hauteurCarte = H - haut - 130;
  // supra : intercommunalités, bassins de vie ou zones d'emploi (sans encart parisien)
  const supra = echelle !== "commune", rang = new Map(U.code.map((c, k) => [c, k]));
  const features = geo[echelle].features, indice = supra ? f => rang.get(f.properties.code) : f => f.properties.i;
  const proj = cadreur(bboxDe(features), marge, haut, largeurCarte, hauteurCarte);
  dessinerUnites(ctx, features, indice, proj, supra ? 1.2 : 0.6, supra);
  if (geoDep) { ctx.beginPath(); for (const f of geoDep.features) tracer(ctx, f.geometry, proj); ctx.strokeStyle = "rgba(60,60,60,0.6)"; ctx.lineWidth = 1.8; ctx.stroke(); }
  // colonne de droite : légende, puis encart parisien (communes seulement)
  const xc = W - marge - colonne;
  let yl = dessinerLegende(ctx, xc, haut, colonne);
  // logo de Solagro sous la légende, exigé quand la carte utilise les données Adonis (fichier solagro.png à côté de la page)
  if (typeof utiliseIft === "function" && utiliseIft()) {
    const logo = await new Promise(ok => { const im = new Image(); im.onload = () => ok(im); im.onerror = () => ok(null); im.src = ADONIS.logo; });
    if (logo) { const h = 110, w = Math.min(colonne, h * logo.width / logo.height); ctx.drawImage(logo, xc, yl + 40, w, w * logo.height / logo.width); yl += 40 + w * logo.height / logo.width; }
  }
  const limite = supra ? H - 160 : H - 130 - 560;
  // les dix plus grandes villes, classées (onglet Cumul), sous la légende
  const v = typeof villesExport === "function" ? villesExport() : null;
  if (v && v.lignes.length && yl + 110 + 42 * v.lignes.length < limite) {
    ctx.fillStyle = "#8c3b1c"; ctx.font = `600 30px ${police}`;
    yl = ecrire(ctx, v.titre.toUpperCase(), xc, yl + 70, colonne, 38);
    ctx.fillStyle = "#666"; ctx.font = `26px ${police}`;
    yl = ecrire(ctx, "Classement, " + v.note, xc, yl + 6, colonne, 32);
    yl += 14;
    v.lignes.forEach((l, k) => {
      const y = yl + 42 * k + 30;
      ctx.fillStyle = "#666"; ctx.font = `28px ${police}`; ctx.textAlign = "right"; ctx.fillText(String(k + 1), xc + 34, y);
      ctx.textAlign = "left"; ctx.fillStyle = "#222"; ctx.fillText(l.nom, xc + 54, y);
      ctx.fillStyle = l.couleur; ctx.fillRect(xc + colonne - 130, y - 22, 24, 24);
      ctx.fillStyle = "#222"; ctx.textAlign = "right"; ctx.fillText(l.valeur, xc + colonne, y); ctx.textAlign = "left";
    });
    yl += 42 * v.lignes.length + 10;
  }
  // graphique en déciles (Cumul, Double peine), sous la légende, s'il reste la place
  const g = typeof grapheActuel === "function" ? grapheActuel() : null;
  if (g) {
    const hG = Math.round(colonne * 178 / 340);
    ctx.font = `600 30px ${police}`;
    const hTitre = hauteurTexte(ctx, g.titre.toUpperCase(), colonne, 38);
    if (yl + 50 + hTitre + hG < limite) {
      const svg = g.svg.replace('width="100%"', `width="${colonne}" height="${hG}"`).replace(/ style="[^"]*"/, "");
      const image = await new Promise(ok => { const im = new Image(); im.onload = () => ok(im); im.onerror = () => ok(null); im.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(svg); });
      if (image) {
        ctx.fillStyle = "#8c3b1c"; yl = ecrire(ctx, g.titre.toUpperCase(), xc, yl + 70, colonne, 38);
        ctx.drawImage(image, xc, yl - 10, colonne, hG); yl += hG - 10;
      }
    }
  }
  // résumé de la lecture de la carte, sous la légende ; à l'échelle communale, on garde de la place pour l'encart
  const resume = typeof resumeCarte === "function" ? resumeCarte() : "";
  if (resume) {
    ctx.fillStyle = "#8c3b1c"; ctx.font = `600 30px ${police}`;
    if (yl + 90 < limite) { ctx.fillText("CE QUE DIT LA CARTE", xc, yl + 70); yl += 90; }
    ctx.fillStyle = "#333"; ctx.font = `29px ${police}`;
    // on garde autant de phrases entières que la place le permet
    const phrases = resume.match(/[^.!?]+[.!?]+(\s|$)|[^.!?]+$/g) || [resume];
    let texte = "";
    for (const ph of phrases) {
      const essai = (texte + " " + ph.trim()).trim();
      if (yl + hauteurTexte(ctx, essai, colonne, 39) > limite) break;
      texte = essai;
    }
    if (texte) yl = ecrire(ctx, texte, xc, yl + 30, colonne, 39);
  }
  if (!supra) {
    const idf = geoCommunes.features.filter(f => ["75", "92", "93", "94"].includes(D.communes.dep[f.properties.i]));
    if (idf.length) {
      const yE = Math.max(yl + 50, H - 130 - 760), hE = Math.min(760, H - 130 - yE);
      ctx.strokeStyle = "#999"; ctx.lineWidth = 2; ctx.strokeRect(xc, yE, colonne, hE);
      const pE = cadreur(bboxDe(idf), xc + 10, yE + 60, colonne - 20, hE - 70);
      dessinerUnites(ctx, idf, f => f.properties.i, pE, 1.2, false);
      if (geoDep) { ctx.save(); ctx.beginPath(); ctx.rect(xc, yE, colonne, hE); ctx.clip(); ctx.beginPath(); for (const f of geoDep.features) tracer(ctx, f.geometry, pE); ctx.strokeStyle = "rgba(60,60,60,0.6)"; ctx.lineWidth = 2.4; ctx.stroke(); ctx.restore(); }
      ctx.fillStyle = "#222"; ctx.font = `30px ${police}`; ctx.fillText("Paris et petite couronne", xc + 14, yE + 40);
    }
  }
  // pied : date des données, auteur, adresse de l'outil
  ctx.fillStyle = "#555"; ctx.font = `28px ${police}`;
  ctx.fillText(pied.join("  ·  "), marge, H - marge + 10);
  const nom = "injustices_" + (mode === "cumul" ? vue.replace(":", "_") : mode) + "_" + echelle;
  if (format === "pdf") {
    if (!window.jspdf) await new Promise((ok, ko) => { const s = document.createElement("script"); s.src = JSPDF; s.onload = ok; s.onerror = ko; document.head.appendChild(s); });
    const doc = new window.jspdf.jsPDF({ orientation: "landscape", unit: "mm", format: "a4" });
    doc.addImage(cv.toDataURL("image/jpeg", 0.92), "JPEG", 0, 0, 297, 210);
    doc.save(nom + ".pdf");
  } else {
    cv.toBlob(b => { const a = document.createElement("a"); a.href = URL.createObjectURL(b); a.download = nom + ".png"; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000); }, "image/png");
  }
}
const JSPDF = "https://unpkg.com/jspdf@2.5.1/dist/jspdf.umd.min.js";

// ------------------------------------------------------------------
// Export de la fiche d'un territoire en image (PNG). La fiche affichée est relue
// (en-tête, lignes du tableau avec leurs pastilles de couleur, notes), puis redessinée
// avec la jauge du score cumulé et la source, comme sur l'export de la carte.
// ------------------------------------------------------------------
function exporterFiche() {
  const f = document.getElementById("fiche");
  if (!f || f.style.display === "none") return;
  const police = "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif";
  const E = 2, W = 760, m = 32, valeurX = W - m - 26;          // E : échelle (image nette sur écran haute définition)
  const cv = document.createElement("canvas"); cv.width = W * E; cv.height = 4000 * E;
  const ctx = cv.getContext("2d"); ctx.scale(E, E);
  ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, W, 4000);
  ctx.textBaseline = "alphabetic";
  const copie = f.cloneNode(true);
  copie.querySelectorAll(".fermer, .exporter-fiche, svg, .jauge").forEach(e => e.remove());
  const table = copie.querySelector("table");
  const apres = [];
  if (table) { let n = table.nextSibling; while (n) { apres.push(n); n = n.nextSibling; } apres.forEach(n => n.remove()); table.remove(); }
  // en-tête : nom du territoire en gras, puis les lignes de texte
  const lignes = copie.innerText.split("\n").map(t => t.trim()).filter(t => t && !t.startsWith("Cliquer pour"));
  let y = m + 28;
  const premiere = lignes.shift() || "", [nom, ...reste] = premiere.split(" · ");
  ctx.fillStyle = "#222"; ctx.font = `600 27px Georgia, serif`; ctx.fillText(nom, m, y);
  const lNom = ctx.measureText(nom).width;
  ctx.font = `17px ${police}`; ctx.fillStyle = "#555"; if (reste.length) ctx.fillText(" · " + reste.join(" · "), m + lNom, y);
  // jauge et visage du score cumulé, en haut à droite
  const s = mode === "cumul" && epingle && res && res.score ? res.score[epingle.i] : NaN;
  if (Number.isFinite(s)) {
    const xg = W - m - 150, yg = m + 10, lg = 110;
    const grad = ctx.createLinearGradient(xg, 0, xg + lg, 0); COULEURS.forEach((c, k) => grad.addColorStop(k / 9, c));
    ctx.fillStyle = grad; ctx.beginPath(); ctx.roundRect(xg, yg, lg, 12, 6); ctx.fill();
    ctx.fillStyle = "#222"; ctx.fillRect(xg + s * lg - 2.5, yg - 5, 5, 22);
    const cx = W - m - 16, cy = yg + 6, c = couleur(s), trait = s < 0.2 || s >= 0.8 ? "#fff" : "#222";
    ctx.fillStyle = c; ctx.strokeStyle = "#333"; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.arc(cx, cy, 15, 0, 2 * Math.PI); ctx.fill(); ctx.stroke();
    ctx.fillStyle = trait; for (const dx of [-5, 5]) { ctx.beginPath(); ctx.arc(cx + dx, cy - 3.5, 2, 0, 2 * Math.PI); ctx.fill(); }
    const k = 15 / 12, coin = cy + (15.5 - 2 * (0.5 - s) - 12) * k, bouche = cy + (16.5 + 7 * (0.5 - s) - 12) * k;
    ctx.strokeStyle = trait; ctx.lineWidth = 2.2; ctx.lineCap = "round"; ctx.beginPath(); ctx.moveTo(cx - 6.5, coin); ctx.quadraticCurveTo(cx, bouche, cx + 6.5, coin); ctx.stroke();
  }
  y += 14;
  ctx.font = `17px ${police}`; ctx.fillStyle = "#333";
  for (const t of lignes) y = ecrire(ctx, t, m, y + 22, W - 2 * m, 24) - 22;
  y += 14;
  // tableau : une ligne par territoire, indicateur ou dimension
  const carre = (x, yy, coul) => { ctx.fillStyle = coul; ctx.fillRect(x, yy - 12, 13, 13); };
  if (table) for (const tr of table.querySelectorAll("tr")) {
    const tds = [...tr.querySelectorAll("td")];
    if (!tds.length) continue;
    if (tr.querySelector("hr")) { ctx.strokeStyle = "#ddd"; ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(m, y + 8); ctx.lineTo(W - m, y + 8); ctx.stroke(); y += 14; continue; }
    const gras = !!tds[0].querySelector("b"), retrait = Math.round(1.8 * (parseInt(tds[0].style.paddingLeft) || 0)), petit = tr.classList.contains("petit");
    const pastille = tds[0].querySelector("span[style*=background]");
    const corps = petit ? 15 : 17;
    ctx.font = `${gras ? "600 " : ""}${corps}px ${police}`; ctx.fillStyle = petit ? "#666" : "#222";
    let x = m + retrait;
    if (pastille) { carre(x, y + 24, pastille.style.background || pastille.style.backgroundColor); x += 20; }
    const valeurs = tds.slice(1).filter(td => td.innerText.trim() !== "■");
    const couleurCase = tds.slice(1).find(td => td.innerText.trim() === "■");
    const v = valeurs.map(td => td.innerText.replace(/\s+/g, " ").trim()).join(" ");
    ctx.font = `${corps}px ${police}`; const lv = ctx.measureText(v).width;
    ctx.font = `${gras ? "600 " : ""}${corps}px ${police}`;
    const largeur = tds.length === 1 || tds[0].colSpan > 1 ? W - m - x : Math.max(160, valeurX - x - lv - 16);
    const yFin = ecrire(ctx, tds[0].innerText.replace(/\s+/g, " ").trim(), x, y + 24, largeur, 22);
    if (v) { ctx.font = `${corps}px ${police}`; ctx.fillStyle = petit ? "#666" : "#333"; ctx.textAlign = "right"; ctx.fillText(v, valeurX, y + 24); ctx.textAlign = "left"; }
    if (couleurCase) carre(W - m - 13, y + 24, couleurCase.style.color);
    y = yFin - 24 + 8;
  }
  // notes et classe (double peine, concentrations), sous le tableau
  for (const n of apres) {
    const t = (n.innerText || n.textContent || "").replace(/\s+/g, " ").trim();
    if (!t || t.startsWith("Cliquer pour")) continue;
    const pastille = n.querySelector && n.querySelector("span[style*=background]");
    let x = m;
    if (pastille) { carre(x, y + 26, pastille.style.background || pastille.style.backgroundColor); x += 20; }
    ctx.font = `${n.classList && n.classList.contains("petit") ? 14 : 17}px ${police}`; ctx.fillStyle = n.classList && n.classList.contains("petit") ? "#666" : "#222";
    y = ecrire(ctx, t, x, y + 26, W - m - x, 20) - 18;
  }
  // source : titre de la carte, date des données, auteur, adresse
  const cart = document.getElementById("cartouche").innerText.split("\n").map(t => t.trim()).filter(Boolean);
  y += 30; ctx.strokeStyle = "#ddd"; ctx.beginPath(); ctx.moveTo(m, y); ctx.lineTo(W - m, y); ctx.stroke();
  ctx.font = `14px ${police}`; ctx.fillStyle = "#666";
  y += 22;
  for (const t of [cart[0], N().par, ...cart.slice(-3)].filter(Boolean)) y = ecrire(ctx, t, m, y, W - 2 * m, 19);
  const H = y + m - 10;
  const sortie = document.createElement("canvas"); sortie.width = W * E; sortie.height = Math.ceil(H * E);
  sortie.getContext("2d").drawImage(cv, 0, 0);
  const nomFichier = "fiche_" + (U.nom[epingle ? epingle.i : 0] || "territoire").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^A-Za-z0-9]+/g, "_").replace(/^_|_$/g, "");
  sortie.toBlob(b => { const a = document.createElement("a"); a.href = URL.createObjectURL(b); a.download = nomFichier + ".png"; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000); }, "image/png");
}