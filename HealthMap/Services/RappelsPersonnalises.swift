import Foundation
import UserNotifications

// MARK: - Rappels personnalisés (notifications LOCALES)
//
// Décision d'Arthur du 11 sept. 2026 : option A — les notifications sont
// préparées SUR LE TÉLÉPHONE, à partir du bilan et des repas notés, et
// recalculées à chaque ouverture pour les 7 jours qui suivent. Aucun serveur,
// aucune clé Apple Push, et aucune donnée de santé ne quitte l'appareil.
//
// Refonte du 1er oct. 2026 (« très factuel et très aguicheur ») : on passe de
// trois rappels sans chiffre à une journée rythmée, où CHAQUE rappel ouvre sur
// un fait de la personne.
//
//   · 8 h 30  — le brief : « Hier : 6 besoins sur 10 couverts » (dès demain :
//               aujourd'hui, l'app est déjà ouverte)
//   · 10 h    — le déclic, un jour sur deux : ce qui freine un apport d'après
//               le questionnaire, et ce que ça coûte en points
//   · 12 h 15 — midi : où en était l'apport le plus bas hier, quoi manger
//   · 16 h 15 — l'encas : où en est l'apport AUJOURD'HUI
//   · 19 h 15 — le soir : idem, avec le conseil du bilan
//   · 21 h 15 — le dernier appel, seulement si la journée est commencée et
//               que le dîner manque
//   · dimanche 18 h — la semaine en chiffres
// Plus un rappel de retour au 7e jour : il ne sonne que si l'app n'a pas été
// rouverte d'ici là (chaque ouverture replanifie tout). Et, pour qui a importé
// une prise de sang, un rappel le jour où elle passe 6 mois (elle compte alors
// moitié moins) : il dit son âge, jamais une valeur.
//
// La journée pleine ne vaut que pour AUJOURD'HUI et DEMAIN — la personne
// vient d'ouvrir l'app. Au-delà, on retombe à trois rappels par jour : celui
// qui n'ouvre plus n'a pas à être harcelé.
//
// D'où viennent les faits, et pourquoi ils restent vrais à l'heure où ça
// sonne : tout changement du journal passe par l'app, et chaque passage
// replanifie. Un rappel qui sonne sans avoir été recalculé prouve donc que
// rien n'a été noté entre-temps — « rien de noté aujourd'hui » se planifie la
// veille sans mentir. Quand le journal est illisible au moment de planifier
// (hors-ligne), on n'affirme RIEN : formulations d'avant, sans chiffre.
//
// Garde-fous :
//   · un repas déjà noté (ou préparé d'avance) sur un créneau annule le rappel
//     de ce créneau ;
//   · le mode Zen coupe tout — il le promet dans les Réglages ;
//   · déconnexion = tout est retiré (un autre compte ne doit jamais voir
//     « ton fer » de l'utilisateur précédent sur l'écran verrouillé) ;
//   · seules les habitudes ALIMENTAIRES du questionnaire peuvent s'afficher :
//     ni traitement, ni âge, ni tabac sur un écran verrouillé.

struct RappelPlanifie: Equatable {
    let id: String
    let date: Date
    let titre: String
    let corps: String
    /// Écran ouvert au tap (valeur brute de `DeepLinkRoute`).
    let ecran: String

    /// « midi », « declic »… — le rappel sans son jour. Part avec le tap, pour
    /// savoir LEQUEL fait revenir.
    var type: String {
        let sansPrefixe = id.hasPrefix(RappelsPersonnalises.prefixe)
            ? String(id.dropFirst(RappelsPersonnalises.prefixe.count))
            : id
        return sansPrefixe.split(separator: ".").first.map { String($0) } ?? sansPrefixe
    }
}

// MARK: - Ce que le journal sait d'un jour

