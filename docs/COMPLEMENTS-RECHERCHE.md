# Compléments : doctrine, cadre et table symptômes

> Document de travail interne, ouvert le 20 septembre 2026.
> **Ne part pas chez Claude Design.**
>
> Il répond à une question : quel complément recommander à qui, sous quelle
> forme, avec quelle référence — et comment le justifier.

---

## 1. Les décisions (Arthur, 20 septembre 2026)

1. **Profondeur** — les 10 nutriments d'un coup.
2. **Gamme** — accessible. *Pas de gamme végétale à créer : tous les produits
   du catalogue sont véganes sauf l'huile de poisson.*
3. **Validation médicale** — Arthur valide le contenu avant mise en ligne.
   La table du § 4 a été validée le 20 septembre.
4. **Dosages** — **on n'affiche pas les doses journalières.** On conseille le
   complément ; la posologie appartient au fabricant et à la personne.
5. **Formes** — **on recommande toujours la forme la mieux absorbée et la
   mieux supportée sur la durée.** Bisglycinate pour le fer, le magnésium et
   le zinc ; D3 huileuse pour la vitamine D. Le prix arbitre *à qualité
   égale*, jamais contre elle : on ne veut pas d'effets indésirables.

**Ce que la décision 5 a réglé sans qu'on s'y attende.** Deux références
dépassaient ce que l'ANSES juge prudent. On aurait pu répondre par une
précaution affichée ; on a répondu par la forme, ce qui fait disparaître le
problème au lieu de l'annoter. Elle a aussi fermé la question du calcium
citrate : sous la règle « une seule meilleure forme », le carbonate pris au
repas suffit, y compris quand l'acidité gastrique est réduite.

**Ce que la décision 4 ne règle pas**, et qu'il faut se dire : ne plus écrire
la dose ne nous dégage pas du produit vers lequel on envoie. C'est la
décision 5 qui nous couvre, pas le silence sur le chiffre.

---

## 2. Le cadre réglementaire

### 2.1 — Hiérarchie des sources

1. Textes et avis officiels : arrêté du 9 mai 2006, **avis ANSES du 31 juillet
   2024** (saisine 2023-SA-0165), règlement (UE) 432/2012 pour les allégations.
2. Essais cliniques et revues systématiques, pour départager deux formes.
3. Fiches techniques fabricant, uniquement pour la composition d'un produit.

**Exclus** : blogs affiliés, comparatifs sponsorisés, avis clients.

### 2.2 — Doses maximales, et le catalogue en face

L'avis de 2024 donne la dose journalière maximale (DJM) proposée pour les
adultes **et** l'avis du comité, qui ne la suit pas toujours. C'est la source à
jour : le texte de 2006 place encore la vitamine D à 5 µg.

| Nutriment | DJM proposée | Avis du comité | Notre produit | |
|---|---|---|---|---|
| Vitamine D | 50 µg (2000 UI) | approuvé | 2000 UI | au plafond |
| Vitamine C | 1000 mg | approuvé | 1000 mg | au plafond |
| Vitamine B12 | *quantum satis* | pas de limite | 1000 µg | ok |
| Vitamine B6 | 12,5 mg | — | 2 mg | large marge |
| Calcium | 800 mg | approuvé | 500 mg | ok |
| Fer | 14 mg | approuvé | 14 mg | au plafond |
| Iode | 150 µg — **200 µg** enceintes/allaitantes | approuvé | 150 µg | au plafond |
| Magnésium | 360 mg | **« ne devrait pas dépasser 250 mg »** | 225 mg | ok *(corrigé)* |
| Zinc | 15 mg | **« ne devrait pas dépasser 9,7 mg »** | 10 mg | à la limite *(corrigé)* |

Le repère de 40 mg pour le fer n'est pas une limite de sécurité au sens strict,
mais un niveau sans risque fondé sur l'apparition de selles foncées.

**Reste ouvert :** l'iode est servi à 150 µg à tout le monde alors que l'ANSES
autorise 200 µg pendant la grossesse et l'allaitement, où le besoin est plus
élevé.

### 2.3 — Allégations

Seules les formulations du règlement 432/2012 sont utilisables. « Contribue à
réduire la fatigue » est autorisé pour le fer, la B12, le magnésium et la
vitamine C. **Rien n'est autorisé sur l'humeur ni sur le sommeil.** Aucune
promesse thérapeutique. Recommander des marques engage notre responsabilité
éditoriale ; toute affiliation devra être déclarée visiblement.

---

## 3. Le catalogue sous la doctrine

| Nutriment | Forme retenue | État |
|---|---|---|
| Fer | bisglycinate | déjà conforme |
| Vitamine D | D3 huileuse, lichen | déjà conforme |
| Oméga-3 | triglycérides · algue si régime végétal | déjà conforme |
| Vitamine C | acide ascorbique · liposomale si estomac sensible | déjà conforme |
| Iode | iodure de potassium ou algue standardisée | déjà conforme |
| Fibres | psyllium · guar ou acacia si intestin sensible | déjà conforme |
| Calcium | carbonate **pris au repas** | déjà conforme |
| Magnésium | bisglycinate | **changé** — Dynveo TRAACS, 75 mg/gélule |
| Zinc | bisglycinate | **changé** — la référence à 15 mg est sortie |
| Vitamine B12 | forme stable, bien absorbée | argument de vente corrigé |

