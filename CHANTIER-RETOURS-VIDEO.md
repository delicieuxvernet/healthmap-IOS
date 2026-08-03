# Chantier « retours vidéo » — 2 août 2026

> Retours d'Arthur après le tournage de la vidéo App Review (build 426).
> Règle : chaque vague a son OBJECTIF FINAL UTILISATEUR en gras, un plan, des ressources dédiées.
> On enchaîne vague après vague, avec vérification de cohérence à chaque fois.
> Suivi opérationnel : task manager de session (8 tâches) + ce fichier (source de vérité inter-sessions).

## V0 — Crash « Modifier mon profil » 🔴 BLOQUANT SOUMISSION

**OBJECTIF FINAL : l'utilisateur édite n'importe quelle section de son profil sans jamais faire tomber l'app.**

- Symptôme : Profil → Modifier mon profil → tap sur n'importe quelle section → l'app se ferme. 100 % reproductible, build 426.
- Suspect n°1 : refonte `EditProfileView` via `optionPairs` (correctif A3, PR #198 du 2 août, session parallèle).
- Plan : diagnostic agent (cause racine fichier:ligne) → fix minimal → test unitaire de non-régression → build TestFlight → rattacher le build à la version 1.0.
- La soumission App Store (V6) est BLOQUÉE tant que V0 n'est pas vert : un reviewer qui tape là = refus 2.1.

## V1 — Gating renforcé du gratuit

**OBJECTIF FINAL : en gratuit, on voit QU'ON A DÉTECTÉ quelque chose (« une de tes habitudes bloque ton fer ») mais le QUOI et le COMMENT sont premium.**

- Fiche apport ouverte du Bilan (`ApportV2DetailSheet`, BilanV6Components.swift:95-143) : flouter « Où le trouver » (3 aliments) + « Interaction à connaître » — aligner sur la politique de `NutrientDetailSheet` (GatedOverlay + UnlockDoor, PremiumGating.swift). C'était le trou n°3 de l'audit premium.
- Points d'attention du Bilan : teasing en clair, explication/résolution floutée.
- Réutiliser exclusivement les composants existants (GateIntensity .teaser/.locked).
- Au passage (audit premium) : réactivité `NutrientDetailSheet` (remplacer le `let isPremium` snapshot par une observation).

## V2a — Pop-up « point d'attention » (maquette AVANT code)

**OBJECTIF FINAL : taper un point d'attention ouvre un pop-up limpide — schéma visuel du mécanisme, explication très simple du pourquoi, lien vers le Plan — au lieu d'une redirection où on ne sait pas où cliquer.**

- En gratuit : titre + teasing visibles, le mécanisme et la solution floutés (cohérent V1).
- Process : maquette HTML dans le chat → validation Arthur → port SwiftUI (doctrine kiwio-ios-only).

## V2b — Plan à double vue (maquette AVANT code)

**OBJECTIF FINAL : dans le Plan, deux boutons de vue (comme Compléments) : « Objectifs & symptômes » (l'actuel, NE PAS TOUCHER) ↔ « Apports » (bulles vitamine B12, vitamine D… → tap → actions limpides : ajoute tel aliment, arrête telle conso après telle heure).**

- Process : maquette HTML dans le chat → validation → SwiftUI.
- Synergie avec l'audit : c'est l'occasion de rebrancher ou retirer `PlanTopic.ritual` (donnée morte).

## V3 — Précision du scan photo

**OBJECTIF FINAL : une photo de truite + pommes de terre + haricots verts est reconnue comme telle — pas cabillaud + petits pois.**

- Étape 1 (en cours, agent) : diagnostic du pipeline — résolution/compression de l'image envoyée par iOS (cause classique n°1), prompt serveur (vocabulaire fermé ? exemples biaisants ?), post-traitement (mapping vers un référentiel qui écrase les espèces ?).
- Étape 2 : benchmark reproductible — N photos réelles, vérité terrain, métrique par aliment (exact / famille proche / faux), coût + latence. Candidats : modèle actuel (Claude Sonnet 5) vs alternatives vision (Kimi/Moonshot, GPT, Gemini).
- Étape 3 : appliquer le correctif gagnant. Côté serveur = déployable SANS re-review App Store.

## V4 — Polish visuel

**OBJECTIF FINAL : un rendu fini, professionnel, sans zone « hors app ».**

- Sheet nutriment (ex. Vitamine B12) : marge trop faible entre le haut du sheet et le titre+logo.
- Zone blanche sous la status bar (heure/batterie) : le fond doit s'étendre sous la safe area (le blanc s'arrête ~1 px au-dessus du bouton profil).

## V5 — Wording export

**OBJECTIF FINAL : l'utilisateur comprend qu'il exporte SES DONNÉES pour les réutiliser (les donner à une IA, les archiver…).**

- Renommer « Exporter mon profil » → « Exporter mes données » + sous-titre d'usage (IA, archive).

## V6 — Soumission App Store (après V0 minimum)

- Nouveau build (avec V0 + ce qui est prêt) rattaché à la version 1.0 (4 éléments déjà vérifiés).
- Vidéo d'Arthur jointe par API (mode attach-video, release GitHub privée).
- Vérifier `profiles.tier` post-achat sandbox (test live du webhook RevenueCat).
- Envoi par API : mode submit, EXCLUDE_PRODUCTS=healthmap_monthly.
- Décision Arthur : V1 dans le build soumis, ou gardé pour 1.0.1.

## Références

- Audit premium du 2 août : `C:\Users\stana\Desktop\Claude\Healthmap\audit-phase3-2026-08-02\audit-premium-2026-08-02.md`
- État soumission : mémoire `kiwio-soumission-appstore-etat`
