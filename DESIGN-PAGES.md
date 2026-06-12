# DESIGN-PAGES.md — Architecture de référence des écrans HealthMap

> **À relire INTÉGRALEMENT avant tout ajustement UX/UI.** Ce fichier est la source de
> vérité de la structure de chaque page : quel bloc, à quelle position, alimenté par
> quelle donnée, avec quelles limites. Processus imposé par Arthur (11 juin 2026) :
> 1. Toute évolution de structure se décide ICI d'abord (modifier ce fichier),
> 2. puis maquette visuelle validée par Arthur,
> 3. puis code. Jamais l'inverse.
> Pour ajouter une information nouvelle : trouver son niveau (1 scannable / 2 détail),
> lui faire passer le TEST DE VALEUR, et l'insérer dans le template ci-dessous.
> Détails d'exécution et historique des décisions : `C:\Users\stana\Desktop\Claude\PLAN-BILAN-UX-2026-06-11.md`.

---

## 0. Lois transversales (s'appliquent à TOUTES les pages)

1. **Test de valeur utilisateur (loi suprême)** : chaque élément affiché doit répondre à
   « qu'est-ce que ça apporte à l'utilisateur ? ». Réponse faible → supprimer. Les règles
   internes (seuils, tranches, mécanique) ne s'affichent JAMAIS.
2. **Thème clair forcé** (`.preferredColorScheme(.light)`), fond lumineux #F7FAFF,
   cartes blanches, **aurora animée** (AnimatedBackground) en arrière-plan à opacité
   réduite — elle ne domine jamais l'information. Reduce-motion → statique.
3. **Échelle de couleur unique** (une seule fonction dans le code) :
   score < 45 → rouge · 45-69 → orange · ≥ 70 → vert. Vaut pour anneau, jauges,
   labels d'état, pastilles. Jamais la couleur seule : toujours doublée d'un mot d'état.
4. **Labels d'état fixes** — nutriment : < 45 « À renforcer », 45-69 « Limite »,
   ≥ 70 « Solide ». Score global : < 45 « Priorité », 45-69 « À surveiller »,
   70-84 « Solide », ≥ 85 « Optimal ».
5. **Anneau de score : remplissage = score/100 exactement.** Jauges : largeur = score %,
   marqueur « zone visée » fixe à 70 %.
6. **Symétrie stricte** : rayon unique 16 (continuous), grille 8 pt, 3 tailles de texte
   max par écran, tuiles d'une même rangée = dimensions identiques.
7. **Boutons** : primaires = teinte pleine ; secondaires = **glass**
   (`.ultraThinMaterial` + liseré fin), jamais de fond opaque. `.healthMapPressed`
   partout, touch targets ≥ 44 pt.
8. **Pastilles (pills) = vocabulaire contrôlé uniquement** (enums : « Impact fort »,
   « Facile », « 2 à 3 mois », « Essentiel »). JAMAIS de texte libre IA dans une pill.
9. **Texte libre IA : lineLimit + truncationMode(.tail) déclarés par slot**
   (headline 2 lignes, verdict 1 ligne en carte, action 2 lignes, expected_impact
   1 ligne, tip 2 lignes). Le serveur impose les longueurs (prompt v35+) et les rabote.
10. **Pattern « Pourquoi ? » universel** : toute raison/explication secondaire est
    derrière un bouton glass « Pourquoi ? » (révélation en place, chevron). Le contenu
    révélé est CAUSAL et personnel (cite les réponses du questionnaire, cause → effet),
    jamais circulaire.
11. **Une case premium floutée par page** (pattern BlurredSection) : titre lisible qui
    tease, contenu réel flouté dessous. Jamais de coquille vide. Les avertissements de
    SÉCURITÉ ne sont jamais floutés.
12. **Un seul disclaimer médical par écran**, en bas, 1 ligne.
13. **Tout composant déclare en en-tête** : champ source, lignes max, couleur = f(score).
14. Contenu IA : régi par le contrat de prompt (`supabase/functions/generate-analysis/
    prompt.ts`, v35+) — longueurs max par champ, pas de majuscules d'emphase, pas de
    parenthèses/molécules au niveau 1, pas de tiret long « — », fréquences naturelles.
    Toute modification du prompt → harnais de conformité sur les 3 personas test.

---

## 1. BILAN (onglet 1 — l'écran le plus consulté)

