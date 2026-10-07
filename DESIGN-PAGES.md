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
> | Écran de chargement | `LaunchScreenView` : signe 72 pt au centre EXACT de l'écran + « Kiwio » 22 pt dessous, sur le fond de verre teinte kiwi (`VerreFond(teinte: .kiwi)`) | au lancement |
> | Lancement statique | `Info.plist` `UILaunchScreen` : fond `LaunchScreenBackground` (#EDF2E9, la base pâle du fond de verre kiwi / noir) + image `LaunchSigne` (72 pt) | avant le premier écran SwiftUI : même place, même teinte, le passage ne bouge pas |
> | Attente | `KiwiLoader` : **les pépins qui chargent**, une traînée qui fait **un tour en 1,8 s** (partie de la couronne pleine en 0,35 s) ; Reduce Motion = signe figé | lancement, analyse, questionnaire, Plan, Compléments, scan photo, dictée, historique, Apple |
> | En-tête | `KiwiEnTete` (signe 72 + nom 22) | connexion ; l'onboarding en grand (signe 120 + nom 34) |
> | Barre de l'app | `KiwiLockupBarre` (signe 26 + nom 19) | haut de la page de garde, carte du récap partageable |
> | Confirmation | `KiwiConfirmation` (signe 44 dans un rond 72 couleur cœur) | « Bienvenue dans Kiwio Premium » |
> | Signe seul | `KiwiSigne(taille:)` | Brief du jour, ouverture du récap, états vides (Plan, historique), centre de l'anneau de la page de garde |
> | Pied de page | `KiwiPiedDePage` (signe mono 20 + nom 16 + version) | bas des Réglages, suivi de « Ne remplace pas un avis médical » |
> | Mascotte (2 oct. 2026) | `KiwiMascotte(animee:)` + `KiwiMascotteHalo` (`Views/Shared/KiwiMascotte.swift`) | DEUX endroits seulement : la ligne Premium des Réglages (44 pt, immobile) et la feuille Premium (84 pt, animée, sur son halo tournant). Partout ailleurs, le signe reste. |
>
> Le nom : « Kiwio » en SF Pro Rounded gras, serré (-0,045 × la taille) : `KiwiWordmark`. Plus de
> « kiwi » + « o » vert. Règle de la maquette : sous 32 pt, le signe seul.

## ⭐⭐⭐ Verre liquide (direction du 2 octobre 2026)

> **Source** : maquette Claude Design « Kiwio - Motion v3 - Verre liquide » (projet « Kiwio mobile
> app design », fichier `Kiwio - Motion v3 - Verre liquide.dc.html`), PR #296. Elle ne change NI
> les données, NI les calculs, NI ce qui part au serveur : elle change la matière et le mouvement
> de tous les écrans. Les tokens et les briques sont dans `docs/DESIGN-SYSTEM.md` (section « Verre
> liquide ») ; le code du socle dans `Views/Shared/KiwiVerre.swift`, `KiwiMotion.swift`,
> `KiwiMascotte.swift`.
>
> Ce qu'elle remplace dans la refonte du 23 août décrite plus bas, sur TOUS les écrans :
> - **le fond** : plus d'aplat neutre. Quatre halos flous qui dérivent sur une base pâle
>   (`DSPageBackground()` = `VerreFond`), dont la teinte suit l'onglet : kiwi (Journal) · aube
>   (Progrès) · ciel (Plan) · orchidée (Compléments) · neutre (Réglages). Page poussée :
>   `VerrePageFond()`. Feuille : `.verreFeuille()`, coins de 38 ;
> - **les cartes** : plus de carte blanche rayon 14. `.dsCard()` est la carte de verre (blanc 80 →
>   58 %, liseré blanc, rayon 24, ombre douce). Boutons secondaires en verre clair, action
>   principale en verre vert ;
> - **la couleur** : une teinte par catégorie et sa version foncée pour le texte ; un libellé de
>   catégorie s'écrit en 15/600 dans la teinte foncée, précédé de son icône dans la teinte. Le vert
>   kiwi reste réservé à ce qui se touche ;
> - **les chiffres** : les grands chiffres passent en SF Pro Rounded gras, et ils COMPTENT quand ils
>   changent (`ChiffreQuiCompte`, `.contentTransition(.numericText())`) ;
> - **le mouvement** : quatre mouvements partout (glisse, ressort, rebond, compteur), les blocs
>   arrivent en cascade, anneaux et courbes se retracent à chaque arrivée sur l'onglet ; plafond
>   d'échelle 1,22 (`KiwiEchelle.plafond`) au lieu de 1,08 ;
> - **la racine** (`ContentView.mainInterface`) : la page de l'onglet arrive de côté en sortant d'un
>   flou de 8 pt (`kiwiGlisse`), un bord haut flouté (`VerreBordHaut`) couvre la barre d'état, la
>   pastille de la barre d'onglets glisse.
>
> Ce qui tient toujours : le vert réservé à l'interactif, un chiffre héros par écran, le
> vocabulaire, aucune dose, toutes les règles métier et de Premium.
> **Rien de ce qui existait n'a disparu** : un état que la maquette ne montre pas (vide, avant
> questionnaire, hors ligne, verrouillé, mentions) est gardé, habillé en verre. Les données de la
> maquette sont des exemples : l'app affiche les vraies, et ce qui n'a pas de donnée derrière n'est
> pas inventé.
>
> Les descriptions d'écran ci-dessous sont à jour de cette direction.

## ⭐⭐ Refonte « qualité Apple » (direction du 23 août 2026 — socle iOS natif)