struct JourNote: Equatable {
    /// Repas notés ce jour-là.
    var repas = 0
    var creneaux: Set<MealJournalService.MealSlot> = []
    /// Part du besoin couverte, par nutriment (`BriefDuJourBuilder.couverture`).
    var couverture: [String: Int] = [:]

    static let vide = JourNote()

    /// Assez noté pour qu'un pourcentage décrive l'alimentation, pas la saisie
    /// — même règle que le brief. Des repas sans apports chiffrés (ajouts
    /// anciens) ne comptent pas.
    var chiffrable: Bool {
        repas >= BriefDuJourBuilder.repasMinimum && !couverture.isEmpty
    }

    var besoinsCouverts: Int { BriefDuJourBuilder.besoinsCouverts(couverture) }
}

// MARK: - La matière des rappels

struct ContexteRappels: Equatable {
    /// Apports à renforcer, dans l'ordre du bilan.
    var cibles: [CibleNutritionnelle] = []
    /// `false` = le journal n'a pas pu être lu : aucun rappel n'affirme alors
    /// quoi que ce soit sur ce qui a été noté.
    var journalConnu = false
    /// Les jours où quelque chose est noté, par décalage depuis aujourd'hui
    /// (−1 = hier, 0 = aujourd'hui, 1 = demain — un repas préparé d'avance).
    /// Un jour absent n'a rien de noté.
    var jours: [Int: JourNote] = [:]
    /// Repas notés depuis lundi, et sur combien de jours.
    var repasSemaine = 0
    var joursNotesSemaine = 0
    /// L'apport qui a le plus progressé sur la semaine précédente.
    var effort: BriefDuJour.Effort?
    /// La série affichée dans l'app (`GamificationService.currentStreak`),
    /// si elle a été prolongée AUJOURD'HUI ; 0 sinon. C'est ce chiffre-là
    /// qu'on cite, pas un recompte : l'app et la notification ne doivent pas
    /// annoncer deux séries différentes.
    var serieDuJour = 0
    /// Le prélèvement de la dernière prise de sang importée, s'il y en a une :
    /// le jour où elle passe 6 mois, un rappel le dit.
    var priseDeSang: Date?

    func jour(_ decalage: Int) -> JourNote { jours[decalage] ?? .vide }

    /// Depuis les repas lus dans le journal (deux semaines passées, et les
    /// jours à venir pour les repas préparés d'avance).
    static func construire(
        cibles: [CibleNutritionnelle],
        repas: [MealJournalService.MealRecord],
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> ContexteRappels {
        let aujourdhui = calendar.startOfDay(for: maintenant)

        var parJour: [Int: [MealJournalService.MealRecord]] = [:]
        for record in repas {
            let jour = calendar.startOfDay(for: record.consumedAt)
            guard let decalage = calendar.dateComponents([.day], from: aujourdhui, to: jour).day else { continue }
            parJour[decalage, default: []].append(record)
        }
        var jours: [Int: JourNote] = [:]
        for (decalage, duJour) in parJour {
            guard let premier = duJour.first else { continue }
            jours[decalage] = JourNote(
                repas: duJour.count,
                creneaux: Set(duJour.map(\.slot)),
                couverture: BriefDuJourBuilder.couverture(jour: premier.consumedAt, repas: duJour, calendar: calendar)
            )
        }

        let semaine = WeekScoreEngine.currentWeekInterval(containing: maintenant)
        let deLaSemaine = repas.filter { semaine.contains($0.consumedAt) }

        return ContexteRappels(
            cibles: cibles,
            journalConnu: true,
            jours: jours,
            repasSemaine: deLaSemaine.count,
            joursNotesSemaine: Set(deLaSemaine.map { calendar.startOfDay(for: $0.consumedAt) }).count,
            effort: BriefDuJourBuilder.effort(cibles: cibles, repas: repas, maintenant: maintenant)
        )
    }
}

enum RappelsPersonnalises {

