#!/usr/bin/env node
// Le catalogue des traductions de Kiwio (`Partage/Localizable.xcstrings`).
//
// Les clés du catalogue SONT les textes français tels que le compilateur les
// voit (`Text("Il te reste \(n) kcal")` → « Il te reste %lld kcal »). Pas de
// Xcode sur le poste de travail : c'est la CI (workflow `localisation.yml`)
// qui relève ces clés dans les fichiers `.stringsdata` du build.
//
//   node scripts/localisation/catalogue.mjs construire \
//       --traductions <dossier de .json> --extraits <dossier de .stringsdata>
//     Ajoute au catalogue l'anglais des clés qui n'en ont pas encore, à partir
//     de fichiers { "traductions": [{ "fr": "Il te reste {1} kcal", "en": "{1} kcal left" }] }.
//     Les `{n}` deviennent les spécificateurs exacts de la clé (%lld, %@…).
//     Un texte sans clé extraite (libellé passé à `Langue.texte`) entre tel quel.
//     Les traductions déjà présentes dans le catalogue ne sont jamais écrasées.
//
//   node scripts/localisation/catalogue.mjs verifier --extraits <dossier> [--rapport f.json]
//     Liste les clés extraites qui n'ont pas d'anglais. Ne modifie rien.

import fs from "node:fs";
import path from "node:path";

const CATALOGUE = "Partage/Localizable.xcstrings";
const SPEC = /%(?:(\d+)\$)?[-+0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]|%%/g;

function args() {
  const [commande, ...reste] = process.argv.slice(2);
  const opts = {};
  for (let i = 0; i < reste.length; i += 2) opts[reste[i].replace(/^--/, "")] = reste[i + 1];
  return { commande, opts };
}

// ── Clés extraites par le compilateur ────────────────────────────────────────
function lireExtraits(dossier) {
  const cles = new Map(); // clé → fichier source
  if (!dossier || !fs.existsSync(dossier)) return cles;
  for (const nom of fs.readdirSync(dossier)) {
    if (!nom.endsWith(".stringsdata")) continue;
    let json;
    try { json = JSON.parse(fs.readFileSync(path.join(dossier, nom), "utf8")); } catch { continue; }
    const source = (json.source || nom).split("/").slice(-2).join("/");
    const tables = json.tables || {};
    for (const [table, entrees] of Object.entries(tables)) {
      if (table !== "Localizable") continue;
      for (const e of entrees || []) if (typeof e.key === "string") cles.set(e.key, source);
    }
  }
  return cles;
}

// « Il te reste %lld kcal sur %2$lld » → { gabarit: "Il te reste {1} kcal sur {2}", specs: ["%lld", "%lld"] }
function decomposer(cle) {
  const specs = [];
  let rang = 0;
  const gabarit = cle.replace(SPEC, (m, pos) => {
    if (m === "%%") return "%";
    const n = pos ? Number(pos) : ++rang;
    specs[n - 1] = m.replace(/^%\d+\$/, "%");
    return `{${n}}`;
  });
  return { gabarit, specs, formate: specs.length > 0 };
}

const souple = (t) => t.replace(/[’‘]/g, "'").replace(/[  ]/g, " ").replace(/\s+/g, " ").trim();

// L'anglais d'un agent ({1}, {2}) → la valeur du catalogue (%lld, %1$@…).
function recomposer(en, specs, formate) {
  if (!formate) return en;
  const ordre = [...en.matchAll(/\{(\d+)\}/g)].map((m) => Number(m[1]));
  const sequentiel = ordre.every((n, i) => n === i + 1) && ordre.length === specs.length;
  let v = en.replace(/%/g, "%%");
  v = v.replace(/\{(\d+)\}/g, (_, n) => {
    const s = specs[Number(n) - 1] || "%@";
    return sequentiel ? s : `%${n}$${s.slice(1)}`;
  });
  return v;
}

