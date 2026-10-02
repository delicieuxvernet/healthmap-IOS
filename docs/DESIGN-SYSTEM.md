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
| Boutons | `DSCapsuleButton` (50 pt, capsule, verre vert) · `DSLinkRow` (lien vert de fin de carte) · `DSCloseButton` (rond de verre de 36) · `.dsPress` (0,96 + assombrissement, ressort `kiwiVif`) |
| Mouvement | `KiwiMotion.swift` : `kiwiVif` · `kiwiGlisse` · `kiwiFluide` · `kiwiRebond` · `kiwiCompteur`, échelles `KiwiEchelle` (rien au-dessus de 1,22), `ChiffreQuiCompte`, `.kiwiImpulsion(_:)`, `.kiwiRecompense(_:)` |
| Formats | `DS.entier(1021)` → `1 021` · `DS.pourcent(42)` → `42 %` · `DS.decimal(5.9)` → `5,9` (espace fine U+202F) |
| Navigation | `KiwiFloatingTabBar` (capsule de verre de 62, pastille qui glisse, 5 onglets) · grands titres natifs `.large` |

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