    static let prefixe = "kiwio.rappel."
    /// Identifiants des deux rappels fixes d'avant le 11 sept. 2026 : retirés à
    /// chaque planification, sinon ils sonneraient en double.
    static let anciensIdentifiants = ["kiwio.reminder.lunch_scan", "kiwio.reminder.evening_checkin"]
    static let horizonJours = 7
    /// Aujourd'hui et demain ont la journée pleine ; ensuite, trois par jour.
    static let joursPleins = 2
    /// En dessous, « ta semaine en chiffres » n'aurait rien à chiffrer.
    static let repasMinimumSemaine = 3

    enum Moment {
        static let brief = (heure: 8, minute: 30)
        static let declic = (heure: 10, minute: 0)
        static let midi = (heure: 12, minute: 15)
        static let encas = (heure: 16, minute: 15)
        static let semaine = (heure: 18, minute: 0)
        static let soir = (heure: 19, minute: 15)
        static let dernierAppel = (heure: 21, minute: 15)
        static let priseDeSang = (heure: 10, minute: 30)
    }

    // MARK: - Planification (pure, testable)

    static func planifier(
        contexte: ContexteRappels,
        maintenant: Date = Date(),
        calendar: Calendar = .current
    ) -> [RappelPlanifie] {
        let aujourdhui = calendar.startOfDay(for: maintenant)
        let cibles = contexte.cibles
        var rappels: [RappelPlanifie] = []

        func instant(_ jour: Int, _ moment: (heure: Int, minute: Int)) -> Date? {
            guard let date = calendar.date(byAdding: .day, value: jour, to: aujourdhui) else { return nil }
            return calendar.date(bySettingHour: moment.heure, minute: moment.minute, second: 0, of: date)
        }

        /// N'ajoute que ce qui sonne dans le futur.
        func ajouter(
            _ type: String,
            jour: Int,
            _ moment: (heure: Int, minute: Int),
            _ texte: (titre: String, corps: String),
            ecran: String
        ) {
            guard let date = instant(jour, moment), date > maintenant else { return }
            rappels.append(RappelPlanifie(
                id: "\(prefixe)\(type).\(jour)",
                date: date,
                titre: texte.titre,
                corps: texte.corps,
                ecran: ecran
            ))
        }

        for jour in 0..<horizonJours {
            guard let dateDuJour = calendar.date(byAdding: .day, value: jour, to: aujourdhui) else { continue }
            // Le rang du jour dans le calendrier, pas dans l'horizon : quelqu'un
            // qui ouvre l'app chaque jour ne reçoit que des « jour 0 », et
            // tomberait sinon toujours sur la même variante et le même apport.
            let rang = calendar.ordinality(of: .day, in: .era, for: dateDuJour) ?? jour
            let plein = jour < joursPleins
            // `nil` = journal illisible : on ne sait pas, donc on n'affirme pas.
            let veille: JourNote? = contexte.journalConnu ? contexte.jour(jour - 1) : nil
            let jourMeme: JourNote? = contexte.journalConnu ? contexte.jour(jour) : nil
            let creneauxNotes = jourMeme?.creneaux ?? []

            // 10 h — le déclic.
            let declic = texteDeclic(cibles: cibles, rang: rang)
            if let declic {
                ajouter("declic", jour: jour, Moment.declic, declic, ecran: "recommendations")
            }

            // 8 h 30 — le brief. Pas aujourd'hui (l'app est ouverte), et les
            // jours allégés il cède sa place au déclic quand il y en a un.
            if jour >= 1, plein || declic == nil {
                let brief = texteBrief(contexte: contexte, veille: veille, jour: jour, rang: rang)
                ajouter("brief", jour: jour, Moment.brief, brief.texte, ecran: brief.ecran)
            }

            // 12 h 15 — midi.
            if !creneauxNotes.contains(.lunch) {
                ajouter("midi", jour: jour, Moment.midi,
                        texteMidi(cibles: cibles, veille: veille, rang: rang), ecran: "meal_scan")
            }

            // 16 h 15 — l'encas.
            if plein, !creneauxNotes.contains(.snack), let jourMeme,
               let encas = texteEncas(cibles: cibles, jourMeme: jourMeme, rang: rang) {
                ajouter("encas", jour: jour, Moment.encas, encas, ecran: "meal_scan")
            }

            // Dimanche 18 h — la semaine en chiffres.
            if contexte.journalConnu, contexte.repasSemaine >= repasMinimumSemaine,
               calendar.component(.weekday, from: dateDuJour) == 1 {
                ajouter("semaine", jour: jour, Moment.semaine,
                        FormulationsRappel.semaine(
                            repas: contexte.repasSemaine,
                            jours: contexte.joursNotesSemaine,
                            effort: contexte.effort
                        ),
                        ecran: "checkin")
            }

            // 19 h 15 — le soir.
            if !creneauxNotes.contains(.dinner) {
                ajouter("soir", jour: jour, Moment.soir,
                        texteSoir(cibles: cibles, jourMeme: jourMeme, rang: rang), ecran: "meal_scan")
            }

            // 21 h 15 — le dernier appel : la journée est commencée, il lui
            // manque son dîner.
            if plein, let jourMeme, jourMeme.repas >= 1, !creneauxNotes.contains(.dinner) {
                ajouter("appel", jour: jour, Moment.dernierAppel,
                        FormulationsRappel.dernierAppel(
                            repas: jourMeme.repas,
                            couverts: jourMeme.chiffrable ? jourMeme.besoinsCouverts : nil
                        ),
                        ecran: "meal_scan")
            }
        }

        // Retour au 7e jour : ne sonne que si l'app est restée fermée d'ici là.
        if let date = instant(horizonJours, Moment.midi) {
            let texte = FormulationsRappel.retour(cible: cibles.first)
            rappels.append(RappelPlanifie(
                id: "\(prefixe)retour",
                date: date,
                titre: texte.titre,
                corps: texte.corps,
                ecran: "meal_scan"
            ))
        }

        // La prise de sang passe 6 mois : dès cet instant elle compte moitié
        // moins (`PriseDeSangApports.fraicheur`). Un seul rappel, posé des mois
        // à l'avance s'il le faut — au premier 10 h 30 qui suit le cap, pour
        // que la phrase soit vraie quand elle sonne.
        if let prelevement = contexte.priseDeSang,
           let cap = PriseDeSangApports.finDuPleinEffet(prelevement: prelevement, calendar: calendar),
           var date = calendar.date(
               bySettingHour: Moment.priseDeSang.heure, minute: Moment.priseDeSang.minute, second: 0,
               of: calendar.startOfDay(for: cap)
           ) {
            if date < cap, let lendemain = calendar.date(byAdding: .day, value: 1, to: date) { date = lendemain }
            if date > maintenant {
                let texte = FormulationsRappel.priseDeSangSixMois()
                rappels.append(RappelPlanifie(
                    id: "\(prefixe)sang",
                    date: date,
                    titre: texte.titre,
                    corps: texte.corps,
                    ecran: "meal_scan"
                ))
            }
        }

        return rappels.sorted { $0.date < $1.date }
    }