Catalogue : 19 → 18 produits.

**Sur la B12.** La supériorité clinique de la méthylcobalamine sur la
cyanocobalamine n'est pas établie aux doses d'entretien — ce sont les formes
classiques qui ont servi aux essais montrant que la voie orale vaut
l'injection. Ce qui justifie la référence à 1000 µg, c'est la **dose** : au-delà
de quelques microgrammes, la B12 passe surtout par diffusion passive, ce qui
compte quand l'absorption est réduite (âge, metformine, IPP).

**Sur le magnésium.** Les formes restent documentées pour mémoire — citrate
quand le transit est lent, malate pour l'énergie (preuve faible) — mais elles
ne sont plus servies. La doctrine prime : une seule meilleure forme.

---

## 4. La table symptôme → apport

Implémentée dans `HealthMap/Core/SymptomesApports.swift`, validée le
20 septembre.

**Le principe, qui ne doit jamais s'inverser :** c'est le **score**, calculé sur
l'alimentation déclarée, qui décide si un apport est à renforcer. Le symptôme
ne décide de rien — il explique pourquoi ça peut compter, et il arrive
*après*. On n'écrit jamais « tu perds tes cheveux, donc ton fer est bas ».

| Niveau | Règle |
|---|---|
| **fort** | spécifique et bien établi, se dit seul |
| **modéré** | établi mais peu spécifique, se dit puisque le score est déjà bas |
| **faible** | croyance répandue, preuve mince — **jamais seul** |

**Sept symptômes sur dix-huit ne déclenchent rien, volontairement :** l'humeur
et la motivation (aucune allégation autorisée, liens trop minces), le
saignement digestif (il coupe la chaîne au lieu de l'alimenter), et les trois
signaux digestifs qui orientaient une forme de prise — la doctrine les a rendus
sans objet.

Un point contre-intuitif à tenir : **les crampes ne font pas parler le
magnésium à elles seules.** La croyance est massive, la preuve qu'une
supplémentation les réduit est mince.

---

## 5. Ce qui a été corrigé, et ce qui reste

**Corrigé et mergé** — PR #248 et #250.

- L'avertissement des fibres sur les médicaments ne s'affichait jamais.
- La précaution hémochromatose manquait sur une des deux vitamines C.
- `thyroid_med` était capté et ignoré : iode, fer et calcium sont désormais
  signalés.
- Le conseil « IPP + calcium » renvoyait vers un citrate absent du catalogue.
- Les doses journalières ne s'affichent plus, aux trois endroits où elles
  apparaissaient — y compris dans le PDF exporté.

**Reste ouvert.**

1. **Le prompt de `generate-analysis`** (dépôt web) demande toujours des doses
   au modèle. Son exemple de référence contient **25 mg/j de fer**, au-dessus
   du maximum français de 14 mg. On ne les affiche plus, on continue de les
   produire et de les stocker. À traiter avec son propre déploiement et la
   vérification sur les trois profils d'audit.
2. **Les questions manquantes au questionnaire** — thyroïde, hémochromatose,
   insuffisance rénale, allergie au poisson. Sans elles, les contre-indications
   ne peuvent pas filtrer, seulement avertir. Décision produit : ajouter des
   questions change l'inscription pour tout le monde.
3. **L'iode pendant la grossesse** (§ 2.2).
4. **Une passe complète de vérification du catalogue.** `catalogVerifiedAt`
   reste au 20 juillet 2026 : seul le magnésium a été vérifié sur la fiche
   officielle le 20 septembre.

---

## Sources

- ANSES, avis du 31 juillet 2024, saisine 2023-SA-0165 — <https://www.anses.fr/fr/system/files/NUT2023SA0165.pdf>
- ANSES, avis NUT2020SA0105 (magnésium, juillet 2020) — <https://www.anses.fr/fr/system/files/NUT2020SA0105.pdf>
- Arrêté du 9 mai 2006, annexe III — <https://www.legifrance.gouv.fr/loda/id/JORFTEXT000000637294>
- Règlement (UE) 432/2012 — <https://eur-lex.europa.eu/eli/reg/2012/432/oj/fra>
- Fer un jour sur deux — Stoffel et coll., *Lancet Haematology* 2017 — <https://pubmed.ncbi.nlm.nih.gov/29032957/>
- Fer, essai sans avantage clinique, *eClinicalMedicine* — <https://www.thelancet.com/journals/eclinm/article/PIIS2589-5370(23)00463-7/fulltext>
- Calcium carbonate vs citrate en acidité réduite — *NEJM* 1985 — <https://www.nejm.org/doi/full/10.1056/NEJM198507113130202>
- B12, formes et voies d'administration — revue systématique 2025 — <https://www.frontiersin.org/journals/pharmacology/articles/10.3389/fphar.2025.1602976/full>
- Magnésium citrate vs oxyde — essai croisé randomisé — <https://link.springer.com/article/10.1186/s40795-016-0121-3>
- EFSA, magnésium L-thréonate, nouvel aliment 2024 — <https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2024.8656>
- Fiche produit du magnésium retenu — <https://www.dynveo.fr/products/magnesium-bisglycinate>
