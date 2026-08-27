# Kiwio — Publicité SaaS (Seedance / Higgsfield)

> Pack de production pour la vidéo publicitaire Kiwio destinée à **LinkedIn** et **Instagram**.
> Style : SaaS marketing video, montage dynamique, présentation des features et de l'app.
> Créé le 27 août 2026.

---

## ⛔ Statut : prompts prêts, génération NON lancée

La génération Seedance n'a pas pu être exécutée depuis la session Claude Code (web). Deux
blocages indépendants, tous les deux côté accès, aucun côté créa :

| # | Blocage | Détail |
|---|---------|--------|
| 1 | **Clés API inutilisables depuis cette session** | L'egress proxy de l'environnement refuse `platform.higgsfield.ai`, `api.higgsfield.ai` et `higgsfield.ai` (`403` sur le `CONNECT`). C'est une politique réseau d'organisation, pas une erreur de clé. Les clés fournies n'ont donc jamais pu être testées. |
| 2 | **Compte Higgsfield MCP sous-provisionné** | Le serveur MCP Higgsfield connecté à la session pointe sur un **autre compte** : workspace privé unique, plan `free`, **7,53 crédits**. Le plus petit run Seedance 2.5 coûte 12,5 crédits. |

### Les 3 façons de débloquer

1. **Créditer le compte MCP** (le plus simple) : ~200 crédits couvrent le format 9:16 en 1080p
   avec de la marge de retakes ; ~400 couvrent les deux formats. Les prompts de ce dossier
   partent alors en une seule commande (voir *Lancer la génération*).
2. **Faire allowlister `platform.higgsfield.ai`** auprès de l'admin de l'environnement Claude Code,
   puis rejouer les prompts en REST avec les clés `HF_API_KEY_ID` / `HF_API_KEY_SECRET`.
3. **Lancer depuis un poste local** (Mac d'Arthur) : les prompts de `seedance-prompts.json` sont
   agnostiques du transport, ils marchent aussi bien via MCP que via l'API REST.

### 🔐 Sécurité : les clés fournies sont à révoquer

`HF_API_KEY_ID` / `HF_API_KEY_SECRET` ont été collées en clair dans un chat. Elles ne sont
**pas** dans ce dépôt et ne doivent jamais y être commitées. Recommandation : **les révoquer et
en régénérer une paire** dans le dashboard Higgsfield, puis la stocker comme les autres secrets
du projet (`Config.xcconfig`, gitignored — règle 5 de `CLAUDE.md`).

---

## Grille tarifaire mesurée (préflight réel, 27 août 2026)

Coûts constatés via `get_cost`, par plan 4 s :

| Modèle | Résolution | Crédits / plan 4 s | Film 20 s (5 plans) | Les 2 formats |
|---|---|---|---|---|
| Seedance 2.5 | 1080p | 36 | 180 | 360 |
| Seedance 2.5 | 720p | 26 | 130 | 260 |
| Seedance 2.0 Mini | 720p + audio | 10 | 50 | 100 |
| Seedance 2.0 Mini | 480p, muet | 4 | 20 | 40 |

**Budget conseillé : 500 crédits** pour les deux formats en Seedance 2.5 / 1080p, retakes
compris (compter 1,4× le coût nominal : un plan sur trois se rejoue).

**Chemin économique** si le budget est serré : caster les 5 plans en **Seedance 2.0 Mini 480p**
(20 crédits le film) pour valider le rythme et le casting, puis ne repasser en 2.5 / 1080p que
les plans validés.

---

## Le principe de production qui compte

**Aucun modèle vidéo IA ne sait écrire du texte français lisible ni reproduire une UI iOS
réelle.** Laisser Seedance « inventer » l'écran de Kiwio produit une bouillie de faux glyphes qui
décrédibilise l'annonce — c'est l'erreur classique des pubs SaaS générées.

Le pipeline de ce pack sépare donc les trois couches :

```
Couche 1 — SCÈNE (Seedance)      : la personne, la cuisine, la lumière, le mouvement caméra,
                                   le téléphone tenu en main. Écran du téléphone = VIDE / neutre.
Couche 2 — UI RÉELLE (post-prod) : les vraies captures de scripts/appstore_screens_v3/ sont
                                   incrustées dans l'écran (tracking 4 points).
Couche 3 — TEXTE + LOGO (post)   : titres, sous-titres, CTA, logo. Jamais généré par l'IA.
```

Chaque prompt de `seedance-prompts.json` contient donc explicitement
`no text, no readable UI, phone screen off or plain neutral glow` — c'est volontaire, pas un oubli.

**Captures réelles à incruster** (déjà au format 1290×2796, dans le dépôt) :

| Plan | Capture | Ce qu'elle montre |
|---|---|---|
| 2 | `scripts/appstore_screens_v3/final_01_journal.png` | Journal : 1664 kcal restantes, anneau, macros |
| 3 | `scripts/appstore_screens_v3/final_06_ajout.png` | Feuille d'ajout : dicter · scanner · rechercher · code-barres · ma journée · activité |
| 4 | `scripts/appstore_screens_v3/final_02_bilan.png` | Apports à renforcer : B12 10 %, Fer 17 %, Zinc 37 % |
| 5 | `scripts/appstore_screens_v3/final_03_plan.png` + `final_04_complements.png` | Plan radial, rituel matin · midi · soir |

---

## Lancer la génération (une fois les crédits en place)

Le pack est prêt à partir en un seul appel batch. Via le serveur MCP Higgsfield :

```
generate_video_batch(requests = les 5 entrées de seedance-prompts.json, clé "instagram_9x16")
jobs_wait(jobs = les 5 job_id retournés)
show_generation_by_ids(jobs = les 5 job_id)
```

Puis le même batch avec la clé `linkedin_16x9`. Le montage (couches 2 et 3) se fait ensuite
dans l'outil de montage habituel, ou via le workflow `video-editing` de Higgsfield.

---

## Fichiers du pack

| Fichier | Contenu |
|---|---|
| `README.md` | Ce document : statut, blocages, budget, pipeline |
| `storyboard.md` | Le film plan par plan : intention, image, texte à l'écran, voix off, son |
| `seedance-prompts.json` | Les prompts Seedance prêts à envoyer, les deux formats |
| `social-copy.md` | Les posts LinkedIn et Instagram, hashtags, specs de publication |

---

## Garde-fous produit (à ne pas contourner au montage)

Kiwio parle de santé : la publicité engage la conformité App Store et la crédibilité médicale.

1. **Aucune promesse thérapeutique.** On dit « identifie tes apports à renforcer », jamais
   « soigne ta fatigue », « corrige ta carence », « diagnostique ».
2. **Aucun chiffre inventé.** Les pourcentages montrés à l'écran (B12 10 %, Fer 17 %, Zinc 37 %)
   sont ceux des captures réelles du dépôt. Ne pas en fabriquer d'autres pour l'effet.
3. **Aucun faux témoignage.** Les personnes à l'écran sont des figurants génératifs, jamais
   présentées comme des utilisatrices réelles qui témoignent.
4. **Mention légale** en fin de film, lisible : « Kiwio ne remplace pas un avis médical. »
   C'est la même loi que le disclaimer d'écran (`DESIGN-PAGES.md`, loi 12).
5. **Ton de marque** : tutoiement, causal, jamais culpabilisant (pas de « tu manges mal »).