    // MARK: - Le texte de chaque moment

    /// L'apport à travailler le plus bas d'un jour (à égalité : l'ordre du
    /// bilan), avec sa part couverte.
    static func plusBasse(
        _ cibles: [CibleNutritionnelle],
        dans couverture: [String: Int]
    ) -> (cible: CibleNutritionnelle, pourcent: Int)? {
        var trouvee: (cible: CibleNutritionnelle, pourcent: Int)?
        for cible in cibles {
            let pourcent = couverture[cible.id] ?? 0
            if let actuelle = trouvee, actuelle.pourcent <= pourcent { continue }
            trouvee = (cible, pourcent)
        }
        return trouvee
    }

    private static func texteBrief(
        contexte: ContexteRappels,
        veille: JourNote?,
        jour: Int,
        rang: Int
    ) -> (texte: (titre: String, corps: String), ecran: String) {
        guard let veille else {
            return (FormulationsRappel.briefDuMatin(jour: rang), "dashboard")
        }
        let texte = FormulationsRappel.brief(
            repasHier: veille.repas,
            couvertsHier: veille.chiffrable ? veille.besoinsCouverts : nil,
            plusBas: veille.chiffrable ? plusBasse(contexte.cibles, dans: veille.couverture) : nil,
            // Demain matin, la série prolongée aujourd'hui est toujours vraie.
            // Plus loin, on ne sait pas : on ne la cite pas.
            serie: jour == 1 ? contexte.serieDuJour : 0,
            jour: rang
        )
        // Une veille chiffrée s'ouvre sur le brief ; une veille vide, sur
        // l'ajout d'un repas — c'est ce que la notification demande.
        return (texte, veille.chiffrable ? "dashboard" : "meal_scan")
    }

