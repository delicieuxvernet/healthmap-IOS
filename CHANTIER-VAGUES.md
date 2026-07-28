# Chantier « vagues » — retours Arthur du 29 juillet 2026

> **Fichier de reprise.** Si la session Claude est coupée (crédits, crash), la
> session suivante lit CE fichier en premier : elle sait ce qui est fait, ce qui
> reste, et sur quelle branche. Chaque vague est autonome et mergée verte —
> `main` est toujours installable, jamais à moitié corrigé.

Branche de travail : `ios/vagues-scan-ux` (worktree isolé off `origin/main`).
Règle : **une vague = un commit = une PR = CI verte = merge**. On ne démarre
jamais la vague N+1 avec la vague N à moitié poussée.

---

## Les 10 demandes (verbatim condensé)

| # | Demande | Vague |
|---|---|---|
| 1 | La flèche du pop-up « Ajouter une photo » ne pointe pas sur le bouton « Scanne ton repas » | V1 |
| 2 | Le rond kcal restantes / kcal consommées : les deux sont collés, mal répartis | V1 |
| 3 | Le bloc du journal du jour (kcal restantes + protéines/glucides/lipides) est excellent → le réutiliser à la place du bloc calories actuel | V1 |
| 4 | Le scan de code-barres a disparu → le remettre dans la recherche d'aliments | V2 |
| 5 | Réorganiser l'écran Scan : « Recherche d'aliments » sous les deux boutons phares, puis un bloc recherche produit avec un petit bouton code-barres dans la barre | V2 |
| 6 | Maintenir le doigt sur « Dicte ton repas » doit démarrer l'enregistrement (façon Instagram), pas seulement ouvrir la feuille | V3 |
| 7 | L'analyse d'un repas dicté échoue par intermittence — surtout sur les dictées longues ou imprécises | V4 |
| 8 | Barre blanche figée en haut de l'app pendant la navigation, sous la barre d'état | V5 |
| 9 | Polices non homogènes (constaté sur Compléments) — max 2 familles, un titre = toujours la même police | V6 |
| 10 | Le bouton calendrier (haut gauche de Scan) doit ouvrir un vrai calendrier navigable, pas seulement aujourd'hui | V7 |

---

## État des vagues

