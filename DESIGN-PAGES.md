# DESIGN-PAGES.md — Architecture de référence des écrans Kiwio

> 🥝 **Kiwio = HealthMap** (marque renommée juin 2026 ; noms internes `HealthMap`/`fr.healthmap.app`/`healthmap.fr` inchangés).

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

## ⭐⭐⭐ Identité : un seul logo, partout (maquette finale, 22 sept. 2026)

> **Source** : `Kiwio - FINAL pour codage (standalone) (1).html` (Downloads), section « Identité ».
> **Le signe** : la tranche de kiwi de face, version 2 validée : peau `#2F5A16` · chair
> `#5DA838` · halo `#9FD46F` · cœur `#EAF3DE` · 12 graines. Aplats nets, aucun dégradé. Dessiné
> en SwiftUI à partir du SVG source (`Views/Shared/KiwiSigne.swift`, géométrie sur 100 tenue point
> par point par `KiwiSigneTests`) : variantes **standard** (peau qui cerne), **sur-vert** (sur fond
> vert kiwi, la peau disparaît : l'icône), **mono** (disque d'une encre, cœur et graines évidés).
> **Il remplace TOUS les dessins d'avant** : `KiwiContourMark` (le kiwi au trait), `MascotView` (la
> mascotte souriante) et `KiwiWalkerView` (le kiwi qui marche) sont **supprimés**, avec les couleurs
> `mascot*` ; la feuille du centre de la page de garde et le kiwi 3D de l'écran de connexion aussi.
>
> | Emploi | Composant | Où |
> |---|---|---|
> | Icône Apple | `AppIcon.png`, variante sur-vert, 1024 opaque | le springboard |
> | Écran de chargement | `LaunchScreenView` : signe 72 pt au centre EXACT de l'écran + « Kiwio » 22 pt dessous | au lancement |
> | Lancement statique | `Info.plist` `UILaunchScreen` : fond `LaunchScreenBackground` (#F2F2F7 / noir) + image `LaunchSigne` (72 pt) | avant le premier écran SwiftUI : même place, le passage ne bouge pas |
> | Attente | `KiwiLoader` : **les pépins qui chargent**, une traînée qui fait **un tour en 1,8 s** (partie de la couronne pleine en 0,35 s) ; Reduce Motion = signe figé | lancement, analyse, questionnaire, Plan, Compléments, scan photo, dictée, historique, Apple |
> | En-tête | `KiwiEnTete` (signe 72 + nom 22) | connexion ; l'onboarding en grand (signe 120 + nom 34) |
> | Barre de l'app | `KiwiLockupBarre` (signe 26 + nom 19) | haut de la page de garde, carte du récap partageable |
> | Confirmation | `KiwiConfirmation` (signe 44 dans un rond 72 couleur cœur) | « Bienvenue dans Kiwio Premium » |
> | Signe seul | `KiwiSigne(taille:)` | Brief du jour, paywall, ouverture du récap, états vides (Plan, historique), centre de l'anneau de la page de garde |
> | Pied de page | `KiwiPiedDePage` (signe mono 20 + nom 16 + version) | bas des Réglages, suivi de « Ne remplace pas un avis médical » |
>
> Le nom : « Kiwio » en SF Pro Rounded gras, serré (-0,045 × la taille) : `KiwiWordmark`. Plus de
> « kiwi » + « o » vert. Règle de la maquette : sous 32 pt, le signe seul.

## ⭐⭐ Refonte « qualité Apple » (direction du 23 août 2026 — socle iOS natif)

> **Sources de vérité** : `Kiwio iOS - refonte.dc.html` (maquette, **10 écrans** dans sa
> version du 23 août 11:52, `C:\Users\stana\AppData\Local\Temp\` ; la v1 à 7 écrans est dans
> `Downloads`) et `instructions-claude-code-refonte-ios.md` (document d'implémentation,
> `Downloads`). Cette direction **remplace** la DA crème/vert ci-dessous : le fond
> devient neutre (`systemGroupedBackground`), le vert ne colore que ce qui se tape, un seul chiffre
> héros par écran, cartes blanches rayon 14 **sans ombre**, gras plafonné à 700, chiffres SF Pro
> tabulaires. Tokens : `HealthMap/Views/Shared/KiwiDS.swift` (préfixe `ds`).
>
> **Navigation (5 onglets, capsule flottante)** : **Journal · Progrès · Plan · Compléments · Réglages**.
> Le Bilan a fusionné dans le Journal (son écran complet reste accessible par « Tout afficher »,
> en feuille, sans paywall) ; le Scan est devenu le bouton `+` flottant du Journal et sa feuille
> d'ajout à 6 entrées (dicter · scanner · rechercher · code-barres · ma journée · activité) ; les
> Réglages sont le **seul** endroit qui parle d'argent (carte Premium, prix et essai lus depuis StoreKit).
>
> **Écrans** :
> - **Journal** (`MealScanView.swift` → `JournalView`, `JournalComponents.swift`) — **maquette
>   « Journal & Progrès v2 » du 20 septembre 2026** : barre de jour (chevrons + calendrier sans borne,
>   décision du 11 septembre, conservée à la place du semainier de la maquette) · carte calories
>   (héros + anneau 88 en dégradé + ligne **Apple Santé** qui ouvre l'activité du jour) · **macros en
>   quatre lignes** (protéines · glucides · lipides · fibres) avec objectif et **surplus en hachures,
>   lu selon l'objectif de la personne** (vert seulement pour les protéines de qui veut prendre du
>   muscle, orangé sinon ; fibres : référence canonique 30 g) · **la saisie SUR la page** : « Dicter »
>   (seule surface verte — **la bulle kiwi surgit au-dessus du bouton** (voir « Dicter, être écouté,
>   être félicité » plus bas) : **un toucher = mains libres, on touche la bulle pour terminer ; un
>   appui maintenu = elle vit tant que le doigt tient, relâcher analyse, glisser à gauche jette,
>   glisser vers le haut verrouille** ; `AppuiDicter`, seuils `DicteeGeste`) et « Photographier », puis « Autres façons d'ajouter » qui déplie Écrire ·
>   Rechercher · Code-barres (« Écrire » **ouvre la feuille d'analyse sur un champ de texte, clavier levé** — depuis le 21 sept. : l'app ignorant la zone du clavier à sa racine, un champ posé sur la page finissait caché derrière lui, sans sortie ; même analyse et même quota que la dictée) ·
>   « Apports à renforcer » (la phrase de l'interaction, **trois anneaux** à la couleur de l'apport,
>   une sortie verte) · le jour en **mosaïque** de quatre repas (le toucher ouvre **la fiche de CE repas**, `FicheRepasSheet` : ce que tu as saisi, modifiable · « Ce qu'il t'a apporté », macro par macro avec sa part de la cible du jour · vitamines et minéraux · un constat, jamais un geste).
>   **Le bouton `+` flottant et sa feuille d'ajout ont disparu.** **Avant le questionnaire** : la
>   saisie d'abord, puis « On ne connaît pas encore tes besoins » (porte), « En attendant, en France »
>   (`TeaserStatsCatalog`, jamais un chiffre inventé), « À la fin du questionnaire ».
> - **Dicter, être écouté, être félicité** (maquette « Kiwio - Motion » du 1er octobre 2026 ;
>   `EcouteDictee.swift`, `CelebrationAjout.swift`, jetons dans `KiwiMotion.swift`) — la séquence la
>   plus utilisée, animée de bout en bout :
>   1. **la bulle surgit** (maquette « bulle kiwi » du 2 octobre 2026, d'après la bulle vocale de
>      Snapchat ; elle remplace la grande scène du 1er octobre : plus de voile, la page ne recule
>      plus) : une tranche de kiwi de 84 pt apparaît juste au-dessus du bouton « Dicter »
>      (0,62 → 1, ressort vif). Le bouton d'origine n'est jamais retiré de la page, seulement
>      masqué sous la face d'écoute : l'appui maintenu garde son geste ;
>   2. **la bulle écoute** : ses douze graines s'allongent avec le niveau RÉEL du micro (chaque
>      mesure entre par la graine de droite et fait le tour), le cœur gonfle à peine, un arc naît
>      en haut à droite, s'allonge jusqu'à 85° et tourne en 1,7 s. Le doigt posé, la bulle le suit
>      à l'horizontale et s'estompe vers l'annulation. Le bouton porte le minuteur et le geste :
>      maintenu, « ‹‹ Glisse pour annuler » et « Relâche pour envoyer » ; mains libres, « Touche
>      pour terminer » et une croix qui jette la dictée ;
>   3. **le calcul** : la bulle rétrécit et s'efface en 0,15 s, la feuille d'analyse monte ; la
>      dictée transcrite s'y relit **mot à mot, du flou au net**
>      (`MotsQuiArrivent`). ⚠️ Les mots n'arrivent PAS pendant qu'on parle : la capture enregistre
>      d'abord et transcrit ensuite (voir `SpeechCaptureService`), décision conservée ;
>   4. **les résultats** : aliments en cascade (80 ms), total qui compte, aliments reconnus en vert
>      dans la citation, et **« Ce repas t'apporte »** — protéines, glucides, lipides, fibres, la
>      valeur qui compte et une barre à hauteur de la part de l'objectif du jour (sans cible de
>      profil : la valeur seule, jamais d'objectif inventé) ;
>   5. **la célébration, dans la feuille** : 0 ms pastille verte en rebond · 160 coche + vibration de
>      succès · 220 onde · 320 douze confettis aux couleurs des apports · 340 titre « Ajouté au
>      déjeuner » · 550 étiquettes en cascade de 70 ms (« +577 kcal », « Fer +18 % », « 13 jours » :
>      l'apport et la série seulement s'ils existent) · 2 100 la feuille redescend. Ni pendant le
>      tutoriel ni en mode Zen ;
>   6. **le retour au Journal** : une pastille noire sort du haut de l'écran (`PastilleConfirmation`,
>      « Ajouté au déjeuner · 577 kcal », la toucher ouvre le repas), la carte des calories gonfle à
>      1,035 et **compte** jusqu'à sa nouvelle valeur, anneau et jauges macros suivent en ressort.
>      (La vraie Dynamic Island demanderait une activité en direct et une extension : non fait.)
>   **Une seule physique** : `kiwiVif` (0,28 / 0,86 — appuis), `kiwiFluide` (0,5 / 0,9 — feuilles,
>   bulle, recul), `kiwiRebond` (0,55 / 0,72 — célébrations uniquement), `kiwiCompteur` (chiffres,
>   sans dépassement). Échelles `KiwiEchelle` : appui 0,96 · récompense 0,5 → 1,08 → 1 · impulsion
>   1,035 · recul 0,94 ; **rien ne dépasse 1,08**. Vibrations : Dicter doux · fin d'écoute léger ·
>   ajout succès · étiquettes sélection. **Réduire les animations** : fondu de 0,2 s à la place du
>   trajet, ni aura ni confettis, coche déjà tracée, chiffres directement à leur valeur.
>   Pour l'instant, seule la dictée (et « Écrire », même feuille) se fête ainsi ; les autres ajouts
>   gardent la gratification ci-dessous.
> - **Poids et eau (1er octobre 2026)** (`JournalPoidsEau.swift`, calcul `Core/ObjectifPoids.swift`, eau
>   `Services/SuiviEau.swift`) — sous la saisie, avant « Apports à renforcer ». **Carte poids** : poids
>   actuel à gauche, **poids souhaité** à droite, chacun avec son moins et son plus (pas de 100 g, un
>   appui maintenu répète le pas). L'écart donne le SENS de l'objectif (perdre · prendre · maintenir à
>   moins d'un demi-kilo) ; les calories et les macros des cartes du dessus sortent des formules
>   existantes (`calculateMacros`), recalculées sous le doigt, enregistrées quand le geste s'arrête
>   (`DashboardViewModel.reglerPoids`). Le pied dit l'objectif du jour, le rythme et l'échéance estimée.
>   **Deux réserves : jamais de déficit vers un poids sous le repère de corpulence (IMC 18,5), ni
>   enceinte ou allaitante** — les calories restent au maintien et la carte le dit. Sans poids souhaité
>   réglé, rien ne change (les cibles suivent le premier objectif du questionnaire). **Carte eau** :
>   huit gobelets de 25 cl sur deux rangs, l'eau monte d'un coup de ressort ; toucher le dernier rempli
>   le vide ; compte gardé sur le téléphone, par compte et par jour (effacé à la déconnexion).
> - **Offre annuelle** (`OffreAnnuelleOverlay.swift`, `Services/OffrePremium.swift`) : carte qui monte
>   du bas, surcouche de la RACINE comme la gratification. Elle n'affiche que ce qui est LU chez Apple
>   (prix annuel, équivalent d'un an à la semaine, essai gratuit) ; l'économie est le même calcul que
>   le badge du paywall. **Aucun compte à rebours.** « Voir l'offre » ouvre le paywall, « Plus tard »
>   referme. Comptes gratuits ayant fait leur bilan seulement, sur le Journal, après une gratification
>   ou au retour sur l'onglet ; jamais le premier jour, une fois tous les trois jours, puis toutes les
>   deux semaines après trois refus (`RythmeOffre`). Jamais pendant le tutoriel, le brief ou les captures.
> - **Gratification après un ajout** (`GratificationOverlay.swift`, moteur `GratificationRepas`) : une
>   carte de deux secondes qui montre **ce que le geste a changé** — bandeau de verre en haut
>   (« Ajouté au déjeuner · **Modifier** » ouvre la fiche du repas), coche dessinée + deux ondes +
>   trois étincelles 3D, « Bien joué » traversé par un éclat, illustration 3D de l'apport
>   (`Fluent3D.asset(for:)` — la goutte de sang pour le fer ; flamme 3D pour la série, assiette 3D
>   dans le bandeau ; imagesets `fluent_blood` / `fluent_fire` / `fluent_plate`, Fluent Emoji MIT) qui tombe en place, reflet sur le front de la jauge, jusqu'à deux apports en **avant → après du jour** (l'ancien barré, le nouveau en
>   vert, jauge qui se remplit, « le poulet rôti, surtout » si un aliment porte le gain), série de
>   jours suivis, « Continuer ». Une seule couleur héros : le vert du gain. **Jamais à vide** : rien
>   n'a bougé d'au moins 5 points → pas de carte. Pas pendant le tutoriel, ni en mode Zen, ni sur un
>   autre jour qu'aujourd'hui. Surcouche de la RACINE (le Journal porte déjà trop de feuilles).
> - **Enchaînements (21 sept. 2026)** : les blocs de toute feuille arrivent l'un après l'autre, de
>   haut en bas (`FicheBloc(rang:)` → `kiwiEntrance`, plafonné, coupé sous Reduce Motion) ; les
>   cartes « À quoi c'est relié » arrivent de gauche à droite ; la carte de gratification REDESCEND
>   avant que « Modifier » n'ouvre la fiche du repas ; le bandeau du Plan suit la sélection en fondu.
> - **Fiche apport** (`BilanV6Components.swift` → `ApportV2DetailSheet`) — **réordonnée le 21 sept.
>   2026** (retour d'Arthur : « on ne sait pas où regarder en premier »), la même d'où qu'on vienne
>   (Journal, Bilan, Progrès). Elle répond dans l'ordre des questions, et tout ce qui s'y calcule
>   vient de `Core/LectureApport.swift` :
>   1. **le verdict** : carte anneau de cause 112 (avec ses zones grises) + nom + UNE phrase
>      accordée (« Ton fer est bas. Première cause : règles abondantes. ») + quantité (« 5,9 sur
>      18 mg par jour », dérivée de la référence canonique) ;
>   2. **Ce qui pèse le plus · touche pour comprendre** : les 3 premiers freins du registre, carré à
>      la teinte de leur part de l'anneau, barre de poids (relative au plus lourd), points, chevron →
>      `CauseApportSheet` (ce qu'elle pèse, ce qu'on regagnerait sans elle, pourquoi, où elle a été
>      déclarée ; santé et traitements renvoient vers un professionnel, jamais vers un arrêt de
>      traitement), la part reste allumée sur l'anneau ;
>   3. **Ce que tu peux faire, dès aujourd'hui** : un geste numéroté par facteur QUI SE CHANGE
>      (habitudes, assiette), un seul par famille, 3 au plus, avec « jusqu'à +N points » = le même
>      calcul rejoué sans ce facteur (aucun chiffre quand l'échelle est saturée) ; le conseil du
>      bilan (`tipBold`/`tipRest`) ferme la carte ;
>   4. **Où le trouver** : les aliments en pastilles à illustration 3D. **On les montre, on ne les
>      ajoute plus au journal d'ici : le « + » est retiré**, comme la capsule « Voir dans mon plan »
>      (aucune redirection vers un autre onglet depuis la fiche) ;
>   5. **En savoir plus**, replié : à quoi ça sert · à quoi ça répond chez toi (table
>      `SymptomesApports`) · ce que dit ton bilan · le détail du calcul (`CascadeApport`).
>   Briques partagées avec la fiche Compléments : `FicheBloc`, `FicheTexteCarte`, `CascadeApport`,
>   `AnneauDeCause`. Un apport hors des trois du bilan s'ouvre aussi (`ApportV2.pourLaFiche`).
>   **Gratuit** : le verdict et les causes en clair ; les gestes et « Où le trouver » floutés, porte
>   épinglée en bas (`UnlockDoor`, zone `fiche_apport_bilan`) qui annonce le vrai nombre de gestes.
> - **Compléments** (`SupplementsView.swift`, `AnneauDeCause.swift`, `FicheApport.swift`) — **l'anneau
>   de cause, maquette du 20 septembre 2026** : précision « Kiwio ne gagne rien sur ce qu'il te
>   recommande » · « Ton rituel du jour » (trois tuiles matin · midi · soir qui disent QUOI prendre,
>   un tap coche le moment ; visible dans les deux voies) · segmented natif Compléments · Par
>   l'assiette · **mosaïque** : 1 héros pleine largeur (anneau 112 + les 3 freins les plus lourds et
>   leur poids) puis des tuiles deux par deux (anneau 64), une tuile restante passe en ligne pleine
>   largeur, jamais de trou. **Ni dose, ni prix, ni marque sur une tuile.** Ligne « Ma sélection »
>   (budget mensuel) sous la mosaïque. Au toucher, la **fiche en six blocs** : ce que ça peut
>   expliquer chez toi (la phrase de la table déterministe `SymptomesApports`, jamais le texte libre
>   du bilan ; le score a décidé, le symptôme éclaire) · comment on l'a vu (**cascade** : point de départ 70,
>   freins, appuis, « ramené dans l'échelle » si le total sort de 0-100 ; toucher une ligne allume
>   sa part sur l'anneau) · ce que ça fait · comment le prendre (**la forme et le moment, jamais la
>   dose** : doctrine du 20 septembre) · précautions et interactions ·
>   l'autre voie. **Le chiffre est le score déterministe du registre** (`Core/NutrientLedger.swift`,
>   même arithmétique que `analyzeNutrientScores`) : part couverte dans la couleur de l'apport,
>   freins en trois gris décroissants, « autres facteurs » en piste inactive, parts qui ferment
>   toujours à 100. Le pourcentage rédigé par le bilan n'est plus affiché dans cet onglet. Voie
>   assiette : l'aliment en titre, **aucun pourcentage ni portion par aliment** (la donnée n'existe
>   pas) ; quantités et moments restent dans la fiche nutriment existante, liée depuis la fiche.
> - **Progrès v3** (`SuiviView.swift` + `ProgresV3Components.swift`, maquette du 20 sept. 2026) : le
>   **verdict d'abord** — « Cette semaine, en trois lignes » (un symptôme, un apport, les calories ;
>   phrases de `ProgresVerdict`, pur et testé) — puis **un seul graphe** à la fois (segmented
>   Symptômes · Apports · Calories). Courbe d'un symptôme : une ligne, trois paliers nommés en mots,
>   **le haut est toujours le mieux**, point du jour plein, pilule « +2 niveaux ». Puis « Depuis ton
>   premier jour » (avant → après + écart), puis « Voir mon récap du jour ». Check-in : feuille, **un
>   symptôme par écran**, question dans le sens du mieux, toucher = choisir ET avancer (350 ms),
>   proposé à l'arrivée sur l'onglet (jamais au lancement). Frontière Premium inchangée : tendance
>   des symptômes et des apports derrière leurs portes ; en gratuit le verdict nomme le sujet seul.
> - **Plan en graphe** (`PlanGraphComponents.swift`, modèle `Core/PlanGraph.swift`, maquette du 20 sept.
>   2026) : **trois anneaux, trois couleurs qui portent le sens** — vert = l'objectif (centre), bleu =
>   les symptômes suivis (anneau 1, quatre au plus), gris = les leviers (anneau 2 : apports que le
>   bilan rattache à ce qui est affiché, et **habitudes tirées du registre des apports**, mêmes
>   libellés et mêmes points que la fiche de l'apport). Trait épais = lien fort. Positions
>   **calculées, pas simulées** (leviers tirés vers ceux qu'ils touchent, puis écartés en une passe).
>   Les nœuds dérivent de 2 à 3 pt, une pulsation parcourt les liens du nœud choisi ; le reste
>   s'estompe à 35 %. **Entrée en scène à chaque arrivée sur l'onglet** : les nœuds surgissent du
>   centre vers l'extérieur (spring, 45 ms d'écart), les liens se révèlent ensuite. **L'horloge est en
>   pause hors de l'onglet** (`\.estOngletActif`, posé par la racine sur chaque onglet — à préférer à
>   `onAppear`, qui ne se joue qu'au lancement) et sous Reduce Motion. Ni zoom ni
>   déplacement. Bandeau du nœud choisi (état, jamais un geste) → **la feuille du nœud**
>   (`PlanNoeudSheet`, 21 sept.) : pastille + sur-titre coloré + nom · la cause · **« À quoi c'est
>   relié »** (rangée de cartes : état du voisin — « 42 % », « −22 points » — et force du lien, lisible
>   en gratuit) · **« Quoi changer dans ton assiette »** (pastilles à illustration 3D, `DSFlow` ; en
>   toucher une la déplie : combien, quand, comment, l'astuce) · **« Tes habitudes »** · **« En
>   complément »** (nom + étiquette, **jamais de dose** : `PlanTopicText.sansDose`, lien vers l'onglet
>   Compléments) · délai · « C'est noté ». Gratuit : cause et liens en clair, les trois blocs de
>   solutions voilés, porte `plan_solutions`. Une habitude ouvre sa feuille à elle (la cause et ce
>   qu'elle freine). Le sélecteur « Objectifs et symptômes / Apports »
>   et la ligne « focus de la semaine » ont disparu : le graphe montre les deux lectures à la fois.
> - **Réglages v3** (`ReglagesView.swift` + `ReglagesSousPages.swift`, maquette du 20 sept. 2026) :
>   bloc Premium (carte sobre sur voile, une promesse, 3 lignes en symboles gris, prix lus chez Apple
>   avec trait gris tant qu'ils chargent ; abonné = « Premium actif » + « Gérer », aucun argumentaire)
>   · **Compte** (identité, objectifs, abonnement, Apple Santé, export) · carte questionnaire ·
>   **Application** (Notifications en interrupteur, tutoriel, bilan animé, méthode) · liens
>   Restaurer · Conditions · Confidentialité · déconnexion + suppression. Deux en-têtes, deux styles
>   de carte, pastilles à **trois sens** (gris / vert = connecté ou actif / rouge = destructif).
>   L'interrupteur Notifications porte `RappelsPersonnalises.actifs` et lève l'ancien mode Zen,
>   qui n'a plus d'interrupteur à l'écran. Sous-pages : compte (mot de passe si compte e-mail),
>   objectifs, abonnement, suppression du compte (double verrou). Depuis le 1er oct. 2026, la carte
>   Application porte aussi « Widgets et écran verrouillé » (sous Notifications).
>
> - **Widgets, écran verrouillé, activité en direct** (1er oct. 2026, maquette montrée dans le chat,
>   `Partage/VuesWidgets.swift` + `KiwioWidgets/`) : quatre widgets et une carte d'écran verrouillé
>   qui reprennent le Journal, jamais un design à part. **Ma journée** (petit : le chiffre des kcal
>   restantes + jauge ; moyen : le chiffre, la série, les quatre repas Matin · Midi · Soir · Encas avec
>   leurs symboles et teintes de la mosaïque, un « + » vert sur chacun ; rectangulaire d'écran
>   verrouillé). **Ajout rapide** (petit et rond : le micro ; moyen : quatre tuiles, Dicter en vert,
>   Photo, l'eau, le rituel). **Eau** (les litres comme sur la carte Eau, « + 25 cl »). **Rituel du
>   jour** (matin · midi · soir à cocher, **jamais de dose**). **Activité en direct « Ta journée »** :
>   les quatre repas, puis Dicter · eau · rituel. Règle de geste : l'eau et le rituel se cochent sur
>   place ; Dicter, Photo et un repas ouvrent l'app au bon endroit (un widget ne peut pas enregistrer
>   la voix). Le vert reste réservé à ce qui se touche. Un widget suit le mode clair ou sombre du
>   téléphone (l'app, elle, reste claire). Réglages → Widgets et écran verrouillé : l'interrupteur
>   « Ma journée en direct », les aperçus (les vraies vues), le mode d'emploi en trois lignes.
>
> - **Prise de sang** (Premium, 30 sept. 2026 — maquette validée le 6 juil., `Views/PriseDeSang/PriseDeSangSheet.swift`) :
>   quatrième option de « Autres façons d'ajouter » du Journal (« Prise de sang », goutte) et carte
>   « Ta prise de sang » du Bilan complet (entre points d'attention et symptômes). Feuille : gratuit →
>   zone de dépôt voilée + porte `prise_de_sang` ; Premium → « Photographier la page » (capsule verte),
>   « Choisir une photo » · « Importer un PDF », deux lignes d'info (document lu puis oublié ; liste des
>   valeurs lues) ; lecture « Kiwio lit tes résultats… » ; **« Tes repères »** : date du prélèvement,
>   compteurs « à optimiser » / « dans les repères », UNE précision médicale, une carte par valeur
>   (valeur + « repère 30–100 » imprimé par le labo, pastille, « Côté assiette » ou « Continue comme ça »),
>   puis « Ton bilan en tient compte » (score avant barré → après, par apport), « Importer une autre
>   prise de sang », « Supprimer ». Le calcul : `Core/PriseDeSangApports.swift`, une ligne nommée du
>   registre (« Ta prise de sang du 12 sept. », « mesuré dans ta prise de sang ») appliquée APRÈS le
>   journal ; la fiche apport dit « … va dans ce sens » (une mesure n'est jamais une « cause »).
>
> **Quantités en unités** (demande d'Arthur, 23 août) : partout où une quantité est demandée
> (dictée `VoiceMealSheet`, recherche / code-barres / édition `PortionSheet`), un aliment qui se
> compte se saisit en unités, jamais en grammes d'abord : chips de taille quand ça a un sens
> (œuf Petit 42 g · Moyen 50 g · Gros 60 g ; banane Petite · Moyenne · Grosse ; assiette Petite ·
> Moyenne · Grande), compteur « − 2 œufs + » avec grammes et kcal dessous, question « Combien
> d'œufs ? », lien « Saisir en grammes » ↔ « Compter en œufs ». Le « + » rapide de la recherche
> ajoute 1 unité. Source : `Core/UnitPortionCatalog.swift` (≈130 motifs ordonnés par priorité,
> poids alignés sur `PORTION_PIECE_DEFAUT` du serveur vocal ; repli sur la portion « 1 … » de
> `get_food`). La valeur enregistrée reste le grammage.
>
> **Tutoriel premier lancement** (maquette « Kiwio - Tutoriel », 23 août au soir ; **depuis le
> 20 septembre l'étape du « + » a disparu avec lui : la découpe vise le bouton « Dicter » du Journal,
> cinq étapes au lieu de six**) : à l'origine six étapes qui
> FONT FAIRE sur les vraies commandes — bienvenue (carte), « + » (découpe circulaire), « Dicter mon
> repas » (dans la feuille d'ajout), « on ne te demande que ce qui manque » (dictée), carte des
> apports, barre d'onglets (« Reviens demain » + « J'ai compris »). Voile encre 64 % découpé par
> `destinationOut`, bulle blanche r14 (5 points de progression, « Passer » 15/500), un seul geste
> par étape, étape persistée (reprise après kill), relançable via Réglages → « Revoir le tutoriel ».
> Source : `Views/Shared/TutorielPremierLancement.swift`. Remplace l'ancien tour d'onglets et les
> 3 bulles du Journal.
>
> **Retours du 23 août au soir (appliqués)** : le « + » de « Ce qui le remonte » (fiche apport)
> ajoute vraiment l'aliment (recherche → fiche portion → journal) ; Progrès sans « prochains
> paliers » (fruits à débloquer) ; courbes symptômes réelles dès le premier jour (le suivi démarre
> tout seul, plus de mode « exemple ») ; pavés du Plan nettoyés par KiwiProse (gras markdown,
> apartés savants ≥ 25 car. sans chiffre, causes recollées en phrases).
>
> **Non appliqué (décisions produit à trancher, pas du design)** : le verrouillage par nœud du Plan
> (2 nets / 3 floutés) ; « Mes aliments » et « Activité » comme saisie (remplacés par le journal complet
> et l'énergie active Apple Santé). Le gating premium existant est inchangé partout.

## ⭐ Refonte « v4 — 3D » (direction validée 28 juin 2026 — remplacée le 23 août 2026, conservée pour l'historique)

> DA validée par Arthur (maquettes *« … v4 - 3D »*, dossier *Corrections design et interface app*) :
> **fond crème** (`#FBF6EF`), **anneaux pleins**, **petites illustrations 3D** (Microsoft Fluent
> Emoji, licence MIT — cf. `Views/Shared/Fluent3D.swift`, assets `fluent_*`), **pop-ups
> bottom-sheet**, **accent vert kiwi** (`#5DA838`).
>
> ⚠️ Cette DA **supersède**, sur les écrans refondus, l'ancienne règle « zéro emoji / SF Symbols
> uniquement » de `kiwio-design-system.md` : les icônes de **navigation / section** restent en
> SF Symbols, mais les illustrations **aliments / récolte / score** passent en **3D**.
>
> Déploiement **onglet par onglet** — Arthur valide chacun sur TestFlight avant le suivant.
>
> **Onglet 1 — Bilan (livré, build à valider).** Ordre de l'écran :
> ① score (anneau plein, chiffres mono, étincelle 3D, adjectif `HealthScale`) ·
> ② *Tes apports à renforcer* (champs de points cliquables → **pop-up** : anneau « % du besoin »,
> *Pourquoi à renforcer*, *Où le trouver* en 3D, CTA *Voir mon plan détaillé*) ·
> ③ *Symptôme détecté* (CTA compact → causes en feuille) ·
> ④ *Ta récolte* (coverflow 3D **adossé à la série** `GamificationService.currentStreak` —
> aucune nouvelle mécanique de jeu introduite) ·
> ⑤ *Tes derniers repas* (journal du jour `meal_scans`, état vide → Scanner).
> Les **red flags urgents** restent TOUJOURS au-dessus du héros (sécurité, loi inchangée).
> Code : `DashboardView.swift` · `BilanV4Components.swift` · `Fluent3D.swift`.
> Retirés de la home (hors maquette v4, à réintégrer ailleurs si besoin) : carte « Ton plan est
> prêt », conseil du jour, *Mon évolution* (avatar), export premium.

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

### 4bis — Refonte « 3 carrousels de courbes » (13 juil. 2026, maquette validée)

L'onglet Suivi passe d'une pile verticale à **3 carrousels de courbes défilables
à flèches ‹ ›** (ordre haut→bas validé : **Macros → Micros → Symptômes**). Corps :
titre · `SuiviStatsRow` · carrousel Macros · carrousel Micros · carrousel Symptômes ·
`SuiviNeedsCard` (conseils) · `SuiviPaliersCard`. Les anciennes **barres de couverture**
(`SuiviCoverageCard`) ne sont plus affichées (remplacées par le carrousel Micros).

- **Carrousel Macros** — pages Calories / Protéines / Glucides / Lipides / Fibres :
  **vraies valeurs mesurées par jour** (somme des scans du jour, 14 j) ; jours sans
  scan = trou (jamais un 0 inventé) ; insight « il y a N j : X · aujourd'hui : Y ».
- **Carrousel Micros** — pages = apports à renforcer (< 60), sinon micros présents :
  couverture **% AJR par jour** `min(100, Σ pctRDA)`, repère 100 % ; même insight.
  Pour Free, l’en-tête et le nom de l’apport restent lisibles mais la courbe et
  son insight sont floutés ; Premium débloque la trajectoire détaillée.
- **Carrousel Symptômes** — 1 page par symptôme déclaré : courbe cumulée **+/- PAR
  symptôme** (chaque courbe indépendante — fin du « tout bon ou tout mauvais »),
  `step 3` (lissée), pastille de verdict. Bandeau « Commencer mon suivi » tant que
  le suivi n'est pas démarré (courbes = exemples badgés).
- **Check-in PAR symptôme** : le pop-up quotidien pose **une question 1-tap par
  symptôme** (mieux / pareil / moins bien) + énergie ; stockage `feel_<id>` (repli
  ancienne clé `symptome_today` pour le symptôme principal). Chaque ressenti nourrit
  UNIQUEMENT la courbe de SON symptôme.

Code : `SuiviView.swift` · `SuiviCarouselComponents.swift` (`SuiviCarouselBlock`,
`SuiviValueChart`, `SuiviCurveInsight`) · `SuiviEngineV4.swift` (`macroDailySeries`,
`microDailySeries`, `seriesSummary`, `symptomEvolutions(feelingsById:)`,
`SuiviCheckinHistory.feelingsById`). Fenêtre 14 j = `MealJournalViewModel.fortnight`
(aucun chargement réseau en plus).

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
    spinner nu) / vide (le signe Kiwio + phrase utile) / erreur (message actionnable +
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

## 7. JOURNAL DU JOUR (sheet de l'onglet Scan — refonte « façon Foodvisor », 10 juil. 2026)

> **Retirée le 21 septembre 2026.** La feuille « Ma journée » (`DailyMealJournalView`) répétait
> la page Journal ; elle est remplacée par la fiche d'un repas (`FicheRepasSheet`, moteur
> `FicheRepas`). L'édition et la suppression par aliment, et l'ajout par la recherche, vivent
> désormais dans cette fiche. Ce qui suit est conservé pour l'historique.