> **Sources de vérité** : `Kiwio iOS - refonte.dc.html` (maquette, **10 écrans** dans sa
> version du 23 août 11:52, `C:\Users\stana\AppData\Local\Temp\` ; la v1 à 7 écrans est dans
> `Downloads`) et `instructions-claude-code-refonte-ios.md` (document d'implémentation,
> `Downloads`). Cette direction **remplace** la DA crème/vert ci-dessous : le vert ne colore que ce
> qui se tape, un seul chiffre héros par écran, gras plafonné à 700, chiffres tabulaires. Son fond
> neutre (`systemGroupedBackground`) et ses cartes blanches rayon 14 sans ombre ont été **remplacés
> le 2 octobre 2026 par le verre** (section ci-dessus) ; la navigation, la structure des écrans et
> les règles de contenu restent les siennes. Tokens : `HealthMap/Views/Shared/KiwiDS.swift`
> (préfixe `ds`), désormais posés sur le verre.
>
> **Navigation (5 onglets, capsule flottante)** : **Journal · Progrès · Plan · Compléments · Réglages**.
> Le Bilan a fusionné dans le Journal (son écran complet reste accessible par « Tout afficher »,
> en feuille, sans paywall) ; le Scan vit sur la page du Journal, dans sa rangée de saisie (le
> bouton `+` flottant du 23 août et sa feuille d'ajout ont disparu le 20 septembre) ; les
> Réglages sont le **seul** endroit qui parle d'argent (carte Premium, prix et essai lus depuis StoreKit).
> La barre d'onglets est une capsule de verre de 62 pt dont la pastille glisse d'un onglet à l'autre.
>
> **Écrans** :
> - **Journal** (`MealScanView.swift` → `JournalView`, `JournalComponents.swift`) — structure de la
>   maquette « Journal & Progrès v2 » du 20 septembre 2026, recomposée par le verre le 2 octobre.
>   De haut en bas :
>   1. **le titre et le jour** : la barre de navigation est masquée ; « Journal » (34/700) est
>      dessiné dans la page et, à sa droite, **la capsule du jour** en verre clair de 44 pt : deux
>      chevrons verts et le libellé du jour, qui roule vers le haut quand le jour change et ouvre
>      le calendrier sans borne (décision du 11 septembre, conservée : le chevron de droite
>      s'estompe aujourd'hui, mais il répond toujours). Le jour commande toute la page ET la date
>      des ajouts ;
>   2. **les puces** (`VerrePuce`, une rangée qui défile à l'horizontale) : Eau (anneau de 30 pt et
>      goutte, les litres bus) · Poids · Série · Analyses (« Nouveau », puis la date de la dernière
>      prise de sang). Eau, Poids et Analyses font défiler la page jusqu'à leur carte ; la Série se
>      lit, elle ne mène nulle part, et n'apparaît que si elle existe, hors mode Zen ;
>   3. **la carte Énergie, unique** (`JournalEnergieCard` : elle réunit l'ancienne carte calories
>      et les macros) : le libellé de catégorie « Énergie », les kcal restantes en 34 arrondi (le
>      chiffre héros, il compte), une sous-ligne (« Objectif 2 100 kcal », ou « Déjeuner ajouté ·
>      3 aliments » pendant 8 s après un ajout), l'anneau de 72 pt de la part consommée (vert, puis
>      rouge de statut une fois le budget dépassé). Sous un filet, **les quatre macros en colonnes**
>      (protéines · glucides · lipides · fibres) : la valeur sur l'objectif, une barre de 4 pt dans
>      la teinte de la macro, et **le surplus en hachures, lu selon l'objectif de la personne**
>      (vert seulement pour les protéines de qui veut prendre du muscle et pour les fibres, orangé
>      sinon ; fibres : référence canonique 30 g). À droite du libellé, une pastille au cœur
>      (« +320 kcal », « Santé » ou « Relier ») ouvre l'activité **Apple Santé** du jour. Sans
>      objectif calculable : le consommé seul, sans anneau, jamais une cible inventée ;
>   4. **la saisie, sur UNE rangée de 60 pt** (`JournalSaisieBloc`) : « Dicter » en verre vert bombé
>      (la seule surface verte, avec son halo qui respire et « le plus rapide »), puis « Photo » et
>      « Autres » en verre clair. « Autres » pivote son « + » en croix, passe au vert pâle et déplie
>      trois tuiles : Écrire · Rechercher · Code-barres (« Écrire » **ouvre la feuille d'analyse sur
>      un champ de texte, clavier levé** — depuis le 21 sept. : l'app ignorant la zone du clavier à
>      sa racine, un champ posé sur la page finissait caché derrière lui, sans sortie ; même analyse
>      et même quota que la dictée). « Dicter » : **un toucher = mains libres ; un appui maintenu =
>      la dictée vit tant que le doigt tient, relâcher analyse, glisser à gauche jette, glisser vers
>      le haut verrouille** (`AppuiDicter`, seuils `DicteeGeste`) ; la suite est décrite dans
>      « Dicter, être écouté » ;
>   5. **les micronutriments**, puis **le poids et l'eau** (décrits plus bas) ;
>   6. **la carte de la prise de sang** (voir « Prise de sang ») ;
>   7. **« Apports à renforcer »** (lien « Tout afficher » → le Bilan complet, en feuille) : la
>      phrase de l'interaction, **trois anneaux** à la couleur de l'apport qui se tracent en 1 s à
>      0,1 s d'écart, une sortie verte vers le Plan ;
>   8. **le jour en grille de quatre repas**, deux par deux (Petit-déjeuner · Déjeuner · Dîner ·
>      Collation) : une carte de verre par repas, teintée dans son coin à la couleur du moment
>      quand elle contient quelque chose (ambre, kiwi, indigo, framboise), « Rien pour l'instant »
>      sinon ; les cartes arrivent en cascade et le total du jour compte à l'ajout. Le toucher
>      ouvre **la fiche de CE repas** (`FicheRepasSheet` : ce que tu as saisi, modifiable · « Ce
>      qu'il t'a apporté », macro par macro avec sa part de la cible du jour · vitamines et
>      minéraux · un constat, jamais un geste).
>   L'entrée de la page (cascade des repas, tracé des anneaux) se rejoue à chaque arrivée sur
>   l'onglet et à chaque changement de jour. **Avant le questionnaire** : la saisie d'abord, puis
>   « On ne connaît pas encore tes besoins » (porte), « En attendant, en France »
>   (`TeaserStatsCatalog`, jamais un chiffre inventé), « À la fin du questionnaire » ; ni carte
>   Énergie, ni micronutriments, ni poids, ni eau, ni prise de sang (les repas déjà notés restent
>   listés dessous).
> - **Dicter, être écouté** (maquette « Verre liquide » du 2 octobre 2026, « la bulle de dictée
>   retravaillée » ; `EcouteDictee.swift`, `VoiceMealSheet.swift`, `CelebrationAjout.swift`) — la
>   séquence la plus utilisée. Elle REMPLACE la bulle kiwi façon Snapchat de la PR #295 (tranche
>   de 84 pt, graines, arc) et la célébration dans la feuille du 1er octobre. Les mécanismes
>   (capture, transcription après coup, phases, annulation, gestes) sont inchangés :
>   1. **le bouton devient la bulle** : elle part du cadre du bouton « Dicter », grandit en un
>      disque de 150 pt posé au centre de l'écran (ressort `kiwiFluide`) pendant qu'un **voile**
>      flou tombe sur la page (`VerreVoile`). La scène vit à la RACINE, par-dessus la barre
>      d'onglets (`EcouteSurcouche`). Le bouton d'origine n'est jamais retiré de la page, seulement
>      masqué : l'appui maintenu garde son geste ;
>   2. **la bulle écoute** : trois couches liquides (des formes fermées à sept points, lissées, qui
>      tournent et ondulent) dont l'amplitude suit le niveau RÉEL du micro ; l'ensemble gonfle avec
>      la voix, une aura verte respire derrière, une onde part à chaque pic. Au-dessus, **la carte
>      de transcription** en verre flottant : point rouge, « Je t'écoute… », minuteur. Dessous : la
>      consigne « Dis ce que tu as mangé, avec les quantités », puis **« Annuler » et
>      « Terminer »** (toucher la bulle termine aussi). Quand le doigt tient encore le bouton, ces
>      deux boutons deviennent « Glisse pour annuler » et « Relâche pour terminer », et la bulle
>      suit le doigt à l'horizontale en s'estompant vers l'annulation ;
>   3. **le calcul, sous la bulle** : elle se contracte à 66 pt, trois points tournent autour
>      d'elle (un tour en 1,2 s), les couches accélèrent, « Kiwio calcule tes apports… ». La
>      transcription PUIS l'analyse se font là, avant que la feuille ne monte
>      (`VoiceMealSheet.preparer` : mêmes appels, même ordre, mêmes données envoyées). Dès que la
>      transcription existe, la carte la relit **mot à mot, du flou au net** (`MotsQuiArrivent`).
>      ⚠️ Les mots n'arrivent PAS pendant qu'on parle : la capture enregistre d'abord et transcrit
>      ensuite (voir `SpeechCaptureService`), décision conservée. Un « Annuler » réapparaît après
>      4 s de calcul : la scène couvre tout l'écran, il faut une sortie ;
>   4. **les résultats** : la bulle s'efface et **une feuille de verre DÉTACHÉE des bords** monte
>      (marges de 8, rayon 44, posée en bas à la taille de ce qu'elle montre ; elle défile si le
>      contenu dépasse) ; le voile reste jusqu'à ce qu'elle redescende. « Ton déjeuner » en 24/700
>      (« Ton repas » tant que le repas n'est pas choisi) et « 3 aliments reconnus », les lignes en
>      cascade (pastille de 40, nom, quantité, kcal ; UNE seule déployée à la fois pour régler sa
>      quantité), le total qui compte, **les étiquettes de ce que le repas apporte** (« Protéines
>      +42 g », glucides, lipides, fibres : des grammes, jamais un objectif inventé), « Ajouter au
>      déjeuner » en verre vert de 54 pt avec son reflet, puis « Modifier les quantités ». Gardés
>      alors que la maquette ne les montre pas : la citation de la dictée, les avertissements, le
>      choix du repas, l'action bloquée tant qu'il manque une quantité, « Recommencer la dictée » ;
>   5. **la confirmation sort de l'île** : à l'ajout (vibration de succès), la feuille redescend
>      AUSSITÔT. Une capsule noire part de la place de la Dynamic Island (126 × 37), se déplie
>      sous elle (350 × 68), sa pastille verte rebondit : « Ajouté au déjeuner », ce que le repas
>      change (« Fer et fibres en hausse », sinon « C'est compté dans ta journée. »), « +564 kcal »
>      (`PastilleConfirmation`, surcouche de la racine). Elle se replie seule après 2,9 s ; la
>      toucher ouvre le repas. Ce n'est PAS la vraie Dynamic Island (elle demanderait une activité
>      en direct) : une surimpression qui part de sa place et de sa taille ;
>   6. **le retour au Journal** : la carte Énergie gonfle à 1,035 et **compte** jusqu'à sa nouvelle
>      valeur, sa sous-ligne dit « Déjeuner ajouté · 3 aliments », l'anneau et les macros suivent.
>   **Plus de célébration dans la feuille** (pastille, onde, confettis, étiquettes, 2,1 s) : la
>   maquette ne garde qu'UN moment de confirmation, la capsule. La série et le gain chiffré
>   (« Fer +18 % ») ne sont donc plus montrés après un repas dicté ; la série se lit dans la puce
>   du Journal.
>   **Mouvement** : les quatre mouvements de `KiwiMotion` (`kiwiGlisse`, `kiwiFluide`, `kiwiRebond`,
>   `kiwiCompteur`) et `kiwiVif` pour l'appui (0,96) ; rien ne dépasse 1,22 (`KiwiEchelle.plafond`).
>   **Réduire les animations** : la bulle est posée d'emblée à sa place, liquide figé, ni onde ni
>   trajet ; la capsule arrive dépliée ; tout se fait en fondu.
>   « Écrire » ouvre la même feuille détachée sur un champ, sans la bulle. Les autres ajouts
>   (photo, recherche, code-barres) gardent la gratification décrite plus bas.
> - **Micronutriments** (1er octobre 2026, verre le 2 ; `JournalMicrosComponents.swift`, calcul
>   `Core/MicrosDuJour.swift`) — sous la saisie. **Réservé au Premium** : en gratuit (verrou
>   **défloué** le 7 oct. 2026, demande d'Arthur), la carte est NETTE : en-tête avec pastille
>   « 🔒 Premium », phrase neutre (« Tes 26 micronutriments, calculés sur tes repas… »), filtres,
>   **chaque micronutriment nommé** dans l'ordre du catalogue (6 lignes puis « Voir les N
>   autres »). Seuls les chiffres sont brouillés : jauge FACTICE floutée (longueur tirée du seul
>   identifiant, `MicroVerrouille.partFactice`) sous une pastille « Premium » sur chaque ligne ;
>   ni priorités, ni phrase « ta vitamine D est basse », ni repère de statut (ils diraient quelque
>   chose de la personne). Toucher une ligne ouvre la feuille Premium. La porte « Débloque tes
>   micronutriments » suit la carte (zone `journal_micros`). La carte porte son en-tête (feuille verte, « Micronutriments », « touche
>   pour le détail ») ; **les trois apports qui comptent le plus pour la personne**, puis tous les
>   autres derrière « Voir les N micronutriments ». Une ligne = le nom, un point et une jauge à la
>   TEINTE de l'apport, le pourcentage, un chevron ; un apport bas porte un petit signe rouge ou
>   orange après son nom. **Un seul chiffre par apport : la part du besoin couverte**, le même que
>   dans Progrès et dans la fiche de l'apport. Un bandeau ambré (`JournalMicrosAlerte`) passe
>   au-dessus de la carte Énergie quand un apport est bas au moins trois jours sur sept.
>   **La page d'un micronutriment est POUSSÉE** dans la pile du Journal (elle était une feuille) :
>   elle entre par la droite, la barre d'onglets reste là, la barre native est masquée et la page
>   dessine elle-même son retour « ‹ Journal » en vert (un glissé depuis le bord gauche la referme
>   aussi ; quitter l'onglet la referme). Elle montre : le nom en 34/700 ; une carte avec l'anneau
>   de 150 pt à la teinte de l'apport, le pourcentage qui compte, « de ton besoin » et l'étiquette
>   de niveau (Couvert · À renforcer · À combler) ; « Pourquoi c'est bas chez toi » (« D'où vient
>   ce chiffre » si l'apport n'est pas bas), les faits de la personne en cascade ; « Quoi ajouter
>   dans ton assiette », en pastilles de verre clair ; « Tes repas, jour par jour » (un jour pas
>   assez noté reste creux) ; à quoi il sert ; et, pour un apport du bilan, « Voir tout ce qui pèse
>   sur cet apport » (la fiche des causes).
> - **Poids et eau (1er octobre 2026)** (`JournalPoidsEau.swift`, calcul `Core/ObjectifPoids.swift`, eau
>   `Services/SuiviEau.swift`) — sous les micronutriments, avant la prise de sang ; les puces
>   « Poids » et « Eau » du haut de page y mènent. **Carte poids** : poids
>   actuel à gauche, **poids souhaité** à droite, chacun avec son moins et son plus (pas de 100 g, un
>   appui maintenu répète le pas). L'écart donne le SENS de l'objectif (perdre · prendre · maintenir à
>   moins d'un demi-kilo) ; les calories et les macros de la carte Énergie sortent des formules
>   existantes (`calculateMacros`), recalculées sous le doigt, enregistrées quand le geste s'arrête
>   (`JournalView.reglerPoids`, puis `DashboardViewModel.enregistrerPoids`). Le pied dit l'objectif du jour, le rythme et l'échéance estimée.
>   **Deux réserves : jamais de déficit vers un poids sous le repère de corpulence (IMC 18,5), ni
>   enceinte ou allaitante** — les calories restent au maintien et la carte le dit. Sans poids souhaité
>   réglé, rien ne change (les cibles suivent le premier objectif du questionnaire). **Carte eau** :
>   huit gobelets de 25 cl sur deux rangs, l'eau monte d'un coup de ressort ; toucher le dernier rempli
>   le vide ; compte gardé sur le téléphone, par compte et par jour (effacé à la déconnexion).
>   **Verre (2 oct.)** : les « − » et « + » sont des ronds de verre clair, les chiffres (poids, kcal,
>   litres) sont en SF Pro Rounded et ROULENT quand ils changent ; l'eau prend sa teinte
>   (`teinteEau`), ce qu'un toucher ajoute s'envole du gobelet (« +25 cl »), et le huitième gobelet
>   déclenche une gerbe de gouttes (sur un toucher seulement, pas en revenant sur un jour déjà plein).
> - **Offre annuelle** (`OffreAnnuelleOverlay.swift`, `Services/OffrePremium.swift`) : carte qui monte
>   du bas, surcouche de la RACINE comme la gratification. Elle n'affiche que ce qui est LU chez Apple
>   (prix annuel, équivalent d'un an à la semaine, essai gratuit) ; l'économie est le même calcul que
>   le badge du paywall. **Aucun compte à rebours.** « Voir l'offre » ouvre le paywall, « Plus tard »
>   referme. Comptes gratuits ayant fait leur bilan seulement, sur le Journal, après une gratification
>   ou au retour sur l'onglet ; jamais le premier jour, une fois tous les trois jours, puis toutes les
>   deux semaines après trois refus (`RythmeOffre`). Jamais pendant le tutoriel, le brief ou les captures.
>   **Verre (2 oct.)** : même grammaire que la feuille Premium — voile flou (`VerreVoile`), feuille de
>   verre aux coins de 38, titre 24/700, « Voir l'offre » en verre vert de 54 pt avec son reflet
>   (`PremiumAction`), « Plus tard » en vert. Pas de mascotte ici.
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
>   **Verre (2 oct.)** : la carte est la même feuille détachée des bords que les résultats de la
>   dictée (marges de 8, rayon 44), posée sur le voile flou. **Un repas dicté n'ouvre plus cette
>   carte** : la capsule du haut de l'écran le confirme. Photo, recherche et code-barres la gardent.
> - **Enchaînements (21 sept. 2026)** : les blocs de toute feuille arrivent l'un après l'autre, de
>   haut en bas (`FicheBloc(rang:)` → `kiwiEntrance`, plafonné, coupé sous Reduce Motion) ; depuis
>   le verre, les LIGNES d'un bloc arrivent à leur tour en cascade (`.verreCascade`, délais de la
>   maquette) ; les cartes « À quoi c'est relié » arrivent de gauche à droite ; la carte de
>   gratification REDESCEND avant que « Modifier » n'ouvre la fiche du repas ; la carte du Plan
>   suit la sélection en fondu flouté.
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
>   **Verre (2 oct.)** : c'est LA fiche que la maquette dessine. Feuille de verre (coins de 38) ; les
>   causes puis les gestes arrivent en cascade, leurs filets avec elles ; les barres de poids se
>   remplissent en 0,8 s ; pastilles numérotées vert foncé sur vert pâle ; aliments en pastilles de
>   verre clair qui surgissent.
> - **Bilan complet** (`DashboardView.swift`, `BilanV7Components.swift` ; « Tout afficher » du
>   Journal) : une PAGE présentée en feuille, avec sa pile de navigation (elle pousse l'historique
>   du score) : fond `VerrePageFond()`, croix `DSCloseButton`, cartes de verre en cascade, libellés
>   de catégorie teintés (`BilanV7SectionLabel(teinte:)`), jauge d'un apport à la teinte de
>   l'apport. La maquette ne dessine pas cet écran : il est habillé par le système, sans changement
>   de contenu.
> - **Compléments** (`SupplementsView.swift`, `SupplementsChainV6.swift`, `AnneauDeCause.swift`,
>   `FicheApport.swift`) — **l'anneau de cause, maquette du 20 septembre 2026**, passée au verre le
>   2 octobre. La barre de navigation est masquée : « Compléments » est une ligne de 17/600 centrée
>   qui défile avec la page, suivie de la précision « Kiwio ne gagne rien sur ce qu'il te
>   recommande ». Puis :
>   - **« Ton rituel du jour »** : trois tuiles matin · midi · soir qui disent QUOI prendre, et un
>     compteur qui roule. Un toucher coche le moment : la tuile passe au vert kiwi, la coche se
>     dessine en 0,3 s dans un rond vert qui rebondit, une gerbe part ; en décochant, rien ne
>     saute. Visible dans les deux voies ;
>   - **la bascule de verre** Compléments · Par l'assiette (`VerreBascule`), qui pilote toute la
>     page : le corps échangé arrive en fondu, remonte de 8 pt et sort d'un flou de 4 pt ;
>   - **voie Compléments, la mosaïque** : 1 héros pleine largeur (anneau 112 + les 3 freins les
>     plus lourds et leur poids, en cascade) puis des tuiles deux par deux (anneau 64), une tuile
>     restante passe en ligne pleine largeur, jamais de trou. Les parts de l'anneau se tracent
>     l'une après l'autre et le chiffre compte ; anneaux et cascades se rejouent à chaque arrivée
>     sur l'onglet et à chaque bascule. **Ni dose, ni prix, ni marque sur une tuile.** Ligne « Ma
>     sélection » (budget mensuel) sous la mosaïque ;
>   - **voie Par l'assiette** : UNE carte de verre, une ligne par apport (pastille de 40 à la
>     teinte de l'apport, son premier aliment en titre, les suivants en précision, le nom de
>     l'apport à droite), les lignes arrivent l'une après l'autre. **Aucun pourcentage, aucune
>     portion ni fréquence par aliment** (la donnée n'existe pas) ; plus de tuiles à anneau dans
>     cette voie.
>   Au toucher, la **fiche en six blocs** (feuille de verre) : ce que ça peut
>   expliquer chez toi (la phrase de la table déterministe `SymptomesApports`, jamais le texte libre
>   du bilan ; le score a décidé, le symptôme éclaire) · comment on l'a vu (**cascade** : point de départ 70,
>   freins, appuis, « ramené dans l'échelle » si le total sort de 0-100 ; chaque frein porte une
>   barre de poids qui se remplit ; toucher une ligne allume sa part sur l'anneau) · ce que ça fait ·
>   comment le prendre (**la forme et le moment, jamais la dose** : doctrine du 20 septembre) ·
>   précautions et interactions · l'autre voie. **Le chiffre est le score déterministe du registre**
>   (`Core/NutrientLedger.swift`, même arithmétique que `analyzeNutrientScores`) : part couverte dans
>   la couleur de l'apport, freins en trois gris décroissants, « autres facteurs » en piste inactive,
>   parts qui ferment toujours à 100. Le pourcentage rédigé par le bilan n'est plus affiché dans cet
>   onglet. Quantités et moments d'un aliment restent dans la fiche nutriment existante, liée depuis
>   la fiche. États gardés, en verre : carte d'exemple avant le bilan, état vide, mention médicale.
> - **Progrès : la toile** (`SuiviView.swift` + `ProgresComponents.swift` + `ProgresV3Components.swift`,
>   maquette « Verre liquide » du 2 octobre 2026 ; elle recompose le « Progrès v3 » du 20 septembre
>   avec les mêmes données, sans appel réseau ni IA à l'affichage). Barre de navigation masquée,
>   « Progrès » (34/700) dessiné dans la page. De haut en bas :
>   1. **les puces** : Équilibre « N sur 10 » (avec la toile en miniature), une puce par évolution
>      RÉELLEMENT connue (un symptôme dont la tendance a bougé, l'apport qui a le plus bougé depuis
>      le départ ; aucune en gratuit), la Série ;
>   2. **la toile** (`ProgresToileView`) : les dix apports sur un radar, un axe par apport, le
>      besoin en cercle pointillé (le score 60, seuil « à renforcer » de l'app), un chiffre au
>      centre. Les valeurs montent en 1,3 s à chaque arrivée sur l'onglet. Toucher un point ou un
>      libellé choisit l'apport (les autres pâlissent, le centre dit son nom, sa part et son
>      statut) ; le toucher à nouveau, ou toucher le centre, le relâche. Les chiffres sont ceux de
>      `DashboardViewModel.registre` : un seul chiffre par apport dans toute l'app ;
>   3. **le verdict** : un titre 28/700 (« Ton équilibre progresse / est stable / est à
>      surveiller », comparé au premier bilan ; « Ton équilibre du jour » en gratuit ou le premier
>      jour), une phrase (« 6 apports sur 10 atteignent ton besoin aujourd'hui. »), puis le lien
>      « Voir ta progression depuis le départ » (cadenas et offre en gratuit ; en Premium il fait
>      défiler jusqu'à « En coulisses ») ;
>   4. **« Ce qui a changé »**, des cartes de verre empilées (le sélecteur Symptômes · Apports ·
>      Calories a disparu) : **le symptôme suivi** (un seul à la fois, un menu pour en changer :
>      son verdict, sa courbe qui se dessine — **le haut est toujours le mieux** —, ses réponses au
>      check-in) ; **la semaine des apports** et **celle des calories** (sept jours réels, jour
>      hors cible en ambre, pointillé du besoin, pas de barre pour un jour sans repas) ; **« En
>      coulisses »** : chaque apport suivi, de son score du premier bilan à celui d'aujourd'hui, la
>      ligne ouvre la fiche de l'apport ;
>   5. **le bas de page** : la porte vers le bilan tant qu'il n'est pas fait, la ligne du check-in
>      du jour tant qu'il n'est pas répondu, la ligne du récap du jour.
>   Check-in : feuille de verre, **un symptôme par écran**, question dans le sens du mieux, toucher
>   = choisir ET avancer, proposé à l'arrivée sur l'onglet (jamais au lancement). **Frontière
>   Premium inchangée** (zones `suivi_symptomes`, `suivi_micros`) : en gratuit la page nomme le
>   sujet, jamais sa tendance. La porte n'est plus une carte : c'est le bouton de verre vert « Voir
>   ta courbe » posé sur la courbe floutée, le lien sous le verdict et les lignes d'« En
>   coulisses » ; la feuille Premium grandit depuis ce qu'on a touché (iOS 18 et plus). La carte
>   « Cette semaine, en trois lignes » n'existe plus en tant que carte : ses phrases
>   (`ProgresVerdict`, pur et testé) vivent dans les cartes. Premier jour sans repas : une seule
>   carte, qui le dit (`ProgresPremierJourCard`).
> - **Plan en graphe** (`PlanGraphComponents.swift`, modèle `Core/PlanGraph.swift`, physique
>   `Core/PlanGraphPhysique.swift` ; maquette du 20 sept. 2026, physique validée le 30 sept., verre
>   le 2 oct.) : **trois couleurs qui portent le sens** — vert = l'objectif (centre), bleu =
>   les symptômes suivis (anneau 1, quatre au plus), gris = les leviers (anneau 2 : apports que le
>   bilan rattache à ce qui est affiché, et **habitudes tirées du registre des apports**, mêmes
>   libellés et mêmes points que la fiche de l'apport). Trait épais = lien fort. Le titre « Plan »
>   reste le grand titre natif ; dessous, un sous-titre et la légende à trois points.
>   **Une physique à la façon d'Obsidian** : les bulles se repoussent, les tiges qui les relient les
>   retiennent ; on attrape une bulle, ses voisines suivent, et tout revient en place quand on la
>   lâche. Le point de départ est le placement calculé des trois anneaux. Réglages validés par
>   Arthur (répulsion 1150, raideur 15, amorti 0,70) : **on n'y touche pas sans lui**. Ni zoom ni
>   déplacement de la carte.
>   **Verre** : un nœud qui n'est ni choisi ni le centre garde sa teinte, en pâle ; le choisir
>   l'allume (pleine couleur, halo, rebond 1 → 0,86 → 1,1 → 1). Les liens du nœud choisi passent
>   au vert et à 3 pt en 0,3 s, une pulsation les parcourt ; les noms hors de son voisinage
>   s'estompent. **Entrée en scène à chaque arrivée sur l'onglet** : les nœuds éclosent depuis
>   l'objectif (0,3 → 1, 0,09 s d'écart), puis les liens se tracent (0,6 s chacun). **L'horloge est
>   en pause hors de l'onglet** (`\.estOngletActif`, posé par la racine sur chaque onglet — à
>   préférer à `onAppear`, qui ne se joue qu'au lancement) ; sous Reduce Motion le graphe est
>   calculé une fois, puis fixe, sans glisser-déposer.
>   **La carte du nœud choisi** est une plaque de verre qui flotte (rayon 28) au-dessus de la barre
>   d'onglets : pastille, catégorie colorée, nom, résumé (un état, jamais un geste), rond vert
>   « détail ». Quand on change de nœud, la plaque reste en place et son contenu sort d'un léger
>   flou. Elle ouvre **la feuille du nœud**
>   (`PlanNoeudSheet`, feuille de verre) : pastille + sur-titre coloré + nom · la cause · **« À quoi c'est
>   relié »** (rangée de cartes : état du voisin — « 42 % », « −22 points » — et force du lien, lisible
>   en gratuit) · **« Quoi changer dans ton assiette »** (pastilles de verre clair à illustration 3D,
>   `DSFlow` ; en toucher une la déplie : combien, quand, comment, l'astuce) · **« Tes habitudes »** ·
>   **« En complément »** (nom + étiquette, **jamais de dose** : `PlanTopicText.sansDose`, lien vers
>   l'onglet Compléments) · délai · « C'est noté ». Gratuit : cause et liens en clair, les trois blocs
>   de solutions voilés, porte `plan_solutions`. Une habitude ouvre sa feuille à elle (la cause et ce
>   qu'elle freine). Avant le bilan : un graphe d'exemple estompé, où tout toucher mène au bilan.
>   Le sélecteur « Objectifs et symptômes / Apports »
>   et la ligne « focus de la semaine » ont disparu : le graphe montre les deux lectures à la fois.
> - **Réglages** (`ReglagesView.swift` + `ReglagesSousPages.swift`, maquette « Réglages v3 » du
>   20 sept. 2026, verre le 2 oct.) : même ordre — Premium, compte, questionnaire, application —
>   sur le fond de verre neutre, grand titre natif. **Le bloc Premium est UNE ligne de verre** : la
>   mascotte (44 pt, immobile), « Kiwio Premium », l'essai lu chez Apple en vert foncé (sans essai,
>   la promesse existante), un chevron vert ; le prix reste juste dessous, toujours lu chez Apple
>   (trait gris tant qu'il charge). Abonné : la même carte (« Premium actif » et l'échéance), sans
>   chevron, puis « Gérer mon abonnement », aucun argumentaire. La carte n'apparaît qu'une fois le
>   bilan fait. Toucher la ligne : la feuille Premium grandit depuis elle (iOS 18 et plus).
>   Dessous, des cartes de verre **sans en-tête** (les groupes se lisent par l'écart entre cartes) :
>   identité, objectifs, abonnement, Apple Santé, export · questionnaire · Notifications
>   (interrupteur), « Widgets et écran verrouillé », tutoriel, bilan animé, méthode · liens
>   Restaurer · Conditions · Confidentialité · déconnexion + suppression. Une ligne = une pastille
>   CARRÉE de 30 pt (rayon 8), le libellé, un filet de 0,5 pt posé sous le libellé seul ; pastilles
>   à **trois sens** (gris / vert = connecté ou actif / rouge = destructif). Les lignes arrivent en
>   cascade à chaque visite de l'onglet.
>   L'interrupteur Notifications porte `RappelsPersonnalises.actifs` et lève l'ancien mode Zen,
>   qui n'a plus d'interrupteur à l'écran. Sous-pages (fond `VerrePageFond()`, cartes de verre,
>   réserve de la barre d'onglets) : compte (mot de passe si compte e-mail), objectifs, abonnement,
>   suppression du compte (double verrou), questionnaire en édition, méthode, widgets ; leurs
>   feuilles et leurs champs de saisie sont en verre.
> - **Feuille Premium** (`PaywallView.swift`, maquette validée le 3 juillet 2026, verre le 2 oct.) :
>   feuille de verre (coins de 38), **la mascotte de 84 pt** qui éclot sur son halo tournant,
>   « Kiwio Premium » en vert foncé puis la promesse en 24/700, les bénéfices en cascade (pastilles
>   teintées), les cartes de formule (liseré vert sur celle qui est choisie), l'action principale
>   en verre vert de 54 pt avec son reflet (`PremiumAction`), la mention d'abonnement, « Plus tard »
>   en vert, puis le code promo, la restauration, les liens, et la croix « Fermer ». **Formules,
>   prix, essai et mentions sont lus aux mêmes endroits qu'avant** (jamais en dur) : les textes
>   d'exemple de la maquette ne sont pas repris. Elle grandit depuis ce qu'on a touché (zoom iOS 18
>   et plus, feuille simple sur iOS 17 : `feuillePremium`, `premiumOrigine` / `premiumDepuis` dans
>   `PremiumGating.swift`). **Contenu verrouillé, partout** : un seul traitement, flou 8 et opacité
>   0,5, sans voile blanc ; portes (`UnlockDoor`), jauges de quota et écrin Premium en verre.
>   (Exception : la carte Micronutriments du Journal, défloutée — voir plus haut.)
> - **Feuille Premium « Oups ! » — limite du jour atteinte** (7 oct. 2026, `LimiteDuJour.swift`,
>   `PaywallView(limite:)`) : quand un non-abonné bute sur ses scans photo, ses dictées ou ses
>   repas écrits (429 du serveur, ou bouton dont le quota local est épuisé), plus jamais de simple
>   message d'erreur : la feuille Premium monte en mode limite. De haut en bas : **« Oups ! » en
>   64 arrondi**, ce qui est épuisé (« Tu as utilisé tes 3 scans photo du jour » ; dictée et
>   texte partagent leur quota, la phrase le dit), « Ça se recharge demain. Ou passe à Kiwio
>   Premium pour suivre tes apports de fond en comble » ; **« Ce qui t'attend »** : trois
>   captures dessinées en téléphones (micronutriments chiffrés, semaine d'un apport, aliments qui
>   en apportent) sur des **données d'exemple, étiquetées comme telles** ; « Avec Kiwio Premium » et
>   six bénéfices (30 scans, dictées et repas écrits, micronutriments chiffrés, tendances,
>   pourquoi de chaque apport, plan) ; puis l'achat habituel. Vaut pour tout non-abonné, bilan
>   fait ou non (l'événement « limite » n'est pas la porte permanente de `ScanQuotaUI`). Un abonné
>   au bout de son plafond lit toujours « ça se recharge demain ».
>
> - **Widgets, écran verrouillé, activité en direct** (refonte « en verre » du 3 oct. 2026, maquette
>   Claude Design « Kiwio - Widgets », W1 à W7 ; briques dans `Partage/VuesWidgets.swift`, vues dans
>   `Partage/Widgets*.swift`, configurations dans `KiwioWidgets/`) : six widgets, des accessoires
>   d'écran verrouillé et une carte en direct, qui disent ce que dit le Journal, jamais autre chose.
>   **Le verre** : texte blanc, plaques blanches translucides, bouton vert (dégradé `#96E26C` →
>   `#5DA838`) pour ce qui se touche, pastille pâle pour ce qui est fait. Un widget ne voit pas le fond
>   d'écran : en couleurs pleines, `FondVerreW` peint la base verte de la maquette puis le verre ; en
>   Teinté et Transparent (iOS 18, iOS 26), iOS pose son propre verre et les illustrations 3D gardent
>   leurs couleurs. Le verre est le même en mode clair et sombre. Teintes des apports et des repas :
>   celles de la maquette, faites pour le verre et distinctes de la palette de l'app (vitamine D
>   `#FFB547`, magnésium `#AFAEFF`, fer `#F0B27A`, les sept autres dérivées ; repas matin `#FFB547` ·
>   midi `#8FDB62` · soir `#AFAEFF` · encas `#FF8FB1`). **Tes apports** (petit : l'apport le plus bas
>   en anneau, son score, un aliment pour le prochain repas ; moyen : le verdict, les trois anneaux,
>   « Voir le calcul » ; grand : l'apport en grand, sa cause, « Ce qui la remonte » en pastilles, les
>   autres en barres ; rond, rectangulaire et en ligne sur l'écran verrouillé) : un seul chiffre par
>   apport, celui du registre, et les mots de la fiche (`LectureApport`), jamais recalculés.
>   **Conseil du jour** (petit, moyen, rectangulaire) : un geste par jour pour l'apport à renforcer,
>   tiré des gestes de la fiche, qui change à minuit sans ouvrir l'app ; « C'est fait » se coche et se
>   décoche sur place ; le geste est réservé au Premium, comme « Ce que tu peux faire » dans la fiche ;
>   **jamais de dose**. **Ajout rapide** (petit : le micro et la question du repas de l'heure, « Ton
>   midi ? » ; moyen : Dicter en grand, puis Photo, l'eau, le rituel, Chercher ; rond : le micro).
>   **Eau** (le verre qui se remplit vraiment, les litres, « + 25 cl » jusqu'à l'objectif ; rond : les
>   verres en anneau, un toucher ajoute un verre). **Rituel du jour** (petit : le prochain moment à
>   prendre ; moyen : matin · midi · soir ; **jamais de dose**). **Ma journée** (même rôle, habillé
>   comme la carte en direct : les kcal, la barre des repas, les quatre repas qui ouvrent leur fiche).
>   **Activité en direct « Ta journée »** : la journée en une barre (chaque repas sa couleur), les kcal
>   restantes, la série, puis Dicter · eau · prise du moment ; Dynamic Island compacte (le signe, les
>   kcal), minimale (l'anneau du jour) et étendue (l'anneau, le prochain repas, Dicter et l'eau) ; un
>   jour périmé dit « Nouvelle journée » au lieu des chiffres de la veille. Règle de geste : l'eau, le
>   rituel et le conseil se cochent sur place ; Dicter, Photo, Chercher, un repas et un apport ouvrent
>   l'app au bon endroit (« Voir le calcul » et « Pourquoi ? » : la fiche de l'apport, servie par le
>   Journal). Accessoires d'écran verrouillé : monochromes, comme iOS les dessine. Réglages → Widgets
>   et écran verrouillé : l'interrupteur « Ma journée en direct », l'écran verrouillé en miniature sur
>   le fond d'écran de la maquette (accessoires et carte en direct), les widgets d'accueil à leur
>   taille d'iPhone 16 (les vraies vues, nourries par la journée en cours, sinon par un exemple), le
>   mode d'emploi en trois lignes.
>
> - **Prise de sang** (Premium, 30 sept. 2026 — maquette validée le 6 juil., `Views/PriseDeSang/PriseDeSangSheet.swift`) :
>   une carte du Journal (`PriseDeSangCarte`, sous « Poids et eau » ; la puce « Analyses » y mène —
>   elle a quitté « Autres façons d'ajouter » le 1er octobre, où personne ne la voyait) et carte
>   « Ta prise de sang » du Bilan complet (entre points d'attention et symptômes). Feuille de verre : gratuit →
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
> apports, barre d'onglets (« Reviens demain » + « J'ai compris »). Voile découpé par
> `destinationOut` — depuis le verre, c'est le voile du système (`VerreVoile`, encre à 22 % sur un
> flou vivant) et non plus une encre à 64 % : la cible ressort parce qu'elle est la seule chose
> NETTE de l'écran ; la bulle et la carte de bienvenue sont en verre flottant, leurs actions en
> verre vert (points de progression, « Passer »), un seul geste
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

> Ces lois datent du 11 juin 2026. Celles qui parlent de contenu tiennent toujours. Quatre lois
> d'habillage sont **remplacées par le verre** (2 octobre 2026, `docs/DESIGN-SYSTEM.md`) : la 2 (le
> thème clair reste forcé, mais le fond est le fond de verre et les cartes sont en verre), la 6
> (rayons : 24 pour une carte, 14 pour une tuile, 38 pour une feuille), la 7 (bouton secondaire =
> `.verreClair()`, appui = `.dsPress`) et la 17 (les quatre mouvements de `KiwiMotion`).

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

**Questionnaire ludique (3 octobre 2026, maquette avant / après validée par Arthur : « c'est top »)**
— retour : « trop de freins, trop générique, pas assez ludique », surtout les aliments. Ce qui
change, présentation seule (`Views/Questionnaire/BilanLudique.swift`) :
- **le kiwi parle** : `KiwiMascotte` (animée) en haut de chaque écran, sa bulle (`BilanKiwi`) dit
  pourquoi on demande, puis la piste que les réponses font apparaître (elle remplace la carte de
  piste du bas) ; elle fête aussi la fin d'une étape et l'écran de fin ;
- **une question à la fois** (`BilanQuestions`) : sur un écran à thème, la réponse donnée se range
  en pastille (touchable pour corriger) et la suivante arrive seule après 0,55 s (1,1 s pour un
  curseur) ; le bouton du bas ne sert qu'en fin d'écran ;
- **un chemin à quatre stations** (`BilanChemin`) remplace la barre à quatre segments dans
  l'en-tête (le Journal garde ses segments) ;
- **grandes cartes** (`BilanCartes`) ; les bascules oui / non deviennent deux cartes (mêmes
  valeurs `yes` / `no`) ; le stress et le réveil font vivre un visage (`BilanVisage`) ;
- **aliments, « remplis ta journée »** : frise des quatre repas avec le nombre d'aliments cochés,
  ciel qui passe du matin au soir (aube, ciel, kiwi, orchidée via `EcranBilan.teinteVerre`),
  assiette en dix parts (`BilanAssiette`, même mesure que les dix jauges d'avant) avec une bulle
  qui dit ce que l'aliment apporte, et les trois mots qui s'ouvrent **sous la rangée** de
  l'aliment touché (`BilanGrilleAliments`, `BilanTiroirNiveau`) au lieu d'une barre flottante qui
  cachait la grille ; boutons « Repas suivant : Midi » … « J'ai fini ma journée » ;
- **fin d'étape** : les pistes arrivent face cachée (`BilanCartePisteCachee`), on les retourne.

Code : `Views/Questionnaire/Bilan*.swift` (vue), `Core/ParcoursBilan.swift` (ordre, écrans
visibles, ce qu'il faut avoir répondu), `Core/PistesBilan.swift` (ce que les réponses apprennent),
`Core/RepasCatalog.swift` (aliments par repas), `Core/NiveauConsommation.swift` (les trois mots),
`Core/LibellesBilan.swift` (les mots des réponses). L'état reste dans `QuestionnaireViewModel`.

**Quatre étapes, une couleur chacune** (`EtapeBilan.teinte`, prises dans la palette du verre depuis
le 2 octobre 2026) : ① Toi (bleu `teinteProteines`) · ② Ton quotidien (orange `teinteLipides`) ·
③ Ta forme (orchidée `teinteFer`) · ④ Ton assiette (vert kiwi). L'étape se lit sur **le fond de
verre** (`VerreFond`, dont les halos passent de ciel à aube, orchidée puis kiwi, en fondu), sur le
nom du chapitre et sur le segment de la barre. **Une réponse choisie, elle, passe au verre vert**
(verre vert pâle, liseré kiwi, texte vert foncé), quelle que soit l'étape, et **le bouton du bas
reste vert d'un bout à l'autre** (verre vert de 54 pt ; verre clair et libellé estompé tant que
l'écran attend une réponse). Écart assumé à la règle « le vert ne colore que ce qui se tape » :
ici la couleur porte un sens, l'étape, comme la couleur d'une jauge porte un statut. Tuiles, puces
et lignes de réponse sont en verre clair, cartes et curseurs en cartes de verre ; les écrans
glissent (`kiwiGlisse`) et leurs blocs arrivent en cascade (`.bilanCascade`).

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
   encre · « encore ~2 min » · pilule de verre clair « N pistes » (un symbole SF, plus la loupe
   en emoji).
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
8. **Identité** : le signe (`KiwiSigne`) sur l'accueil et sur la fin ; aucun emoji kiwi. Les
   emojis qui illustrent les réponses (catalogues `LibellesBilan`, `GroceryCatalog`…) sont
   toujours là : les retirer est une décision produit, pas un habillage.
9. **Mouvement** : jetons de `KiwiMotion` uniquement, rien au-delà du plafond `KiwiEchelle.plafond`
   (1,22 depuis le verre), tout coupé par « Réduire les animations ». La gerbe de fin d'étape se
   joue une fois.

L'ancien flux (`QuestionnaireContainerView`, `GroceryShoppingView`, `SectionIntroView`,
`TeaserEngine`, `QuantityBracket`) reste dans le dépôt, plus présenté, tant que le nouveau n'est
pas validé sur appareil ; il part ensuite dans une PR à part.

---

*Maquettes de référence : session du 11 juin 2026 (« rendu_final_4_ecrans_reference »
+ correctifs « Pourquoi ? » et règles déterministes). Contrat IA : prompt v35
(generate-analysis v40), harnais de conformité sur audit-a/b/c obligatoire avant
tout déploiement de prompt.*
