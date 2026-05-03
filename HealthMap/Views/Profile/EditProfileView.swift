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

    enum EditSection: String, CaseIterable, Identifiable {
        case profil = "Profil"
        case modeDeVie = "Mode de vie"
        case sante = "Sante"
        case nutrition = "Nutrition"
        case symptomes = "Symptomes"
        case medical = "Medical"

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
                    ForEach(EditSection.allCases) { section in
                        sectionCard(section)
                    }
                }
                .padding(.vertical, Theme.spacingMD)
                .padding(.bottom, hasUnsavedChanges ? 100 : 20)
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
            saveError = "Client indisponible. Réessaie dans un instant."
            HapticService.shared.error()
            return
        }
        guard let session = await AuthService.shared.currentSession else {
            isSaving = false
            saveError = "Session expirée. Merci de te reconnecter."
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
            ToastService.shared.currentToast = "Profil mis à jour — tes scores ont été recalculés"
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
    /// Options : mirror exact des select/picker du questionnaire pour
    /// que les scores health.js calculent identiquement.
    private func fieldsForSection(_ section: EditSection) -> [EditableField] {
        switch section {
        case .profil:
            return [
                EditableField(id: "firstName", label: "Prenom", emoji: "👤", kind: .text(placeholder: "Ton prénom")),
                EditableField(id: "age", label: "Age", emoji: "🎂", kind: .number(unit: "ans", min: 10, max: 110)),
                EditableField(id: "gender", label: "Genre", emoji: "⚧", kind: .pickerSingle(options: [
                    ("homme", "Homme"), ("femme", "Femme"),
                ])),
                EditableField(id: "height", label: "Taille", emoji: "📏", kind: .number(unit: "cm", min: 120, max: 230)),
                EditableField(id: "weight", label: "Poids", emoji: "⚖️", kind: .number(unit: "kg", min: 30, max: 250)),
                EditableField(id: "weightTrend", label: "Tendance poids", emoji: "📈", kind: .pickerSingle(options: [
                    ("stable", "Stable"), ("gain", "Prise"), ("loss", "Perte"), ("unintentional_loss", "Perte non-voulue"),
                ])),
            ]
        case .modeDeVie:
            return [
                EditableField(id: "indoorWork", label: "Travail interieur", emoji: "🏢", kind: .pickerSingle(options: [
                    ("yes", "Oui"), ("no", "Non"),
                ])),
                EditableField(id: "sunExposure", label: "Exposition soleil", emoji: "☀️", kind: .pickerSingle(options: [
                    ("none", "Aucune"), ("very_little", "Très peu"), ("some", "Un peu"), ("moderate", "Modérée"), ("plenty", "Beaucoup"),
                ])),
                EditableField(id: "skinType", label: "Type de peau", emoji: "🖐️", kind: .pickerSingle(options: [
                    ("very_fair", "Très claire"), ("fair", "Claire"), ("medium", "Mate"), ("dark", "Foncée"), ("very_dark", "Très foncée"),
                ])),
                EditableField(id: "strengthTraining", label: "Activite physique", emoji: "🏋️", kind: .pickerSingle(options: [
                    ("none", "Aucune"), ("light", "Légère"), ("moderate", "Modérée"), ("regular", "Régulière"), ("intense", "Intense"),
                ])),
            ]
        case .sante:
            return [
                EditableField(id: "stressLevel", label: "Niveau de stress", emoji: "🧘", kind: .pickerSingle(options: [
                    ("low", "Faible"), ("moderate", "Modéré"), ("high", "Élevé"), ("very_high", "Très élevé"),
                ])),
                EditableField(id: "sleepHours", label: "Heures de sommeil", emoji: "😴", kind: .number(unit: "h", min: 3, max: 12)),
                EditableField(id: "wakeFeeling", label: "Reveil", emoji: "🌅", kind: .pickerSingle(options: [
                    ("rested", "Reposé"), ("ok", "Correct"), ("tired", "Fatigué"), ("exhausted", "Épuisé"),
                ])),
                EditableField(id: "caffeineIntake", label: "Cafeine", emoji: "☕", kind: .pickerSingle(options: [
                    ("none", "Aucune"), ("light", "Légère"), ("moderate", "Modérée"), ("heavy", "Forte"),
                ])),
                EditableField(id: "waterIntake", label: "Eau", emoji: "💧", kind: .pickerSingle(options: [
                    ("low", "< 1L"), ("medium", "1-2L"), ("high", "> 2L"),
                ])),
                EditableField(id: "alcohol", label: "Alcool", emoji: "🍷", kind: .pickerSingle(options: [
                    ("none", "Aucun"), ("occasional", "Occasionnel"), ("weekly", "Hebdomadaire"), ("daily", "Quotidien"),
                ])),
            ]
        case .nutrition:
            return [
                EditableField(id: "dietType", label: "Regime", emoji: "🍽️", kind: .pickerSingle(options: [
                    ("omnivore", "Omnivore"), ("flexitarien", "Flexitarien"), ("vegetarien", "Végétarien"), ("vegan", "Vegan"), ("pescetarien", "Pescétarien"),
                ])),
                EditableField(id: "vegetableServings", label: "Legumes/semaine", emoji: "🥦", kind: .number(unit: "portions", min: 0, max: 30)),
                EditableField(id: "fruitServings", label: "Fruits/semaine", emoji: "🍎", kind: .number(unit: "portions", min: 0, max: 30)),
                EditableField(id: "fattyFish", label: "Poisson gras/sem", emoji: "🐟", kind: .number(unit: "portions", min: 0, max: 10)),
                EditableField(id: "meatPoultry", label: "Viande/semaine", emoji: "🥩", kind: .number(unit: "portions", min: 0, max: 21)),
                EditableField(id: "dairyServings", label: "Produits laitiers", emoji: "🥛", kind: .number(unit: "portions/j", min: 0, max: 10)),
                EditableField(id: "nutsPerWeek", label: "Noix/semaine", emoji: "🥜", kind: .number(unit: "portions", min: 0, max: 14)),
            ]
        case .symptomes:
            return [
                EditableField(id: "symptoms", label: "Symptomes ressentis", emoji: "🩺", kind: .pickerMulti(options: [
                    ("fatigue", "Fatigue"),
                    ("brain_fog", "Brouillard mental"),
                    ("hair_loss", "Chute de cheveux"),
                    ("brittle_nails", "Ongles cassants"),
                    ("muscle_cramps", "Crampes musculaires"),
                    ("tingling", "Fourmillements"),
                    ("dry_skin", "Peau sèche"),
                    ("mood_low", "Humeur basse"),
                    ("sleep_issues", "Troubles du sommeil"),
                    ("digestive_issues", "Troubles digestifs"),
                ])),
            ]
        case .medical:
            return [
                EditableField(id: "medications", label: "Medicaments", emoji: "💊", kind: .pickerMulti(options: [
                    ("ppi", "IPP / anti-acides"),
                    ("metformin", "Metformine"),
                    ("oral_contraceptive", "Contraception orale"),
                    ("antibiotics_recent", "Antibiotiques récents"),
                    ("statins", "Statines"),
                    ("antidepressants", "Antidépresseurs"),
                ])),
                EditableField(id: "digestiveConditions", label: "Conditions digestives", emoji: "🫁", kind: .pickerMulti(options: [
                    ("celiac", "Maladie cœliaque"),
                    ("crohns", "Crohn / MICI"),
                    ("ibs", "Côlon irritable"),
                    ("acid_reflux", "Reflux acide"),
                    ("sibo", "SIBO"),
                ])),
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
        case "weightTrend": return p.weightTrend.isEmpty ? "-" : friendlyLabel(p.weightTrend)
        case "indoorWork": return p.indoorWork == "yes" ? "Oui" : (p.indoorWork == "no" ? "Non" : "-")
        case "sunExposure": return friendlyLabel(p.sunExposure)
        case "skinType": return friendlyLabel(p.skinType)
        case "strengthTraining": return friendlyLabel(p.strengthTraining)
        case "stressLevel": return friendlyLabel(p.stressLevel)
        case "sleepHours": return p.sleepHours.isEmpty ? "-" : "\(p.sleepHours)h"
        case "wakeFeeling": return friendlyLabel(p.wakeFeeling)
        case "caffeineIntake": return friendlyLabel(p.caffeineIntake)
        case "waterIntake": return friendlyLabel(p.waterIntake)
        case "alcohol": return friendlyLabel(p.alcohol)
        case "dietType": return friendlyLabel(p.dietType)
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

    /// Mappe un value technique (stored) vers le label humain affiché.
    /// Cohérent avec les options des pickers définis dans `fieldsForSection`.
    private func friendlyLabel(_ value: String) -> String {
        let map: [String: String] = [
            // weightTrend
            "stable": "Stable", "gain": "Prise", "loss": "Perte", "unintentional_loss": "Perte non-voulue",
            // sunExposure
            "none": "Aucune", "very_little": "Très peu", "some": "Un peu", "moderate": "Modérée", "plenty": "Beaucoup",
            // skinType
            "very_fair": "Très claire", "fair": "Claire", "medium": "Mate", "dark": "Foncée", "very_dark": "Très foncée",
            // strengthTraining / stressLevel
            "light": "Légère", "regular": "Régulière", "intense": "Intense",
            "low": "Faible", "high": "Élevé", "very_high": "Très élevé",
            // wakeFeeling
            "rested": "Reposé", "ok": "Correct", "tired": "Fatigué", "exhausted": "Épuisé",
            // caffeineIntake / waterIntake / alcohol
            "heavy": "Forte", "medium": "1-2L", "occasional": "Occasionnel", "weekly": "Hebdomadaire", "daily": "Quotidien",
            // dietType
            "omnivore": "Omnivore", "flexitarien": "Flexitarien", "vegetarien": "Végétarien",
            "vegan": "Vegan", "pescetarien": "Pescétarien",
        ]
        if value.isEmpty { return "-" }
        return map[value] ?? value
    }
}

#Preview {
    NavigationStack {
        EditProfileView()
            .environmentObject(DashboardViewModel())
    }
}