function lireTraductions(dossier) {
  const parFr = new Map();
  const liste = [];
  parFr.liste = liste;
  if (!dossier) return parFr;
  for (const nom of fs.readdirSync(dossier).filter((n) => n.endsWith(".json")).sort()) {
    const json = JSON.parse(fs.readFileSync(path.join(dossier, nom), "utf8"));
    for (const t of json.traductions || []) {
      if (typeof t.fr !== "string" || typeof t.en !== "string" || !t.en.trim()) continue;
      if (!parFr.has(t.fr)) { parFr.set(t.fr, t.en); liste.push([t.fr, t.en]); }
      if (!parFr.has(souple(t.fr))) parFr.set(souple(t.fr), t.en);
    }
  }
  return parFr;
}

function lireCatalogue() {
  if (!fs.existsSync(CATALOGUE)) return { sourceLanguage: "fr", strings: {}, version: "1.0" };
  return JSON.parse(fs.readFileSync(CATALOGUE, "utf8"));
}

function ecrireCatalogue(cat) {
  const tri = {};
  for (const k of Object.keys(cat.strings).sort()) tri[k] = cat.strings[k];
  cat.strings = tri;
  fs.writeFileSync(CATALOGUE, JSON.stringify(cat, null, 2).replace(/": /g, '" : ') + "\n");
}

const aDesLettres = (t) => /\p{L}{2,}/u.test(t.replace(SPEC, ""));
const anglaisDe = (entree) => entree?.localizations?.en?.stringUnit?.value;

function construire(opts) {
  const cat = lireCatalogue();
  const extraits = lireExtraits(opts.extraits);
  const traductions = lireTraductions(opts.traductions);
  const utilisees = new Set();
  let ajoutees = 0;

  for (const cle of extraits.keys()) {
    const entree = (cat.strings[cle] ||= {});
    if (anglaisDe(entree) !== undefined) continue;
    const { gabarit, specs, formate } = decomposer(cle);
    const en = traductions.get(gabarit) ?? traductions.get(souple(gabarit));
    if (en === undefined) continue;
    utilisees.add(gabarit); utilisees.add(souple(gabarit));
    entree.localizations = { en: { stringUnit: { state: "translated", value: recomposer(en, specs, formate) } } };
    ajoutees++;
  }
  // Libellés connus seulement à l'exécution (`Langue.texte`) : clé = texte français.
  let manuelles = 0;
  for (const [fr, en] of traductions.liste) {
    if (utilisees.has(fr) || utilisees.has(souple(fr)) || /\{\d+\}/.test(fr)) continue;
    if (extraits.has(fr)) continue;
    if (cat.strings[fr] && anglaisDe(cat.strings[fr]) !== undefined) continue;
    cat.strings[fr] = { extractionState: "manual", localizations: { en: { stringUnit: { state: "translated", value: en } } } };
    manuelles++;
  }
  ecrireCatalogue(cat);
  console.log(`Catalogue : ${Object.keys(cat.strings).length} clés, ${ajoutees} traductions ajoutées sur des clés extraites, ${manuelles} libellés manuels.`);
  verifier(opts);
}

function verifier(opts) {
  const cat = lireCatalogue();
  const extraits = lireExtraits(opts.extraits);
  const manquants = [];
  for (const [cle, source] of extraits) {
    if (!aDesLettres(cle)) continue;
    if (anglaisDe(cat.strings[cle]) === undefined) manquants.push({ cle, source });
  }
  const total = [...extraits.keys()].filter(aDesLettres).length;
  console.log(`\n### Traduction anglaise\n\n${total - manquants.length} / ${total} textes repérés par le compilateur ont leur anglais.`);
  if (manquants.length) {
    console.log(`\n${manquants.length} sans anglais (ils s'afficheront en français) :\n`);
    for (const m of manquants.slice(0, 200)) console.log(`- \`${m.source}\` : ${m.cle.replace(/\n/g, "⏎")}`);
    if (manquants.length > 200) console.log(`- … et ${manquants.length - 200} autres (voir manquants.json)`);
  }
  if (opts.rapport) fs.writeFileSync(opts.rapport, JSON.stringify(manquants, null, 2));
}

const { commande, opts } = args();
if (commande === "construire") construire(opts);
else if (commande === "verifier") verifier(opts);
else { console.error("usage : catalogue.mjs construire|verifier [--traductions d] [--extraits d] [--rapport f]"); process.exit(2); }
