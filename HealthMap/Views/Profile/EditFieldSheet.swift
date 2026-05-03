import SwiftUI

// MARK: - Editable Field Descriptor
/// Décrit un champ éditable : son type d'éditeur (text, number, picker, multi, toggle)
/// et ses options si applicable. Pattern inspiré d'Apple Health : chaque field est
/// édité dans son propre sheet contextuel plutôt qu'un gros formulaire.
struct EditableField: Identifiable, Equatable {
    enum Kind: Equatable {
        case text(placeholder: String)
        case number(unit: String, min: Int, max: Int)
        case decimal(unit: String)
        case pickerSingle(options: [(value: String, label: String)])
        case pickerMulti(options: [(value: String, label: String)])
        case toggle

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            // Equatable simplifié — suffisant pour .sheet(item:) diffing
            switch (lhs, rhs) {
            case (.text, .text), (.number, .number), (.decimal, .decimal),
                 (.pickerSingle, .pickerSingle), (.pickerMulti, .pickerMulti),
                 (.toggle, .toggle):
                return true
            default: return false
            }
        }
    }

    let id: String        // ex: "age", "firstName"
    let label: String     // ex: "Âge"
    let emoji: String
    let kind: Kind
}

// MARK: - Edit Field Sheet
/// Sheet contextuel d'édition d'un field. Appelé depuis EditProfileView.
/// Commit les changements via le callback `onSave` qui reçoit la nouvelle value.
struct EditFieldSheet: View {
    let field: EditableField
    let currentValue: Any  // String, [String], Bool, selon le kind
    let onSave: (Any) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var textValue: String = ""
    @State private var intValue: Int = 0
    @State private var arrayValue: [String] = []
    @State private var boolValue: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spacingLG) {
                        // Header emoji + label (cohérent avec le fieldRow)
                        HStack(spacing: Theme.spacingSM) {
                            Text(field.emoji)
                                .font(.system(size: 32))
                                .accessibilityHidden(true)
                            Text(field.label)
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Color.healthMapText)
                        }
                        .padding(.top, Theme.spacingSM)

                        // Éditeur selon le kind
                        editor
                            .padding(Theme.spacingMD)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.healthMapCard)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    }
                    .padding(.horizontal, Theme.spacingLG)
                    .padding(.bottom, Theme.spacingXXL)
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        HapticService.shared.selection()
                        onSave(currentOutput())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { isInputFocused = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { initState() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - Editor switch
    @ViewBuilder
    private var editor: some View {
        switch field.kind {
        case .text(let placeholder):
            TextField(placeholder, text: $textValue)
                .font(.system(.body, design: .rounded))
                .focused($isInputFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onAppear { isInputFocused = true }

        case .number(let unit, let min, let max):
            HStack(spacing: Theme.spacingMD) {
                Stepper(value: $intValue, in: min...max) {
                    HStack {
                        Text("\(intValue)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(intValue)))
                        Text(unit)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                }
            }
            .tint(Color.healthMapBlue)

        case .decimal(let unit):
            HStack {
                TextField("0", text: $textValue)
                    .keyboardType(.decimalPad)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .focused($isInputFocused)
                    .onAppear { isInputFocused = true }
                Text(unit)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.healthMapSecondary)
            }

        case .pickerSingle(let options):
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        HapticService.shared.selection()
                        textValue = opt.value
                    } label: {
                        HStack {
                            Text(opt.label)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.healthMapText)
                            Spacer()
                            if textValue == opt.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.healthMapBlue)
                            }
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    if idx < options.count - 1 {
                        Divider()
                    }
                }
            }

        case .pickerMulti(let options):
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    Button {
                        HapticService.shared.selection()
                        if arrayValue.contains(opt.value) {
                            arrayValue.removeAll { $0 == opt.value }
                        } else {
                            arrayValue.append(opt.value)
                        }
                    } label: {
                        HStack {
                            Text(opt.label)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color.healthMapText)
                            Spacer()
                            Image(systemName: arrayValue.contains(opt.value) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(arrayValue.contains(opt.value) ? Color.healthMapBlue : Color.healthMapMuted.opacity(0.4))
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.healthMapPressed)
                    if idx < options.count - 1 {
                        Divider()
                    }
                }
            }

        case .toggle:
            Toggle(isOn: $boolValue) {
                Text(field.label)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.healthMapText)
            }
            .tint(Color.healthMapBlue)
        }
    }

    // MARK: - State init
    private func initState() {
        switch field.kind {
        case .text:
            textValue = (currentValue as? String) ?? ""
        case .number:
            intValue = (currentValue as? Int) ?? Int((currentValue as? String) ?? "") ?? 0
        case .decimal:
            textValue = (currentValue as? String) ?? ""
        case .pickerSingle:
            textValue = (currentValue as? String) ?? ""
        case .pickerMulti:
            arrayValue = (currentValue as? [String]) ?? []
        case .toggle:
            boolValue = (currentValue as? Bool) ?? false
        }
    }

    // MARK: - Current output
    private func currentOutput() -> Any {
        switch field.kind {
        case .text, .decimal, .pickerSingle:
            return textValue
        case .number:
            return String(intValue)
        case .pickerMulti:
            return arrayValue
        case .toggle:
            return boolValue
        }
    }
}