Maquette validée par Arthur (session du 10 juil.). Livraison en 3 phases : P1
lignes par aliment + suppression + total honnête · P2 quantité libre + ajout via
recherche · P3 favoris/récents/suggestions. Code : `DailyMealJournalView.swift`.

Ordre de l'écran :
① **En-tête** (carte kiwiCard) : « Aujourd'hui · date » · gros chiffre = **kcal
restantes** (vert ; rouge + « au-dessus » si dépassé) vs objectif RÉEL du profil ·
barre de progression · 3 mini-barres macros (P/G/L) vs cibles réelles.
**Jamais de cible inventée** : sans objectif calculable → consommé seul, pas de barre.
② **4 sections repas** (Matin/Midi/Soir/Encas) : emoji + libellé + kcal du créneau
+ bouton « + » (ajout). État vide → « Rien pour l'instant ».
③ **Lignes aliment** (une carte par ALIMENT quand le repas porte le détail
par aliment — scans photo Edge ≥ v5 ; une carte par repas entier sinon) :
vignette teintée (symbole du 1er micro apporté, sinon fourchette) · nom ·
grammes si connus (jamais inventés) · kcal à droite.
④ **Fiche portion** (tap → `PortionSheet`, composant UNIQUE journal + accueil
Scan) : presets Petite/Moyenne/Grande (80/150/250 g) · stepper ±10 · **champ
grammes libre** (clavier) · aperçu live kcal + P/G/L (re-scaling linéaire,
identique à la persistance) · CTA « Enregistrer » + « Retirer cet aliment »
(ligne éditable) / note + suppression seule (entrée sans détail). Suppression
aussi en contextMenu sur la ligne.
⑤ **Recherche** (« + » d'un créneau → `FoodSearchSheet`) : barre de recherche
→ RPC **`search_foods_visuel`** (21 sept. 2026 : enveloppe additive de `search_foods`,
même classement ; les 12 meilleurs génériques CIQUAL + les 12 meilleurs produits
Open Food Facts en UN aller-retour, avec photo, Nutri-Score et famille CIQUAL ;
repli automatique sur `search_foods` si elle ne répond pas) · **un repère visuel par
ligne** (`FoodHitContenu`, partagé avec l'onglet Recherche du scan) : **photo de
l'emballage** sur fond blanc pour un produit de marque, **illustration de la
famille** pour un générique (3D `fluent_*` quand elle existe, emoji sinon — la
table vit dans `Core/RechercheVisuelle.swift`, le nom affine : une volaille n'est
pas un steak) · nom sur DEUX lignes (les génériques ne diffèrent souvent que par
la fin) · « Marque · kcal / 100 g » ou « Famille · kcal / 100 g » · pastille
Nutri-Score · deux sections « Aliments » / « Produits de marque », celle qui
porte le meilleur résultat passe devant (« nutella » montre le pot d'abord) ·
crédit « Open Food Facts » sous la liste · **⊕ ajout rapide 100 g** avec
bandeau de confirmation, ou tap → fiche portion « Ajouter au [repas] »
(`get_food`, valeurs 100 g server-side re-scalées ×g/100 — jamais de recalcul
RDA client). Produit OFF sans kcal → fiche non ajoutable (note explicite).
L'ancien AddMealSheet (nom + kcal à la main) est SUPPRIMÉ.

Lois spécifiques : la suppression d'un ITEM réécrit `detected_foods` + agrégats
`macros`/`micros` recomposés (miroir Edge — le Bilan hebdo et `day_summary`
lisent ces colonnes) ; les clés annexes de l'Edge (`ciqual_code`, `confidence`,
`nova_class`, `micros[].amount`…) sont préservées telles quelles (passthrough).

## 8. QUESTIONNAIRE (feuille « bilan » — refonte du 1er octobre 2026)

> **Source** : maquette cliquable validée par Arthur en trois tours le 1er octobre 2026
> (« c'est bien dans l'idée » → repas et mêmes données → « pas beaucoup, modérément, beaucoup »).
> **Pourquoi** : l'ancien flux (une question par écran, barre qui repartait de zéro à chaque
> section, animation imposée entre deux sections) était « très long, pas aéré » ; on ne savait ni
> où on en était ni à quoi servait la question. 36 inscrits sur 44 le commençaient, 26 le
> finissaient ; la perte était au caddie.
> **La règle qui borne tout** : *les données envoyées à l'API sont les mêmes*. Mêmes clés, mêmes
> valeurs (`QuestionnaireSection`), même `profile.groceries[id] = portions par semaine`. La
> refonte ne change que l'ordre, le regroupement et les mots. `ParcoursBilanTests` et
> `LibellesBilanTests` le vérifient.

Code : `Views/Questionnaire/Bilan*.swift` (vue), `Core/ParcoursBilan.swift` (ordre, écrans
visibles, ce qu'il faut avoir répondu), `Core/PistesBilan.swift` (ce que les réponses apprennent),
`Core/RepasCatalog.swift` (aliments par repas), `Core/NiveauConsommation.swift` (les trois mots),
`Core/LibellesBilan.swift` (les mots des réponses). L'état reste dans `QuestionnaireViewModel`.

**Quatre étapes, une couleur chacune** (`EtapeBilan.teinte`) : ① Toi (bleu `#007AFF`) · ② Ton
quotidien (orange `#FF9500`) · ③ Ta forme (violet `#AF52DE`) · ④ Ton assiette (vert kiwi). La
couleur habille l'écran (halos du fond, réponse choisie, segment de la barre) ; **le bouton du bas
reste vert d'un bout à l'autre**. Écart assumé à la règle « le vert ne colore que ce qui se tape » :
ici la couleur porte un sens, l'étape, comme la couleur d'une jauge porte un statut.

Ordre des écrans (`EcranBilan`, l'ordre des cas est l'ordre du parcours) :
accueil → **Toi** : motif (objectifs + symptômes, en puces) · prénom (sauté si le compte le
connaît) · repères (sexe + trois molettes âge, taille, poids) · récap → **Ton quotidien** :
soleil (intérieur, exposition, nuancier de peau) · bouger (activité, poids + « c'était voulu ? ») ·
boire (café, moment du café à partir de trois, eau) · alcool et tabac · récap → **Ta forme** :
ressenti (curseurs stress, réveil) · nuits (curseurs écrans, sommeil) · ventre · cycle (femmes) ·
récap → **Ton assiette** : régime · « ce qu'on voit déjà » · petit déj · midi · goûter · soir ·
« jamais » (le champ `allergies`) → fin. Sur demande (« Affiner d'abord ») : à table · pain, sel
et compagnie · habitudes · compléments · traitements · digestion · antécédents.

Lois de l'écran :
1. **En-tête** : chevron retour · quatre segments qui ne repartent JAMAIS de zéro · croix (confirme
   avant de quitter ; la feuille ne se ferme pas en glissant). Dessous : nom de l'étape dans son
   encre · « encore ~2 min » · pastille « 🔍 N pistes ».
2. **Chaque écran dit pourquoi il demande** : une phrase sous le titre, vraie au regard du moteur
   (« le café pendant le repas freine l'absorption du fer »).
3. **La carte de piste**, sous les réponses : « Piste repérée » / « C'est noté » / « Bon point ».
   Elle vient d'un FAIT du registre (`HealthCalculator.registreApports`), lu par différence, jamais
   d'un symptôme (doctrine `SymptomesApports`) et jamais du sexe ou de l'âge seuls. Rien à dire :
   pas de carte. Vocabulaire : « piste », « à surveiller », « ton assiette dira si elle compense ».
4. **Aucune réponse validée en silence** : un curseur exige un geste, une molette se touche, un
   champ qui porte une valeur par défaut (sexe, régime, cycle) ne s'affiche choisi qu'une fois
   choisi. Une bascule éteinte vaut « non », écrit au moment de continuer.
5. **Les aliments** : douze vedettes par repas (adaptées au régime déclaré), puis « Voir tous les
   aliments » (le catalogue entier, rayons du repas en tête, recherche). Sous un aliment coché :
   **« Pas beaucoup · Modérément · Beaucoup »** = 1 · 3 · 10 portions par semaine ; un aliment
   coché part sur « Modérément ». Dix jauges, une par apport, se remplissent en direct.
6. **Fin** : la phrase et les trois lignes viennent des VRAIS scores ; « Réponses données N sur M »
   est un décompte, pas une note de précision. « Voir mon bilan » envoie ; « Affiner d'abord »
   ouvre les écrans d'approfondissement.
7. **Reprise** : là où on s'est arrêté, sans jamais sauter un écran pas terminé (remplace la
   décision du 6 juillet 2026, « reprise au début »). Le Journal affiche alors « Ton bilan
   t'attend · Étape 2 sur 4 » avec la barre et « Reprendre ».
8. **Identité** : le signe (`KiwiSigne`) sur l'accueil et sur la fin ; aucun emoji kiwi.
9. **Mouvement** : jetons de `KiwiMotion` uniquement, rien au-delà de 1,08, tout coupé par
   « Réduire les animations ». La gerbe de fin d'étape se joue une fois.

L'ancien flux (`QuestionnaireContainerView`, `GroceryShoppingView`, `SectionIntroView`,
`TeaserEngine`, `QuantityBracket`) reste dans le dépôt, plus présenté, tant que le nouveau n'est
pas validé sur appareil ; il part ensuite dans une PR à part.

---

*Maquettes de référence : session du 11 juin 2026 (« rendu_final_4_ecrans_reference »
+ correctifs « Pourquoi ? » et règles déterministes). Contrat IA : prompt v35
(generate-analysis v40), harnais de conformité sur audit-a/b/c obligatoire avant
tout déploiement de prompt.*