    /// Un jour sur deux, en faisant tourner les freins déclarés : le premier
    /// de chaque apport d'abord, les seconds ensuite. `nil` les autres jours,
    /// ou quand le questionnaire n'a nommé aucun frein alimentaire.
    private static func texteDeclic(
        cibles: [CibleNutritionnelle],
        rang: Int
    ) -> (titre: String, corps: String)? {
        guard rang % 2 == 0 else { return nil }
        var paires: [(cible: CibleNutritionnelle, frein: FreinCible)] = []
        for position in 0..<BriefDuJourBuilder.freinsParCible {
            for cible in cibles {
                guard let freins = cible.freins, freins.indices.contains(position) else { continue }
                paires.append((cible, freins[position]))
            }
        }
        guard !paires.isEmpty else { return nil }
        let tour = rang / 2
        let paire = paires[tour % paires.count]
        // La variante change à chaque fois que le MÊME frein revient.
        return FormulationsRappel.declic(cible: paire.cible, frein: paire.frein, jour: tour / paires.count)
    }

    private static func texteMidi(
        cibles: [CibleNutritionnelle],
        veille: JourNote?,
        rang: Int
    ) -> (titre: String, corps: String) {
        guard !cibles.isEmpty else { return FormulationsRappel.midiSansBilan(jour: rang) }
        if let veille, veille.chiffrable, let bas = plusBasse(cibles, dans: veille.couverture) {
            return FormulationsRappel.midi(cible: bas.cible, jour: rang, hier: bas.pourcent)
        }
        return FormulationsRappel.midi(cible: cibles[rang % cibles.count], jour: rang, hier: nil)
    }

    /// `nil` = pas d'encas à proposer : pas de bilan, des repas notés sans
    /// apports chiffrés, ou tout ce qui est à travailler est déjà à 100 %.
    private static func texteEncas(
        cibles: [CibleNutritionnelle],
        jourMeme: JourNote,
        rang: Int
    ) -> (titre: String, corps: String)? {
        guard !cibles.isEmpty else { return nil }
        guard jourMeme.repas >= 1 else {
            return FormulationsRappel.encas(cible: cibles[(rang + 2) % cibles.count], jour: rang, aujourdhui: nil)
        }
        guard !jourMeme.couverture.isEmpty else { return nil }
        // Du plus bas au plus haut aujourd'hui. Le soir prend le plus bas :
        // l'encas prend le suivant, pour ne pas dire deux fois le même chiffre.
        var classees: [(rangBilan: Int, cible: CibleNutritionnelle, pourcent: Int)] = []
        for (rangBilan, cible) in cibles.enumerated() {
            let pourcent = jourMeme.couverture[cible.id] ?? 0
            if pourcent < 100 { classees.append((rangBilan, cible, pourcent)) }
        }
        classees.sort { a, b in
            if a.pourcent != b.pourcent { return a.pourcent < b.pourcent }
            return a.rangBilan < b.rangBilan
        }
        guard let choisie = classees.count >= 2 ? classees[1] : classees.first else { return nil }
        return FormulationsRappel.encas(
            cible: choisie.cible,
            jour: rang,
            aujourdhui: (pourcent: choisie.pourcent, repas: jourMeme.repas)
        )
    }