| # | Bloc | Source | Règles |
|---|------|--------|--------|
| 0 | Red flags `urgency == immediate` uniquement | `red_flags` | Sécurité : seuls les urgents passent avant le héro ; les autres en bas |
| 1 | **Héro compact** : anneau (~140 pt, arc = score, reveal animé count-up) + pill label global + chip streak discrète + headline + « Comment ce score est calculé » discret | `healthScore` local, `summary.headline` (2 lignes max), streak | Épure du 12 juin : la MÉTAPHORE a quitté le héro, elle ouvre la sheet « comment ce score… ». Reveal = pic émotionnel ; reduce-motion : direct |
| 2 | **Cartes nutriments JUMELLES, directement sous le héro, SANS titre de section** : nom + mot d'état coloré, verdict 1 ligne, grande jauge (10 pt) + marqueur 70 %, bouton glass « Pourquoi ? » → fiche. **La 1re carte porte le bandeau « Ton action\u{202F}: … »** (l'ex-bloc « priorité n°1 », supprimé le 12 juin : il prenait trop de place sans valeur) | deficiencies top 3, action = priorityActions[0] si elle mentionne le nutriment sinon solution.action | L'ordre fait la hiérarchie (test de valeur, loi 1) |
| 4 | Bouton glass « Tous mes nutriments (10) » → grille complète (sheet séparée) | scores locaux 10 nutriments | La grille n'est PLUS sur l'écran principal. Grille héritée : anneaux encore colorés par identité, à aligner sur l'échelle score (lot polish) |
| 5 | **Rangée symétrique 2 tuiles** : « Points forts » (verte) / « Interaction » | `positive_findings[0]` (labels via NutrientData, jamais d'ids bruts) / `interactions_detectees[0].titre` | Tuiles strictement identiques en dimensions |
| 6 | « Pépite du jour » | `practical_tips` rotation quotidienne : tip (2 lignes) | why + source RÉVÉLÉS au tap via bouton glass « Pourquoi ? » (loi 10), jamais inline |
| 7 | Case premium floutée : « Le hack [nutriment prioritaire] » | `hack`/`synergie` du risque n°1 | Texte borné 3 lignes même flouté |
| 7b | Actions premium : « Exporter mon bilan (PDF) » / « Partager mon score » | services d'export existants | 2 boutons, premium uniquement (partage = viralité) |
| 8 | **Fin positive** : « Ton plan est prêt → » + « Ton score évoluera à ton prochain bilan » | — | Peak-end : ne JAMAIS finir sur les carences |
| 9 | Disclaimer (1 ligne) + red flags non urgents | | |

**Supprimés définitivement** : highlight grid 2×2 hétérogène, grille 10 nutriments inline,
badges (→ Suivi), navigation cards NotificationCenter, doublons action du jour/disclaimers.

## 2. FICHE NUTRIMENT (niveau 2, sheet — TERMINALE, X visible, jamais de niveau 3)

| # | Bloc | Source | Règles |
|---|------|--------|--------|
| 1 | Header : emoji + nom + état FR + MiniScoreRing | NutrientData + score local | Statut TOUJOURS en français (helper partagé) |
| 2 | « Détecté dans tes réponses » : chips + badge fiabilité | `signals[]`, `confidence` (vulgarisé : « fiabilité élevée ») | LA preuve de personnalisation |
| 3 | Comparaison en citation | `comparaison` | Phrase mémorable |
| 4 | **Solution d'abord** (carte verte) : action + dosage + quand + « Effet attendu : [delai] » | `solution.*` | Le delai est la promesse motivationnelle |
| 5 | Repliables fermés (caret) : « Comprendre le mécanisme » / « Symptômes possibles » | `mecanisme`, `signe_manque` | |
| 6 | Hack + synergie : premium (BlurredSection) | `hack`, `synergie` | Politique premium identique PARTOUT |

## 3. MON PLAN (onglet 4)

| # | Bloc | Source | Règles |
|---|------|--------|--------|
| 1 | Header + « N besoins identifiés dans ton bilan » | count | |
| 2 | **Une carte par BESOIN** : nom + état coloré, SES actions cochables (cochée = barrée), footer vert « Résultat attendu : [bénéfice] — [delai] » | `nutrient_risks` + `priority_actions` rattachées + `solution.delai`/`expected_impact` | Le groupement par besoin rend chaque action signifiante |
| 3 | Rangée symétrique 2 tuiles : « Compléments » (résumé) / « Analyses » (tests) | `supplements_schedule` counts / `blood_tests.tests` | |
| 4 | 1 ligne interaction (si > 0) | `interactions_detectees` | |
| 5 | Pépites (compteur) + case premium floutée « Le timing parfait de tes compléments » | `practical_tips`, `supplements_schedule` | |

**Supprimés** : red flags dupliqués, points forts dupliqués, « plan 3 phases » codé en dur,
stats grid (IMC/TDEE → Profil), CTA premium plein écran.

## 4. SUIVI (onglet 2)

**État A — découverte (suivi non activé)** : pill glass « Aperçu — exemple » ;
carte « Ton score, semaine après semaine » (barres 6 semaines + ✓/✗ objectifs sous
chaque semaine, SANS ligne d'explication) ; ligne nutriment exemple (« Fer : 38 → 64 ») ;
rangée symétrique Série (avec joker visible) / Badges ; **gros CTA « Commencer mon
suivi personnalisé — 3 questions · 1 minute »** → mini-questionnaire d'objectifs ;
case premium « Ta projection de score personnalisée » (estimation CALCULÉE, jamais inventée).

**État B — actif** : mêmes blocs avec données réelles (`score_history`, checkins) ;
carte « Check-in du jour » (3 gros boutons glass Énergie/Sommeil/Stress + CTA) en
position 2 ; delta vert « +N depuis ton dernier bilan » en tête. Jamais de faux chiffres,
jamais de culpabilisation (pas de compteur d'inactivité).

## 5. MES COMPLÉMENTS (future page, remplacera l'onglet Profil — P6)

Timeline « Matin / Soir » (sections vides affichées : « Aucun complément le soir pour
ton profil ») ; chaque complément = carte : nom + dose, pill priorité (« Essentiel »),
ligne forme + quand, **bouton glass « Pourquoi ? »** → raison causale (`reason`) ;
carte d'avertissement ambre TOUJOURS visible (`supplements_schedule.warnings`) ;
sous-titre « Issus de ton bilan — à confirmer par bilan sanguin » ; case premium
floutée « Interaction détectée avec ton [habitude] ». Le profil devient un bouton
avatar en haut du Bilan (P6).

---

## 6. MICRO-DÉTAILS (lois 15-22 — « pousser encore plus loin le souci du détail », Arthur)

Un relecteur dédié « pixel & micro-détails » vérifie ces points sur CHAQUE PR d'interface,
en plus des relecteurs compilation et conformité :

15. **Typographie française irréprochable** : apostrophes courbes (' jamais '),
    espace fine insécable avant ? ! : ; et dans « guillemets », accents sur les
    capitales (É, À), pluriels dynamiques corrects (« 1 besoin identifié » /
    « 2 besoins identifiés » — jamais « 1 besoins »), nombres au format français
    (virgule décimale, espace insécable des milliers).
16. **Grille au pixel** : tous les paddings/espacements sont des multiples de 8
    (4 toléré pour les micro-gaps) ; AUCUNE valeur magique (13, 17, 22…) ;
    espacement identique entre toutes les sections d'un même écran.
17. **Mouvement unifié** : une seule courbe spring (`.healthMapSpring`) et une seule
    durée courte (`.healthMapQuick`) dans toute l'app ; apparitions de sections en
    léger stagger ; jauges et anneau s'animent de 0 → valeur à l'apparition ;
    count-up du score ~1,2 s ease-out ; TOUT est gelé si reduce-motion.
18. **Toucher vivant** : haptic léger sur chaque sélection, haptic de succès sur les
    moments forts (bilan révélé, action cochée) ; `.healthMapPressed` sur tout ce qui
    se tape ; aucune zone tappable sans feedback visuel < 100 ms.
19. **Chaque vue déclare ses 4 états** : contenu / chargement (skeleton, jamais un
    spinner nu) / vide (mascotte + phrase utile) / erreur (message actionnable +
    réessayer). Un écran sans ses 4 états ne passe pas la revue.
20. **Accessibilité de détail** : VoiceOver label sur chaque élément interactif,
    Dynamic Type testé au clamp max sans casse de layout, contrastes AA sur tous les
    couples texte/fond utilisés, cibles 44 pt vérifiées AU RENDU (pas au padding déclaré).
21. **Bords d'écran** : safe areas respectées partout, testé mentalement sur iPhone SE
    (petit) et Pro Max (grand) ; aucun texte tronqué à une taille standard ;
    les ombres ne se font jamais couper par un clipping parent.
22. **Cohérence des vides** : un même séparateur, une même hauteur de carte minimale,
    une même icône de chevron partout ; si deux écrans montrent le même objet
    (nutriment, complément), ils utilisent le MÊME composant.

---

*Maquettes de référence : session du 11 juin 2026 (« rendu_final_4_ecrans_reference »
+ correctifs « Pourquoi ? » et règles déterministes). Contrat IA : prompt v35
(generate-analysis v40), harnais de conformité sur audit-a/b/c obligatoire avant
tout déploiement de prompt.*
