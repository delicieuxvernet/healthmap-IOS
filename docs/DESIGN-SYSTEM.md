# DESIGN-SYSTEM.md — tokens visuels Kiwio iOS

> Source de vérité des **tokens** (police, espacement, rayon, ombre, couleur).
> La structure des écrans, elle, vit dans `DESIGN-PAGES.md` à la racine.
> Fichiers de code : `HealthMap/Views/Shared/KiwiDS.swift` (**DS de la refonte
> du 23 août 2026, à consommer sur tout écran refondu**), puis les tokens
> historiques `HealthMap/Views/Shared/ThemeConstants.swift` et
> `HealthMap/Utilities/Color+Theme.swift` (basculés sur le socle neutre).

---

## Verre liquide (2 octobre 2026)

> Maquette Claude Design « Kiwio - Motion v3 - Verre liquide ». Elle remplace le fond neutre et
> la carte blanche du socle du 23 août ; le reste du socle (vert réservé à ce qui se touche,
> un chiffre héros par écran, typographie, formats) tient toujours.
> Code : `HealthMap/Views/Shared/KiwiVerre.swift`, `KiwiMascotte.swift`, `KiwiMotion.swift`.

**Fond.** `VerreFond` (= `DSPageBackground()`) : quatre halos flous qui dérivent lentement sur une
base pâle. La teinte suit l'onglet (`VerreTeinte` : `kiwi` Journal · `aube` Progrès · `ciel` Plan ·
`orchidee` Compléments · `neutre` Réglages), en fondu de 0,9 s ; la racine la pose dans
l'environnement (`\.verreTeinte`). Une page racine ne peint jamais d'aplat. Page poussée :
`VerrePageFond()`. Feuille : `.verreFeuille()` sur son contenu (fond de verre, coins de 38).

**Verre.** Une matière = une recette (`VerreMatiere`) dessinée dans une forme (`VerrePlaque`).