    private static func texteSoir(
        cibles: [CibleNutritionnelle],
        jourMeme: JourNote?,
        rang: Int
    ) -> (titre: String, corps: String) {
        guard !cibles.isEmpty else { return FormulationsRappel.soirSansBilan(jour: rang) }
        if let jourMeme, jourMeme.repas >= 1, !jourMeme.couverture.isEmpty,
           let bas = plusBasse(cibles, dans: jourMeme.couverture) {
            return FormulationsRappel.soir(cible: bas.cible, jour: rang, aujourdhui: bas.pourcent)
        }
        // Décalé d'un cran sur le midi : on alterne les apports au fil des jours.
        return FormulationsRappel.soir(cible: cibles[(rang + 1) % cibles.count], jour: rang)
    }

    // MARK: - Mémoire des cibles

    /// Les cibles du dernier bilan chargé : l'onglet Progrès et le retour au
    /// premier plan replanifient sans avoir le bilan en main. Clé préfixée
    /// `healthmap_` → effacée au changement de compte.
    static let cleCibles = "healthmap_rappels_cibles"

    static func memoriser(_ cibles: [CibleNutritionnelle], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cibles) else { return }
        defaults.set(data, forKey: cleCibles)
    }

    static func ciblesMemorisees(defaults: UserDefaults = .standard) -> [CibleNutritionnelle] {
        guard let data = defaults.data(forKey: cleCibles),
              let cibles = try? JSONDecoder().decode([CibleNutritionnelle].self, from: data) else { return [] }
        return cibles
    }

    // MARK: - Mémoire de la prise de sang

    /// Le prélèvement de la dernière prise de sang, pour replanifier le rappel
    /// des 6 mois sans le bilan en main. Clé préfixée `healthmap_` → effacée
    /// au changement de compte.
    static let clePriseDeSang = "healthmap_rappels_prise_de_sang"

    static func memoriserPriseDeSang(_ prelevement: Date?, defaults: UserDefaults = .standard) {
        if let prelevement {
            defaults.set(prelevement.timeIntervalSince1970, forKey: clePriseDeSang)
        } else {
            defaults.removeObject(forKey: clePriseDeSang)
        }
    }

    static func priseDeSangMemorisee(defaults: UserDefaults = .standard) -> Date? {
        guard let secondes = defaults.object(forKey: clePriseDeSang) as? Double else { return nil }
        return Date(timeIntervalSince1970: secondes)
    }

    // MARK: - Interrupteur (Réglages → Notifications)

    /// Ce que la personne VEUT, distinct de ce qu'iOS autorise. Allumé par
    /// défaut : seul un geste dans les Réglages l'éteint. Clé préfixée
    /// `healthmap_` → effacée au changement de compte.
    static let cleActifs = "healthmap_rappels_actifs"