| Vague | Sujet | Fichiers pivots | État | PR |
|---|---|---|---|---|
| V1 | Scan — bloc calories + flèche du pop-up | `MealScanView.swift`, `ScanHomeComponents.swift` | ✅ mergé | [#182](https://github.com/delicieuxvernet/healthmap-IOS/pull/182) |
| V2 | Scan — hiérarchie des entrées + recherche & code-barres | `MealScanView.swift`, `BarcodeScannerSheet.swift`, `Info.plist` | ✅ mergé | [#183](https://github.com/delicieuxvernet/healthmap-IOS/pull/183) |
| V3 | Vocal — maintien pour enregistrer | `MealScanView.swift`, `VoiceMealSheet.swift` | 🔄 en cours | — |
| V4 | Vocal — fiabilité de l'analyse | `VoiceMealService.swift` + edge `parse-meal-voice` (repo web) | ⬜ à faire | — |
| V5 | Chrome — barre blanche en haut | vues racine des onglets | ⬜ à faire | — |
| V6 | Typographie homogène | `ThemeConstants.swift` + vues | ⬜ à faire | — |
| V7 | Calendrier navigable | `DailyMealJournalView.swift`, `MealJournalViewModel.swift` | ⬜ à faire | — |

Légende : ⬜ à faire · 🔄 en cours · ✅ mergé sur `main`

---

## Ce qu'on a compris du code (pour ne pas re-fouiller)

- **Accueil Scan** = `MealScanView.scanHome` : header (titre + `ScanDayNav` + compteur
  de scans) · `dualEntry` (dicte | scanne) · `voiceHint` · `ScanKcalGauge` ·
  `searchEntry` · `captureBlock` · « Ta journée » (micros + macros) · dernier plat ·
  récents.
- **Le pop-up photo** est un `confirmationDialog` porté par le modificateur
  `PhotoPresentations`, appliqué au *scaffold entier*. Sous iOS 26 les dialogues
  émergent du contrôle qui les déclenche : ancré au conteneur, la flèche vise le
  centre de l'écran. Le fix est de porter le dialogue sur le bouton lui-même.
- **Le bouton calendrier** (toolbar, haut gauche) ouvre `DailyMealJournalView`,
  qui n'affiche qu'aujourd'hui. La navigation par jour existe déjà côté accueil
  (`ScanDayNav` + `MealJournalViewModel.goPrevDay/goNextDay`) — V7 branchera un
  vrai calendrier sur ce même modèle.
- **Vocal** : `VoiceMealService.analyze` appelle l'edge function
  `parse-meal-voice` (source dans le repo **web**, pas ici), puis `buildEntries`
  re-résout chaque aliment via `get_food`. Toute erreur non-429 est aplatie en
  « L'analyse n'a pas abouti » — d'où l'impression d'aléatoire.
- **Code-barres** : le service `FoodScanService.lookupBarcode` existe toujours et
  fonctionne (cache 1 h). C'est l'entrée UI qui a disparu, pas le moteur.

---

## Journal des vagues

_(chaque vague ajoute ici : ce qui a été fait, comment ça a été vérifié, et ce
qui a été volontairement laissé de côté)_

### V1 — bloc calories + flèche du pop-up (PR #182, mergée, CI verte 6 min)

- `ScanJourneeCard` remplace `ScanKcalGauge` : kcal restantes en grand, consommé /
  budget, barre de progression, légende Apple Santé, phrase de synthèse et les
  4 macros en barres. La carte macros à anneaux et le titre de section « Ta
  journée » sortent de l'écran (la carte porte son propre titre).
- `ScanKcalGauge` et `ScanMacrosJourCard` restent dans `ScanHomeComponents.swift`,
  hors écran, jusqu'à validation d'Arthur. **Si validée → les supprimer.**
- Le `confirmationDialog` photo est porté par le bouton « Scanne ton repas »
  (avant : par le scaffold, d'où la flèche au centre de l'écran).
- Laissé de côté : l'anneau circulaire disparaît de l'accueil. Arthur avait
  d'abord demandé « un rond avec l'espace bien réparti », puis demandé que le
  bloc du journal prenne cette place — la seconde consigne l'emporte, à
  reconfirmer au réveil.

### V2 — entrées + recherche & code-barres (en cours)

- La barre de recherche remonte juste sous les deux gestes phares (3ᵉ fonction).
- Un bouton code-barres vit DANS cette barre, à droite (52×48 pt).
- `BarcodeScannerSheet` : nouveau. `AVCaptureMetadataOutput` (EAN-13/8, UPC-E),
  gestion des trois états d'autorisation caméra. Le code lu est résolu par
  `foodDetail(id: "off:<code>")` — le MÊME chemin que la recherche texte, donc la
  fiche portion et l'ajout au journal sont ceux déjà testés.
- L'ancien écran code-barres (supprimé en juin, commit `66be05b`) ne scannait
  rien : c'était une saisie manuelle du code. Rien à restaurer, tout à écrire.
- `NSCameraUsageDescription` mentionne désormais le code-barres (revue App Store).
- **Non vérifiable en CI** (pas de caméra) : la lecture réelle d'un code-barres
  se valide sur device.

### V3 — maintien pour enregistrer (en cours)

- L'enregistrement démarre sur l'ACCUEIL, doigt posé sur « Dicte ton repas »,
  après 250 ms de maintien (en deçà, c'est un appui simple : la feuille s'ouvre
  comme avant, sans rien enregistrer).
- Pendant le maintien, un bandeau reprend le micro vivant, la waveform et le
  minuteur de la feuille (`MicroVivant`, `Waveform`, `PointEnregistrement` sont
  passés d'internes au fichier vocal à partagés — aucune duplication de dessin).
- Au relâchement, la feuille s'ouvre directement sur l'analyse. La capture est
  **injectée** dans `VoiceMealSheet` (`@ObservedObject`) au lieu d'être créée
  par elle : c'est ce qui permet de commencer dehors et de finir dedans.
- Garde-fou 60 s : dans un `ScrollView`, un geste peut être avalé par le
  défilement et ne jamais rendre son `onEnded` — sans plafond le micro
  tournerait indéfiniment.
