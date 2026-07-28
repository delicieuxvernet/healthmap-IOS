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
| V1 | Scan — bloc calories + flèche du pop-up | `MealScanView.swift`, `ScanHomeComponents.swift`, `DailyMealJournalView.swift` | ⬜ à faire | — |
| V2 | Scan — hiérarchie des entrées + recherche & code-barres | `MealScanView.swift`, `JournalEditorComponents.swift`, `FoodScanService.swift` | ⬜ à faire | — |
| V3 | Vocal — maintien pour enregistrer | `MealScanView.swift`, `VoiceMealSheet.swift` | ⬜ à faire | — |
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
