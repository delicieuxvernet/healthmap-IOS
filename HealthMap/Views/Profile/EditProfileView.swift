import SwiftUI

// MARK: - Edit Profile View (editable — Vague E Phase 4.3)
/// Version 100% editable : chaque fieldRow ouvre un EditFieldSheet contextuel,
/// les changements sont appliqués au `dashboardVM.profile` en direct,
/// et sync Supabase via `DatabaseService.saveProfile` au tap sur "Sauvegarder".
///
/// Pattern Apple Health : edit field-by-field en sheet, pas un gros formulaire.
/// Respecte CLAUDE.md §2.4 (audit-a/b/c), §2.5 (non-modification hors scope).
struct EditProfileView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Snapshot du profile au mount — référence pour détecter les unsaved changes
    /// et restaurer en cas de discard.
    @State private var originalProfile: UserProfile?

    /// Field en cours d'édition — nil par défaut, set au tap sur fieldRow.
    @State private var editingField: EditableField?

    @State private var isSaving = false
    @State private var showSaved = false
    @State private var saveError: String?
    @State private var expandedSection: EditSection?

    // MARK: - Liaison Apple Santé (HealthKit, lecture seule)
    /// L'utilisateur a-t-il lié Apple Santé ? HealthKit ne révèle pas le statut
    /// d'autorisation de lecture, on porte donc l'intention nous-mêmes.
    @AppStorage("healthkit_linked") private var healthLinked = false
    @State private var healthSyncing = false
    @State private var healthSnapshot: HealthKitService.HealthSnapshot?
    @State private var showHealthManage = false
    /// Message contextuel sous la carte (ex. « aucune donnée trouvée »).
    @State private var healthNote: String?

    enum EditSection: String, CaseIterable, Identifiable {
        case profil = "Profil"
        case modeDeVie = "Mode de vie"
        case sante = "Santé"
        case nutrition = "Nutrition"
        case symptomes = "Symptômes"
        case medical = "Médical"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .profil: return "person.fill"
            case .modeDeVie: return "sun.max.fill"
            case .sante: return "heart.fill"
            case .nutrition: return "leaf.fill"
            case .symptomes: return "stethoscope"
            case .medical: return "cross.case.fill"
            }
        }

        /// Blue nuances only, per the "tout bleu" brand rule.
        var color: Color {
            switch self {
            case .profil: return .healthMapBlue
            case .modeDeVie: return Color(hex: "5AC8FA")
            case .sante: return Color(hex: "0056CC")
            case .nutrition: return Color(hex: "64D2FF")
            case .symptomes: return Color(hex: "5856D6")
            case .medical: return Color(hex: "4A90E2")
            }
        }
    }

    private var profile: UserProfile { dashboardVM.profile }

    /// Changements non sauvegardés si le snapshot diffère du profile actuel.
    private var hasUnsavedChanges: Bool {
        guard let original = originalProfile else { return false }
        return original != dashboardVM.profile
    }

    var body: some View {
        ZStack {
            Color.healthMapBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.spacingSM) {
                    // Toujours visible (même sur iPad où HealthKit est indisponible) pour
                    // identifier clairement la fonctionnalité Apple Santé — App Review 2.5.1.
                    appleHealthCard
                    ForEach(EditSection.allCases) { section in
                        sectionCard(section)
                    }
                }
                .padding(.vertical, Theme.spacingMD)
                .padding(.bottom, hasUnsavedChanges ? 100 : 20)
            }
            .task {
                // Si déjà lié, on rafraîchit silencieusement les valeurs à l'ouverture.
                if healthLinked, healthSnapshot == nil {
                    healthSnapshot = await HealthKitService.shared.importSnapshot()
                }
            }

            // Sticky save button — visible uniquement si modifications
            VStack {
                Spacer()
                if hasUnsavedChanges {
                    saveButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85), value: hasUnsavedChanges)
        }
        .navigationTitle("Modifier mon profil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if originalProfile == nil {
                originalProfile = dashboardVM.profile
            }
        }
        .sheet(item: $editingField) { field in
            EditFieldSheet(
                field: field,
                currentValue: currentValueForField(field.id),
                onSave: { newValue in
                    applyFieldChange(fieldId: field.id, newValue: newValue)
                }
            )
        }
        .alert(
            "Erreur de sauvegarde",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Carte Apple Santé (liaison HealthKit)
    private var appleHealthCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.spacingSM) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "FF2D55"))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: "FF2D55").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Santé")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)
                    if healthLinked {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                            Text("Connecté · synchronisé")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.kiwiGreen)
                    } else {
                        Text("Importe ton activité, ton poids et ton sommeil.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.healthMapSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                if healthLinked {
                    Button("Gérer") { showHealthManage = true }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.healthMapSecondary)
                        .buttonStyle(.healthMapPressed)
                }
            }
            .padding(Theme.spacingMD)

            if healthLinked {
                Divider().padding(.horizontal, Theme.spacingMD)
                VStack(spacing: 0) {
                    healthRow(icon: "figure.walk", label: "Activité", value: stepsDisplay(healthSnapshot))
                    Divider().padding(.horizontal, Theme.spacingMD)
                    healthRow(icon: "scalemass", label: "Poids", value: weightDisplay(healthSnapshot))
                    Divider().padding(.horizontal, Theme.spacingMD)
                    healthRow(icon: "moon.fill", label: "Sommeil", value: sleepDisplay(healthSnapshot))
                }
            } else if HealthKitService.shared.isAvailable {
                Button { connectHealth() } label: {
                    HStack(spacing: 8) {
                        if healthSyncing {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "link").font(.system(size: 15))
                        }
                        Text(healthSyncing ? "Connexion..." : "Connecter Apple Santé")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.kiwiGreen))
                }
                .buttonStyle(.healthMapPressed)
                .disabled(healthSyncing)
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, Theme.spacingMD)
            } else {
                // HealthKit indisponible (ex. iPad) : l'encart reste affiché avec sa
                // description, on indique juste que la connexion se fait sur iPhone.
                HStack(spacing: 8) {
                    Image(systemName: "iphone").font(.system(size: 14))
                    Text("Connexion disponible sur iPhone")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.healthMapBackground))
                .padding(.horizontal, Theme.spacingMD)
                .padding(.bottom, Theme.spacingMD)
            }

            if let note = healthNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.healthMapMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.spacingMD)
                    .padding(.bottom, Theme.spacingMD)
            }
        }
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, Theme.spacingLG)
        .confirmationDialog("Apple Santé", isPresented: $showHealthManage, titleVisibility: .visible) {
            Button("Délier Apple Santé", role: .destructive) { disconnectHealth() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Pour gérer les données partagées, ouvre Réglages > Santé > Données et accès.")
        }
    }

    private func healthRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.healthMapBlue)
                .frame(width: 28, height: 28)
                .background(Color.healthMapBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.healthMapText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.healthMapText)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.spacingMD)
        .padding(.vertical, 12)
    }

    // MARK: - Liaison Apple Santé — actions

    private func connectHealth() {
        guard !healthSyncing else { return }
        healthSyncing = true
        healthNote = nil
        HapticService.shared.primary()
        Task {
            let granted = await HealthKitService.shared.requestAuthorization()
            guard granted else {
                healthSyncing = false
                healthNote = "Autorisation refusée. Tu peux l'activer dans Réglages > Santé."
                HapticService.shared.error()
                return
            }
            let snap = await HealthKitService.shared.importSnapshot()
            healthSnapshot = snap
            healthLinked = true
            applyHealthSnapshot(snap)
            healthSyncing = false
            if snap.isEmpty {
                healthNote = "Connecté, mais aucune donnée partagée pour l'instant."
                HapticService.shared.success()
            } else {
                HapticService.shared.success()
                await save() // persiste le profil + recalcule les scores
            }
        }
    }

    private func disconnectHealth() {
        healthLinked = false
        healthSnapshot = nil
        healthNote = nil
        HapticService.shared.selection()
    }

    /// Écrit les valeurs importées dans les champs profil correspondants
    /// (uniquement celles réellement présentes dans l'instantané).
    private func applyHealthSnapshot(_ snap: HealthKitService.HealthSnapshot) {
        var p = dashboardVM.profile
        if let kg = snap.weightKg { p.weight = HealthKitService.weightString(forKilograms: kg) }
        if let steps = snap.steps { p.strengthTraining = HealthKitService.activityLevel(forSteps: steps) }
        if let hours = snap.sleepHours { p.sleepHours = HealthKitService.sleepBucket(forHours: hours) }
        dashboardVM.profile = p
    }

    private func stepsDisplay(_ snap: HealthKitService.HealthSnapshot?) -> String {
        guard let steps = snap?.steps else { return "—" }
        return "\(steps) pas"
    }

    private func weightDisplay(_ snap: HealthKitService.HealthSnapshot?) -> String {
        guard let kg = snap?.weightKg else { return "—" }
        return HealthKitService.weightString(forKilograms: kg) + " kg"
    }

    private func sleepDisplay(_ snap: HealthKitService.HealthSnapshot?) -> String {
        guard let hours = snap?.sleepHours else { return "—" }
        let whole = Int(hours)
        let mins = Int((hours - Double(whole)) * 60)
        return "\(whole) h \(String(format: "%02d", mins))"
    }

    // MARK: - Section Card
    private func sectionCard(_ section: EditSection) -> some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(reduceMotion ? .none : .spring(response: 0.3)) {
                    expandedSection = expandedSection == section ? nil : section
                }
            } label: {
                HStack(spacing: Theme.spacingSM) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(section.color)
                        .frame(width: 28, height: 28)
                        .background(section.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(section.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.healthMapText)

                    Spacer()

                    Image(systemName: expandedSection == section ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.healthMapMuted)
                }
                .padding(Theme.spacingMD)
                .contentShape(Rectangle())
            }
            .buttonStyle(.healthMapPressed)

            // Content
            if expandedSection == section {
                Divider()
                    .padding(.horizontal, Theme.spacingMD)

                VStack(spacing: 0) {
                    let fields = fieldsForSection(section)
                    ForEach(Array(fields.enumerated()), id: \.element.id) { idx, field in
                        fieldRow(field)
                        if idx < fields.count - 1 {
                            Divider()
                                .padding(.horizontal, Theme.spacingMD)
                        }
                    }
                }
            }
        }
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Field Row (tap-able, ouvre EditFieldSheet)
    private func fieldRow(_ field: EditableField) -> some View {
        Button {
            HapticService.shared.selection()
            editingField = field
        } label: {
            HStack {
                Text(field.emoji)
                    .font(.system(size: 16))
                    .accessibilityHidden(true)

                Text(field.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.healthMapText)

                Spacer()

                Text(displayValue(for: field.id))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.healthMapSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.healthMapMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.healthMapPressed)
        .accessibilityLabel("\(field.label), valeur actuelle : \(displayValue(for: field.id))")
        .accessibilityHint("Appuyer pour modifier")
    }

    // MARK: - Save Button
    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else if showSaved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Sauvegardé")
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                    Text("Sauvegarder les modifications")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(showSaved ? Color(hex: "0056CC") : Color.healthMapBlue)
            )
        }
        .buttonStyle(.healthMapPressed)
        .disabled(isSaving || showSaved)
        .padding(.horizontal, Theme.spacingLG)
        .padding(.bottom, Theme.spacingMD)
        .background(
            LinearGradient(
                colors: [Color.healthMapBackground.opacity(0), Color.healthMapBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .offset(y: -60),
            alignment: .top
        )
    }

    // MARK: - Save to Supabase
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        HapticService.shared.primary()

        guard SupabaseService.shared.safeClient != nil else {
            isSaving = false
            saveError = "Connexion indisponible. Réessaie dans un instant."
            HapticService.shared.error()
            return
        }
        guard let session = await AuthService.shared.currentSession else {
            isSaving = false
            saveError = "Ta connexion a expiré. Reconnecte-toi."
            HapticService.shared.error()
            return
        }

        let userId = session.user.id.uuidString
        let email = session.user.email ?? ""

        do {
            try await NetworkService.shared.withRetry {
                try await DatabaseService.shared.saveProfile(
                    userId: userId,
                    email: email,
                    firstName: dashboardVM.profile.firstName,
                    questionnaireData: dashboardVM.profile
                )
            }

            // Recompute local scores avec le nouveau profile
            dashboardVM.computeLocalScores()

            // Refresh du snapshot pour éviter unsavedChanges fantôme
            originalProfile = dashboardVM.profile

            HapticService.shared.success()
            withAnimation(reduceMotion ? .none : .spring(response: 0.4)) {
                showSaved = true
            }
            isSaving = false

            // Toast positif via ToastService (déjà branché en Vague B)
            ToastService.shared.currentToast = "Profil mis à jour. Tes scores ont été recalculés"
            ToastService.shared.isShowing = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                ToastService.shared.isShowing = false
            }

            // Auto-hide "Sauvegardé" confirmation
            Task {
                try? await Task.sleep(for: .seconds(2))
                withAnimation(reduceMotion ? .none : .spring(response: 0.4)) {
                    showSaved = false
                }
            }
        } catch {
            isSaving = false
            saveError = "Impossible de sauvegarder. Vérifie ta connexion et réessaie."
            HapticService.shared.error()
            AppLogger.database.error("EditProfile save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Apply Field Change
    private func applyFieldChange(fieldId: String, newValue: Any) {
        var p = dashboardVM.profile

        switch fieldId {
        case "firstName": p.firstName = (newValue as? String) ?? ""
        case "age": p.age = (newValue as? String) ?? ""
        case "gender":
            if let s = newValue as? String {
                p.gender = (s == "femme") ? .femme : .homme
            }
        case "height": p.height = (newValue as? String) ?? ""
        case "weight": p.weight = (newValue as? String) ?? ""
        case "weightTrend": p.weightTrend = (newValue as? String) ?? ""
        case "indoorWork": p.indoorWork = (newValue as? String) ?? ""
        case "sunExposure": p.sunExposure = (newValue as? String) ?? ""
        case "skinType": p.skinType = (newValue as? String) ?? ""
        case "strengthTraining": p.strengthTraining = (newValue as? String) ?? ""
        case "stressLevel": p.stressLevel = (newValue as? String) ?? ""
        case "sleepHours": p.sleepHours = (newValue as? String) ?? ""
        case "wakeFeeling": p.wakeFeeling = (newValue as? String) ?? ""
        case "caffeineIntake": p.caffeineIntake = (newValue as? String) ?? ""
        case "waterIntake": p.waterIntake = (newValue as? String) ?? ""
        case "alcohol": p.alcohol = (newValue as? String) ?? ""
        case "dietType": p.dietType = (newValue as? String) ?? ""
        case "vegetableServings": p.vegetableServings = (newValue as? String) ?? ""
        case "fruitServings": p.fruitServings = (newValue as? String) ?? ""
        case "fattyFish": p.fattyFish = (newValue as? String) ?? ""
        case "meatPoultry": p.meatPoultry = (newValue as? String) ?? ""
        case "dairyServings": p.dairyServings = (newValue as? String) ?? ""
        case "nutsPerWeek": p.nutsPerWeek = (newValue as? String) ?? ""
        case "symptoms": p.symptoms = (newValue as? [String]) ?? []
        case "medications": p.medications = (newValue as? [String]) ?? []
        case "digestiveConditions": p.digestiveConditions = (newValue as? [String]) ?? []
        default: return
        }

        dashboardVM.profile = p
    }

    // MARK: - Current value extractor
    private func currentValueForField(_ id: String) -> Any {
        let p = profile
        switch id {
        case "firstName": return p.firstName
        case "age": return p.age
        case "gender": return p.gender == .femme ? "femme" : "homme"
        case "height": return p.height
        case "weight": return p.weight
        case "weightTrend": return p.weightTrend
        case "indoorWork": return p.indoorWork
        case "sunExposure": return p.sunExposure
        case "skinType": return p.skinType
        case "strengthTraining": return p.strengthTraining
        case "stressLevel": return p.stressLevel
        case "sleepHours": return p.sleepHours
        case "wakeFeeling": return p.wakeFeeling
        case "caffeineIntake": return p.caffeineIntake
        case "waterIntake": return p.waterIntake
        case "alcohol": return p.alcohol
        case "dietType": return p.dietType
        case "vegetableServings": return p.vegetableServings
        case "fruitServings": return p.fruitServings
        case "fattyFish": return p.fattyFish
        case "meatPoultry": return p.meatPoultry
        case "dairyServings": return p.dairyServings
        case "nutsPerWeek": return p.nutsPerWeek
        case "symptoms": return p.symptoms
        case "medications": return p.medications
        case "digestiveConditions": return p.digestiveConditions
        default: return ""
        }
    }

    // MARK: - Field Definitions
    /// Alignée sur le questionnaire Home.jsx web (CLAUDE.md §6).
    /// Les options d'un champ viennent du questionnaire, jamais d'une liste
    /// recopiée ici.
    ///
    /// Historique : ces listes étaient écrites en dur et avaient divergé.
    /// L'écran écrivait par exemple `unintentional_loss` là où le
    /// questionnaire et `RedFlagDetector` attendent `losing_unintentionally`
    /// — modifier sa tendance de poids depuis le profil désactivait donc en
    /// silence l'alerte de perte de poids involontaire. Même dérive sur
    /// `stressLevel`, `wakeFeeling`, `waterIntake`, `alcohol`, `dietType`,
    /// `skinType`, `symptoms`, `medications` et `digestiveConditions` : les
    /// moteurs ne reconnaissaient pas la valeur et retombaient sur 0.
    /// Corrigé le 2 août 2026, verrouillé par `EditProfileParityTests`.
    private func options(_ questionId: String) -> [(String, String)] {
        QuestionnaireSection.optionPairs(id: questionId)
    }

    /// Options : mirror exact des select/picker du questionnaire pour
    /// que les scores health.js calculent identiquement.
    private func fieldsForSection(_ section: EditSection) -> [EditableField] {
        switch section {
        case .profil:
            return [
                EditableField(id: "firstName", label: "Prénom", emoji: "👤", kind: .text(placeholder: "Ton prénom")),
                EditableField(id: "age", label: "Âge", emoji: "🎂", kind: .number(unit: "ans", min: 10, max: 110)),
                EditableField(id: "gender", label: "Genre", emoji: "⚧", kind: .pickerSingle(options: options("gender"))),
                EditableField(id: "height", label: "Taille", emoji: "📏", kind: .number(unit: "cm", min: 120, max: 230)),
                EditableField(id: "weight", label: "Poids", emoji: "⚖️", kind: .number(unit: "kg", min: 30, max: 250)),
                EditableField(id: "weightTrend", label: "Tendance poids", emoji: "📈", kind: .pickerSingle(options: options("weightTrend"))),
            ]
        case .modeDeVie:
            return [
                EditableField(id: "indoorWork", label: "Travail à l'intérieur", emoji: "🏢", kind: .pickerSingle(options: options("indoorWork"))),
                EditableField(id: "sunExposure", label: "Exposition soleil", emoji: "☀️", kind: .pickerSingle(options: options("sunExposure"))),
                EditableField(id: "skinType", label: "Type de peau", emoji: "🖐️", kind: .pickerSingle(options: options("skinType"))),
                EditableField(id: "strengthTraining", label: "Activité physique", emoji: "🏋️", kind: .pickerSingle(options: options("strengthTraining"))),
            ]
        case .sante:
            return [
                EditableField(id: "stressLevel", label: "Niveau de stress", emoji: "🧘", kind: .pickerSingle(options: options("stressLevel"))),
                // Le sommeil est un choix, pas un nombre libre : les moteurs
                // comparent à des paliers ("4", "5.5", "6.5"…). Saisir « 7 »
                // ne correspondait à aucun palier et annulait le modificateur.
                EditableField(id: "sleepHours", label: "Heures de sommeil", emoji: "😴", kind: .pickerSingle(options: options("sleepHours"))),
                EditableField(id: "wakeFeeling", label: "Réveil", emoji: "🌅", kind: .pickerSingle(options: options("wakeFeeling"))),
                EditableField(id: "caffeineIntake", label: "Caféine", emoji: "☕", kind: .pickerSingle(options: options("caffeineIntake"))),
                EditableField(id: "waterIntake", label: "Eau", emoji: "💧", kind: .pickerSingle(options: options("waterIntake"))),
                EditableField(id: "alcohol", label: "Alcool", emoji: "🍷", kind: .pickerSingle(options: options("alcohol"))),
            ]
        case .nutrition:
            return [
                EditableField(id: "dietType", label: "Régime", emoji: "🍽️", kind: .pickerSingle(options: options("dietType"))),
                EditableField(id: "vegetableServings", label: "Légumes/semaine", emoji: "🥦", kind: .number(unit: "portions", min: 0, max: 30)),
                EditableField(id: "fruitServings", label: "Fruits/semaine", emoji: "🍎", kind: .number(unit: "portions", min: 0, max: 30)),
                EditableField(id: "fattyFish", label: "Poisson gras/semaine", emoji: "🐟", kind: .number(unit: "portions", min: 0, max: 10)),
                EditableField(id: "meatPoultry", label: "Viande/semaine", emoji: "🥩", kind: .number(unit: "portions", min: 0, max: 21)),
                EditableField(id: "dairyServings", label: "Produits laitiers", emoji: "🥛", kind: .number(unit: "portions/j", min: 0, max: 10)),
                EditableField(id: "nutsPerWeek", label: "Noix/semaine", emoji: "🥜", kind: .number(unit: "portions", min: 0, max: 14)),
            ]
        case .symptomes:
            return [
                EditableField(id: "symptoms", label: "Symptômes ressentis", emoji: "🩺", kind: .pickerMulti(options: options("symptoms"))),
            ]
        case .medical:
            return [
                EditableField(id: "medications", label: "Médicaments", emoji: "💊", kind: .pickerMulti(options: options("medications"))),
                EditableField(id: "digestiveConditions", label: "Conditions digestives", emoji: "🫁", kind: .pickerMulti(options: options("digestiveConditions"))),
            ]
        }
    }

    // MARK: - Display value
    private func displayValue(for id: String) -> String {
        let p = profile
        switch id {
        case "firstName": return p.firstName.isEmpty ? "-" : p.firstName
        case "age": return p.age.isEmpty ? "-" : "\(p.age) ans"
        case "gender": return p.gender == .homme ? "Homme" : "Femme"
        case "height": return p.height.isEmpty ? "-" : "\(p.height) cm"
        case "weight": return p.weight.isEmpty ? "-" : "\(p.weight) kg"
        case "weightTrend": return friendlyLabel("weightTrend", p.weightTrend)
        case "indoorWork": return p.indoorWork == "yes" ? "Oui" : (p.indoorWork == "no" ? "Non" : "-")
        case "sunExposure": return friendlyLabel("sunExposure", p.sunExposure)
        case "skinType": return friendlyLabel("skinType", p.skinType)
        case "strengthTraining": return friendlyLabel("strengthTraining", p.strengthTraining)
        case "stressLevel": return friendlyLabel("stressLevel", p.stressLevel)
        case "sleepHours": return friendlyLabel("sleepHours", p.sleepHours)
        case "wakeFeeling": return friendlyLabel("wakeFeeling", p.wakeFeeling)
        case "caffeineIntake": return friendlyLabel("caffeineIntake", p.caffeineIntake)
        case "waterIntake": return friendlyLabel("waterIntake", p.waterIntake)
        case "alcohol": return friendlyLabel("alcohol", p.alcohol)
        case "dietType": return friendlyLabel("dietType", p.dietType)
        case "vegetableServings": return p.vegetableServings.isEmpty ? "-" : p.vegetableServings
        case "fruitServings": return p.fruitServings.isEmpty ? "-" : p.fruitServings
        case "fattyFish": return p.fattyFish.isEmpty ? "-" : p.fattyFish
        case "meatPoultry": return p.meatPoultry.isEmpty ? "-" : p.meatPoultry
        case "dairyServings": return p.dairyServings.isEmpty ? "-" : p.dairyServings
        case "nutsPerWeek": return p.nutsPerWeek.isEmpty ? "-" : p.nutsPerWeek
        case "symptoms": return p.symptoms.isEmpty ? "Aucun" : "\(p.symptoms.count) symptôme\(p.symptoms.count > 1 ? "s" : "")"
        case "medications": return p.medications.isEmpty ? "Aucun" : "\(p.medications.count)"
        case "digestiveConditions": return p.digestiveConditions.isEmpty ? "Aucune" : "\(p.digestiveConditions.count)"
        default: return "-"
        }
    }

    /// Le libellé humain vient du questionnaire (même source que les options des
    /// pickers) : une table recopiée diverge dès que les options bougent. La
    /// précédente affichait les valeurs techniques post-A3, et son doublon de
    /// clé « medium » faisait trapper Dictionary.init au dépliage d'une section
    /// (crash « Modifier mon profil », présent depuis mai en Release).
    private func friendlyLabel(_ fieldId: String, _ value: String) -> String {
        guard !value.isEmpty else { return "-" }
        return QuestionnaireSection.optionPairs(id: fieldId).first { $0.0 == value }?.1 ?? value
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environmentObject(DashboardViewModel())
    }
}
