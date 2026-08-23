# DESIGN-SYSTEM.md — tokens visuels Kiwio iOS

> Source de vérité des **tokens** (police, espacement, rayon, ombre, couleur).
> La structure des écrans, elle, vit dans `DESIGN-PAGES.md` à la racine.
> Fichiers de code : `HealthMap/Views/Shared/KiwiDS.swift` (**DS de la refonte
> du 23 août 2026, à consommer sur tout écran refondu**), puis les tokens
> historiques `HealthMap/Views/Shared/ThemeConstants.swift` et
> `HealthMap/Utilities/Color+Theme.swift` (basculés sur le socle neutre).

---

## Socle « qualité Apple » (23 août 2026)

Trois règles portent 80 % de l'écart perçu :

1. **Fond neutre** `Color.dsFond` (`systemGroupedBackground`, #F2F2F7). Le crème ne survit
   qu'en voile de marque sur 240 pt (`DSBrandWash`, `DSPageBackground`).
2. **Le vert `Color.dsAccent` ne colore que ce qui se tape** : onglet actif, bouton, lien, `+`,
   chevron d'action. Les chiffres sont noirs (`dsTexte`). Seules les jauges gardent une couleur
   de statut (`dsACombler` #FF3B30, `dsARenforcer` #FF9500, `dsCalories` #FF6B35) ; macros :
   `dsProteines` #3B82F6, `dsGlucides` #34C759, `dsLipides` #FFCC00.
3. **Un seul chiffre héros par écran** (`.dsHeros48`), puis deux niveaux décroissants.

| Token | Valeur |
|---|---|
| Neutres | `dsTexte` (label) · `dsSecondaire` (secondaryLabel) · `dsTertiaire` (tertiaryLabel) · `dsSeparateur` (separator, 0,5 pt) · `dsRemplissage` (#EFEFF4) · `dsTrait` (#D1D1D6) |
| Typo (SF Pro, ≤ 700) | `dsGrandTitre` 34/700 · `dsSection` 22/700 · `dsHeadline` 17/600 · `dsCorps` 17/400 · `dsSousTitre` 15/400 · `dsLegende` 13/400 · chiffres `dsHeros48`, `dsHeros34`, `dsValeur24`, `dsValeurLigne` (tabulaires) |
| Tracking | `DSTracking` : −0,95 grand titre · −0,55 section · −0,4 corps · −0,2 sous-titre · −2,2 héros 48 |
| Cartes | `.dsCard()` : blanc, rayon 14 continu, **aucune ombre, aucune bordure** |
| Listes | `DSGroupedList` + `DSRow` + `DSSeparator(retrait: 49 avec icône / 16 sans)` |
| Jauges | `DSGauge` (4 pt, animée 1 s easeOut, cascade 50 ms) · `DSRing` (92 pt, trait 9) |
| Boutons | `DSCapsuleButton` (50 pt, capsule) · `DSLinkRow` (lien vert de fin de carte) · `.dsPress` (0,97 + assombrissement) |
| Formats | `DS.entier(1021)` → `1 021` · `DS.pourcent(42)` → `42 %` · `DS.decimal(5.9)` → `5,9` (espace fine U+202F) |
| Navigation | `KiwiFloatingTabBar` (capsule, 5 onglets) · `DSAddButton` (60 pt) · grands titres natifs `.large` |

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