| Matière | Recette | Modificateur |
|---|---|---|
| `carte` | blanc 80 → 58 %, liseré blanc intérieur, rayon 24, ombre douce découpée | `.dsCard()` · `.verreCarte()` · `.verreCarte(teinte:)` |
| `carteFlottante` | la même + flou vivant (au-dessus d'un contenu) | `.verreCarteFlottante()` (rayon 28) |
| `clair` | blanc 74 → 40 %, reflet haut et bas, capsule | `.verreClair()` · `.verreClair(Circle())` |
| `clairActif` | vert pâle (bouton déplié, choix retenu) | `.verre(.clairActif, forme:)` |
| `principal` | vert `#8AD262 → #5DA838 → #4C982B`, même reflet | `.verrePrincipal()` · `DSCapsuleButton` |
| `principalBombe` | le bouton Dicter (éclat sur la moitié haute) | `.verre(.principalBombe, forme:)` |
| `barre` · `pastille` | barre d'onglets et sa pastille qui glisse | `KiwiFloatingTabBar` |
| `piste` · `curseur` | bascule à segments | `VerreBascule` |
| `surVoile` | bouton posé sur le voile de la dictée | `.verre(.surVoile, forme:)` |

Le flou d'arrière-plan vivant (`Material`) est réservé à ce qui flotte au-dessus d'un contenu qui
défile : barre d'onglets, bord haut (`VerreBordHaut`), voile (`VerreVoile`), feuilles, carte du Plan.
Une carte posée sur le fond n'en porte pas. Sous « Réduire la transparence », chaque matière devient
un aplat opaque.

**Couleurs.** Une teinte par catégorie, une version foncée pour le texte posé sur fond clair. Le vert
kiwi reste réservé à ce qui se touche.

| Catégorie | Teinte | Texte |
|---|---|---|
| Kiwi | `teinteKiwi` #5DA838 | `teinteKiwiTexte` #3B6D11 |
| Énergie | `teinteEnergie` #F07040 | #A94620 |
| Vitamine D · à renforcer | `teinteVitamineD` #F1961D | #995600 |
| Glucides | `teinteGlucides` #E6B731 | #876200 |
| Lipides | `teinteLipides` #F18336 | #923F00 |
| Fibres | `teinteFibres` #4CAC91 | #206C58 |
| Vitamine C | `teinteVitamineC` #11A6AA | #006368 |
| Eau | `teinteEau` #46B1E3 | #147298 |
| Protéines · symptômes du Plan | `teinteProteines` #4E82E5 | #224FA7 |
| Iode · soir | `teinteIode` #7368D4 | #5348A1 |
| Fer | `teinteFer` #AF5FC7 | #7F3C93 |
| Symptômes | `teinteSymptomes` #EB5070 | #B52F4E |
| B12 · magnésium · oméga-3 · zinc · calcium | dérivées (hors maquette) : #E8605B · #2FA9CE · #3B9CF6 · #DB5FA1 · #8E8E93 | `Color.teinteApportTexte(for:)` |

`Color.nutrientColor(for:)` renvoie la teinte d'un apport ; `dsProteines`, `dsGlucides`, `dsLipides`,
`dsFibres`, `dsCalories`, `dsARenforcer` pointent sur cette palette.

**Quatre mouvements, partout.** Glisse (pages, onglets) `Animation.kiwiGlisse` = `.smooth(duration: 0.45)` ·
ressort (feuilles, zoom, bulle) `kiwiFluide` = `.spring(response: 0.5, dampingFraction: 0.82)` · rebond
(coches, icônes, pastilles) `kiwiRebond` = `.bouncy(duration: 0.45, extraBounce: 0.2)` · compteurs
`.contentTransition(.numericText())` + `kiwiCompteur` (0,9 s). L'appui reste `kiwiVif` (0,96).
Effets : `.verreCascade(_:delai:)`, `.verreSurgir(_:delai:)`, `.verreGerbe(...)`, `.verreEnvol(...)`,
`.verrePop(...)`, `.verreBrillance()`, `VerreHaloQuiRespire`. Rien ne dépasse 1,22 (`KiwiEchelle`).
Haptique : `.selection` au changement d'onglet, `.success` à la coche, à l'ajout d'un repas et au
rituel terminé, impact doux par gobelet. Sous « Réduire les animations » : fondus seuls, bulle fixe,
ni particules ni rebond.

**Mascotte.** `KiwiMascotte` (« Le regard ») : Réglages (ligne Premium, 44 pt, immobile) et feuille
Premium (84 pt, animée, `KiwiMascotteHalo`). Partout ailleurs : le signe `KiwiSigne`.

**Règles d'écran.**

- **Titre d'onglet.** Journal et Progrès masquent la barre de navigation et dessinent leur titre
  dans la page (`DSLargeTitle`, 34/700) ; Compléments aussi, en une ligne de 17/600 centrée qui
  défile avec le contenu. Plan et Réglages gardent le grand titre natif `.large`. Le
  `navigationTitle` reste posé partout (nom de l'écran pour VoiceOver).
- **Page poussée dans un onglet** : `VerrePageFond()` en fond et `.kiwiTabBarBottomInset()` sur son
  contenu (la réserve posée sur la racine de l'onglet ne se propage pas). Si elle masque la barre
  native, elle dessine son propre retour (page d'un micronutriment : « ‹ Journal »).
- **Feuille** : `.verreFeuille()` sur le contenu, coins de 38 (`healthMapSheet` et ses variantes ne
  posent que les détentes et le rayon). Action principale d'une feuille : 54 pt
  (`Verre.hauteurAction`), soit `DSCapsuleButton(hauteur:brillance:)`, soit `PremiumAction`.
- **Contenu verrouillé** : un seul traitement, flou 8 et opacité 0,5 (`GateIntensity`, les deux cas
  ont les mêmes valeurs), sans voile blanc.
- **Entrées** : les onglets restent montés, donc tracés d'anneaux et cascades se rejouent sur
  `\.estOngletActif`, pas sur `onAppear`.

**Briques écrites par les écrans, utilisées à plusieurs endroits.** Elles vivent hors du socle ;
avant d'en écrire une de plus, prendre celle-ci.

| Brique | Fichier | Ce que c'est | Où |
|---|---|---|---|
| `DSLargeTitle` | `KiwiDS.swift` | titre d'onglet 34/700 (−0,95) dessiné dans la page | Journal, Progrès |
| `VerrePuce` + `VerrePastilleIcone` | `KiwiVerre.swift` | rangée de puces d'en-tête qui défile à l'horizontale (`.scrollClipDisabled()` pour l'ombre) | Journal (Eau · Poids · Série · Analyses), Progrès (Équilibre · évolutions · Série) |
| `JournalAnneau` | `MealScan/JournalComponents.swift` | anneau dont le trait tient DANS sa boîte et qui se retrace en 1 s (`trace`) ; `DSRing`, lui, déborde de la moitié de son trait | carte Énergie, « Apports à renforcer » |
| Libellé de catégorie | `ScanCardHeader` (`ScanHomeComponents.swift`) · `BilanV7SectionLabel(teinte:)` (`BilanV7Components.swift`) · `PlanTitreDeBloc` (`PlanSolutionsComponents.swift`) | icône dans la teinte + 15/600 dans la teinte foncée ; trois écritures du même motif | cartes du Journal, du Bilan, feuilles du Plan |
| `DSCapsuleButton(hauteur:brillance:)` | `KiwiDS.swift` | action principale en verre vert ; 50 pt par défaut, 54 pt et reflet périodique pour conclure une feuille | partout |
| `PremiumAction` | `Shared/PremiumGating.swift` | action de feuille Premium : verre vert 54 pt, reflet qui passe sous le texte, état de chargement | `PaywallView`, `OffreAnnuelleOverlay` |
| `PremiumPastille` · `GatedOverlay(pastille:zone:)` | `Shared/PremiumGating.swift` | pastille de verre vert de 36 pt (cadenas + bénéfice) posée sur un contenu flouté | `BlurredSection` ; Progrès a la sienne, `ProgresBoutonOffre` (doublon à fusionner) |
| `.feuillePremium(isPresented:source:)` · `.premiumOrigine(_:dans:)` / `.premiumDepuis(_:dans:)` | `Shared/PremiumGating.swift` | la feuille Premium grandit depuis ce qu'on touche (zoom iOS 18 et plus ; `.sheet` simple sur iOS 17) | `UnlockDoor`, `PremiumTeaseCard`, `PremiumPastille` ; Réglages et Progrès par la paire origine / depuis |
| `VerreMatiere.feuilleDetachee` · `.verreFeuilleDetachee()` | `MealScan/VoiceMealSheet.swift` | feuille détachée des bords : rayon 44, blanc 88 → 72 % sur flou vivant, ombre vers le haut ; les marges de 8 sont à l'appelant | résultats de dictée, `GratificationOverlay` |
| `ReglageLigne` · `ReglagePastille` · `ReglageFilet` | `Profile/ReglagesView.swift` | ligne de 50 pt à pastille CARRÉE (30 × 30, rayon 8) et filet posé sous le libellé seul | Réglages, ses sous-pages, questionnaire en édition, Widgets |
| Champ en verre | `reglageChampVerre()` (`ReglagesView.swift`) · `authChampVerre()` (privé à `AuthSupportViews.swift`) | verre clair, rayon `Verre.rayonTuile`, hauteur plancher de 50 ; deux copies de la même plaque | connexion, Réglages |
| `ProgresLigneAction` | `Checkin/ProgresV3Components.swift` | ligne d'action en verre : pastille ronde de 40 vert pâle, deux lignes, chevron vert | check-in du jour, récap du jour |
| `.bilanCascade(_:)` · `BilanVerre` | `Questionnaire/BilanComposants.swift` · `BilanTheme.swift` | cascade d'un écran du questionnaire (0,08 s + 0,05 s par rang) ; matières dérivées du socle (réponse choisie = `clairActif`) | questionnaire |
| Jauge de ligne | écrite sur place | une barre qui se remplit sur `timingCurve(0.3, 1.1, 0.4, 1, duration: 0.8)`, piste `Verre.remplissage` en capsule ; pas de jeton dans `KiwiMotion` | fiche d'un apport, fiche Compléments, fiche repas, fiche aliment |
| Liste de résultats | écrite sur place (`sectionCarte` / `carteResultats`) | UNE carte de verre par section, lignes séparées d'un filet aligné sur le texte (`DSSeparator(retrait: 72)`) : jamais une plaque de verre par ligne dans une liste qui défile ; le « + » rapide est un verre vert sans ombre (`matierePlus`, privé à `JournalEditorComponents.swift`) | les trois recherches d'aliment (`FoodSearchSheet`, recherche du Journal, remplacement d'un aliment dicté) |

Ne sont pas dans le socle et restent écrits en dur : le chiffre héros en SF Pro Rounded
(`.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()`), le titre de feuille
24/700, la pastille numérotée (rond `dsAccentPale` de 30 pt, chiffre 15/700 `teinteKiwiTexte`),
l'étiquette d'état (13/600 sur la teinte à 14 %), une encre rouge foncée pour le texte « à combler ».

---

## Socle « qualité Apple » (23 août 2026)

Trois règles portent 80 % de l'écart perçu :

1. ~~Fond neutre~~ → **fond de verre** (voir « Verre liquide » ci-dessus). `Color.dsFond` (#EEF2EC)
   ne sert plus qu'aux surfaces qui doivent rester opaques.
2. **Le vert `Color.dsAccent` ne colore que ce qui se tape** : onglet actif, bouton, lien, `+`,
   chevron d'action. Les chiffres sont noirs (`dsTexte`). Seules les jauges gardent une couleur
   de statut (`dsACombler` #FF3B30, `dsARenforcer` #F1961D, `dsCalories` #F07040) ; macros :
   `dsProteines` #4E82E5, `dsGlucides` #E6B731, `dsLipides` #F18336, `dsFibres` #4CAC91.
3. **Un seul chiffre héros par écran** (`.dsHeros48`), puis deux niveaux décroissants.

| Token | Valeur |
|---|---|
| Neutres | `dsTexte` (label) · `dsSecondaire` (secondaryLabel) · `dsTertiaire` (tertiaryLabel) · `dsSeparateur` (separator, 0,5 pt) · `dsRemplissage` (`rgba(120,120,128,.12)`) · `dsTrait` (#D1D1D6) |
| Typo (SF Pro, ≤ 700) | `dsGrandTitre` 34/700 · `dsSection` 22/700 · `dsHeadline` 17/600 · `dsCorps` 17/400 · `dsSousTitre` 15/400 · `dsLegende` 13/400 · chiffres `dsHeros48`, `dsHeros34`, `dsValeur24`, `dsValeurLigne` (tabulaires) |
| Tracking | `DSTracking` : −0,95 grand titre · −0,55 section · −0,4 corps · −0,2 sous-titre · −2,2 héros 48 |
| Cartes | `.dsCard()` : verre dépoli, rayon 24 continu, liseré blanc intérieur, ombre douce découpée |
| Listes | `DSGroupedList` + `DSRow` + `DSSeparator(retrait: 49 avec icône / 16 sans)` |
| Jauges | `DSGauge` (4 pt, animée 1 s easeOut, cascade 50 ms) · `DSRing` (92 pt, trait 9) |
| Boutons | `DSCapsuleButton` (50 pt, capsule, verre vert ; `hauteur:` 54 et `brillance:` pour l'action d'une feuille) · `DSLinkRow` (lien vert de fin de carte) · `DSCloseButton` (rond de verre de 36) · `.dsPress` (0,96 + assombrissement, ressort `kiwiVif`) ; `.healthMapPressed` en est un alias |
| Mouvement | `KiwiMotion.swift` : `kiwiVif` · `kiwiGlisse` · `kiwiFluide` · `kiwiRebond` · `kiwiCompteur`, échelles `KiwiEchelle` (rien au-dessus de 1,22), `ChiffreQuiCompte`, `.kiwiImpulsion(_:)`, `.kiwiRecompense(_:)` |
| Gestes | `KiwiGestes.swift` : `CompteurAjouts` (recherche) · `.kiwiSecousse(_:)` + `Butee` (la quantité fait non de la tête, une fois par appui). Un « − / + » de quantité = `Button` + `.buttonRepeatBehavior(.enabled)` (maintien accéléré système). La coche d'un ajout rapide = `verrePop` + `verreGerbe` |
| Formats | `DS.entier(1021)` → `1 021` · `DS.pourcent(42)` → `42 %` · `DS.decimal(5.9)` → `5,9` (espace fine U+202F) |
| Navigation | `KiwiFloatingTabBar` (capsule de verre de 62, pastille qui glisse, 5 onglets) · titre d'onglet : dessiné dans la page pour Journal et Progrès (`DSLargeTitle`) et Compléments (17/600), grand titre natif `.large` pour Plan et Réglages (voir « Règles d'écran ») |

Vocabulaire imposé (CI) : « apports à renforcer », « à combler », « besoins », jamais les quatre
mots proscrits par `VoiceComplianceTests`. Aucun emoji dans l'interface (seule exception : le kiwi 3D
du Plan).

---

## Hiérarchie de l'information

> Charte validée par le fondateur le 17 août 2026, à partir de l'audit des
> 5 onglets (~700 textes inventoriés, 48 anomalies localisées fichier:ligne).
> Rapports : `Healthmap/audit-hierarchie-2026-08-17/`.

### Le problème que ces tokens résolvent

L'app portait **13 à 18 tailles de police par écran** et **50 à 71 % de textes
en gras** : des paliers 13 / 13.5 / 14 / 14.5 / 15 indiscernables à l'œil, donc
une hiérarchie nulle. Les écrans riches (Bilan v7, Scan, Suivi, Compléments,
Plan) n'utilisaient **aucun** token et écrivaient 100 % de leurs polices en
`.system(size:weight:)` littéral. Les tokens existaient mais décrivaient une
**taille** (`titleFont`, `captionFont`), jamais un **rôle** : personne ne
savait lequel prendre, donc personne n'en prenait.

### Les 5 rôles

Tout texte de l'app est l'un de ces cinq rôles. Le rôle décide du token.

1. **Titre** (écran / sheet / section) — annonce, ne rivalise jamais avec le contenu.
2. **Donnée-héros** — LA réponse de la carte : l'aliment, le pourcentage, le geste, la mesure.
3. **Conclusion / insight** — ce que les données veulent dire.
4. **Donnée secondaire & habillage** — libellés, unités, dates, mentions.
5. **CTA** — l'action ; jamais plus lourd que ce qu'il sert.

### L'échelle : 8 tailles, pas une de plus

**10.5 · 11.5 · 12 · 13 · 15 · 17 · 20 · 28**

Six d'entre elles tombent exactement sur un text style iOS à la taille système
par défaut, ce qui permet de garder **Dynamic Type** :

| Taille | Text style iOS | Token |
|---|---|---|
| 28 | `.title` | `screenTitleFont`, `heroValueFont` |
| 20 | `.title3` | `sheetTitleFont` |
| 17 | `.body` | `conclusionFont`, `heroTextFont` |
| 15 | `.subheadline` | `insightFont`, `heroValueRowFont`, `ctaFont` |
| 13 | `.footnote` | `sectionLabelFont` |
| 12 | `.caption` | `dataSecondaryFont` |
| 11.5 | *(aucun : `.caption2` vaut 11)* | `subLabelFont` — taille fixe |
| 10.5 | *(aucun)* | `chromeFont` — taille fixe |

### La grille rôle → style

| Rôle | Token | Style | Encre |
|---|---|---|---|
| Titre d'écran | `Theme.screenTitleFont` | 28 / heavy / rounded / `tracking(Theme.screenTitleTracking)` | encre neutre |
| Titre de sheet | `Theme.sheetTitleFont` | 20 / bold | `kiwiCharcoal` |
| **Titre de section** | `Theme.sectionLabelFont` | **13 / bold** + icône 15 semibold | **couleur du domaine**, jamais l'encre neutre |
| Sous-label discret | `Theme.subLabelFont` | 11.5 / bold | `healthMapSecondary` / `healthMapMuted` |
| **Conclusion (pic de la carte)** | `Theme.conclusionFont` | **17 / heavy** / `tracking(Theme.conclusionTracking)` / **jamais de `lineLimit`** | encre la plus foncée |
| Conclusion secondaire, verdict de ligne | `Theme.insightFont` | 15 / semibold | encre foncée |
| **Donnée-héros chiffrée de carte** | `Theme.heroValueFont` | **28 / bold / rounded / monospacedDigit** | encre du statut |
| **Donnée-héros chiffrée de ligne** | `Theme.heroValueRowFont` | **15 / heavy / rounded / monospacedDigit** | encre du statut |
| **Donnée-héros textuelle** (aliment, produit, geste) | `Theme.heroTextFont` | 17 / heavy | `kiwiCharcoal` |
| Donnée secondaire | `Theme.dataSecondaryFont` | 12 / medium | `healthMapSecondary` |
| Habillage (unité, date, mention) | `Theme.chromeFont` | 10.5 / medium | `healthMapMuted` |
| CTA primaire | `Theme.ctaFont` | 15 / semibold, h48, **sans ombre**, un seul par carte | blanc sur `kiwiGreen` |
| CTA secondaire | `Theme.ctaFont` (14 accepté) | bold, h48, **aucun fond coloré** | `kiwiInk` sur gris 5 % |
| Statut / pastille | `Theme.subLabelFont` | heavy, capsule `fill(couleur.opacity(0.14))` | encre du statut |

Le token ne porte **que la police**. La couleur (encre du domaine, encre du
statut) et le tracking restent à la charge de l'appelant : c'est voulu, une
même police sert plusieurs domaines.

### Les 3 règles d'arbitrage

Elles tranchent les 48 anomalies recensées. En cas de doute sur un écran,
elles font foi.

1. **Un titre de section n'est jamais neutre et jamais gros.**
   13 / bold + couleur de domaine. Sa **couleur** le signale, sa **taille** le
   range SOUS le contenu. Un titre de section en 16 ou 17 pt d'encre neutre est
   un bug de hiérarchie, pas un choix.

2. **La conclusion est le plus gros texte de sa carte** (17 / heavy, encre la
   plus foncée). Un texte plus gros dans la même carte est soit un titre
   déguisé, soit un CTA hypertrophié : dans les deux cas il redescend.

3. **Une donnée-héros ne descend jamais sous 15 pt** (rounded +
   monospacedDigit pour les chiffres). Dans son bloc elle porte la **plus
   grande taille ET l'encre la plus foncée** ; son titre, son kicker, son unité
   et son CTA sont **tous** strictement plus petits ou plus pâles qu'elle.
   Aucun habillage ne porte de fond coloré si la donnée-héros n'en porte pas.

### Comment vérifier

- `HealthMapTests/HierarchieTokensTests.swift` garde le contrat : les 12 tokens
  existent, ils sont distincts, aucune taille littérale hors échelle n'entre
  dans le bloc de rôle, et les 6 text styles iOS utilisés valent bien
  28 / 20 / 17 / 15 / 13 / 12 à la taille système par défaut.
- Revue d'écran : `grep -n '\.system(size:' HealthMap/Views/<écran>` doit
  tendre vers zéro. Chaque occurrence restante doit se justifier par un rôle
  qui n'existe pas dans la grille.

### État d'application

Les tokens sont posés (août 2026) mais **encore appliqués nulle part** : les
écrans migrent vague par vague, dans l'ordre du trafic (Scan → Bilan →
Compléments → Plan → Suivi), une PR par vague avec captures avant / après.

---

## Autres tokens

| Famille | Constantes | Fichier |
|---|---|---|
| Espacement | `spacingXS` 4 · `spacingSM` 8 · `spacingMD` 16 · `spacingLG` 24 · `spacingXL` 32 · `spacingXXL` 48 | `ThemeConstants.swift` |
| Rayon | `cornerRadiusSM` 10 · `cornerRadius` 16 · `cornerRadiusLG` 20 · `cornerRadiusPill` 100 | `ThemeConstants.swift` |
| Ombres | `shadowCard` · `shadowElevated` · `shadowFloating` · `shadowBrandGlow` | `ThemeConstants.swift` |
| Opacités | `opacitySubtle` .04 → `opacityOverlay` .25 | `ThemeConstants.swift` |
| Polices historiques (taille) | `titleFont` · `headlineFont` · `subheadlineFont` · `bodyFont` · `captionFont` · `captionBoldFont` | `ThemeConstants.swift` |
| Palette | `kiwiGreen` · `kiwiCharcoal` · `kiwiGreenInk` · `healthMapSecondary` · `healthMapMuted` · teintes de section | `Color+Theme.swift` |

Les 6 polices historiques restent en place et inchangées : elles décrivent une
taille, les 12 nouvelles décrivent un rôle. Aucune n'est un alias de l'autre.