    static var actifs: Bool {
        get { UserDefaults.standard.object(forKey: cleActifs) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: cleActifs) }
    }

    // MARK: - Application (UNUserNotificationCenter)

    /// Recalcule et remplace TOUS les rappels. Silencieux si les notifications
    /// ne sont pas autorisées : on ne masque pas un refus derrière des requêtes
    /// qu'iOS jetterait. Idempotent — appelable à chaque ouverture.
    /// - Parameter cibles: cibles fraîches du bilan ; `nil` = les dernières
    ///   mémorisées.
    @MainActor
    static func replanifier(cibles: [CibleNutritionnelle]? = nil) async {
        if let cibles { memoriser(cibles) }

        // Rappels coupés dans les Réglages, ou ancien mode Zen encore actif
        // (il promettait lui aussi le silence) : rien ne part.
        if !actifs || GamificationService.shared.isZenMode {
            toutAnnuler()
            return
        }

        let center = UNUserNotificationCenter.current()
        let reglages = await center.notificationSettings()
        // Le brief décide d'inviter ou non aux notifications SANS attendre iOS
        // (il doit s'afficher à l'instant où l'app s'ouvre) : on lui laisse ici
        // le dernier état connu.
        BriefDuJourStore.memoriserStatutNotifications(reglages.authorizationStatus.rawValue)
        guard reglages.authorizationStatus == .authorized
                || reglages.authorizationStatus == .provisional else {
            AppLogger.push.notice("Rappels non planifiés : notifications non autorisées")
            return
        }

        let calendar = Calendar.current
        let maintenant = Date()
        let aujourdhui = calendar.startOfDay(for: maintenant)
        let ciblesDuBilan = cibles ?? ciblesMemorisees()

        // Deux semaines de repas (la même fenêtre que le brief : même effort
        // de la semaine, mêmes chiffres) et les jours à venir, pour les repas
        // préparés d'avance. En cas d'échec (hors-ligne), on planifie quand
        // même — sans rien affirmer sur le journal.
        let debutSemaine = WeekScoreEngine.currentWeekInterval(containing: maintenant).start
        let depuis = min(
            calendar.date(byAdding: .day, value: -7, to: debutSemaine) ?? debutSemaine,
            calendar.date(byAdding: .day, value: -13, to: aujourdhui) ?? debutSemaine
        )
        let jusqua = calendar.date(byAdding: .day, value: horizonJours + 1, to: aujourdhui) ?? maintenant
        var contexte = ContexteRappels(cibles: ciblesDuBilan)
        if let userId = AuthService.shared.cachedCurrentUserIdString,
           let repas = try? await MealJournalService.shared.loadRange(userId: userId, from: depuis, to: jusqua) {
            contexte = ContexteRappels.construire(
                cibles: ciblesDuBilan, repas: repas, maintenant: maintenant, calendar: calendar
            )
        }
        let gamification = GamificationService.shared
        if let dernier = gamification.lastCheckinDate, calendar.isDate(dernier, inSameDayAs: maintenant) {
            contexte.serieDuJour = gamification.currentStreak
        }
        contexte.priseDeSang = priseDeSangMemorisee()

        let rappels = planifier(contexte: contexte, maintenant: maintenant, calendar: calendar)

        await retirerTout(center: center)
        for rappel in rappels {
            let contenu = UNMutableNotificationContent()
            contenu.title = rappel.titre
            contenu.body = rappel.corps
            contenu.sound = .default
            contenu.userInfo = ["screen": rappel.ecran, "rappel": rappel.type]
            let composantes = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: rappel.date)
            let declencheur = UNCalendarNotificationTrigger(dateMatching: composantes, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: rappel.id, content: contenu, trigger: declencheur))
            } catch {
                AppLogger.push.report(error, context: "replanifier rappels")
            }
        }
        AppLogger.push.info("Rappels personnalisés planifiés : \(rappels.count, privacy: .public)")
    }

    /// Retire tous les rappels Kiwio (actuels et anciens). Sans attente : sûr
    /// depuis la déconnexion ou le mode Zen.
    static func toutAnnuler() {
        let prefixe = Self.prefixe
        let anciens = Self.anciensIdentifiants
        UNUserNotificationCenter.current().getPendingNotificationRequests { requetes in
            let ids = requetes.map(\.identifier).filter { $0.hasPrefix(prefixe) }
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ids + anciens)
        }
    }

    private static func retirerTout(center: UNUserNotificationCenter) async {
        let requetes = await center.pendingNotificationRequests()
        let ids = requetes.map(\.identifier).filter { $0.hasPrefix(prefixe) }
        center.removePendingNotificationRequests(withIdentifiers: ids + anciensIdentifiants)
    }
}
