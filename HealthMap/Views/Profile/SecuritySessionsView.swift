import SwiftUI
import ClerkKit

/// Liste les sessions Clerk actives du user et permet de les déconnecter
/// individuellement ou en masse (sauf la courante).
///
/// Plan B3 (10 mai 2026) — symétrique du composant web `SecurityCard.jsx`.
///
/// - Charge `Clerk.shared.user?.getSessions()` à l'apparition
/// - Marque la session courante (`Clerk.shared.session?.id`) avec un badge
///   "CET APPAREIL" et désactive le bouton revoke pour elle
/// - Bouton "Déconnecter de tous les autres appareils" qui itère sur les
///   sessions distantes et appelle `session.revoke()` en série (pour ne pas
///   spammer Clerk + avoir un retour propre par session)
/// - Si l'API ClerkKit change (renommage de `getSessions()` ou `revoke()`),
///   le build Xcode renverra une erreur de compilation explicite — l'idée
///   est de garder le code lisible plutôt que de cacher des erreurs
struct SecuritySessionsView: View {
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var revokingSessionId: String?
    @State private var isRevokingAll = false

    private var currentSessionId: String? {
        Clerk.shared.session?.id
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
            }

            if isLoading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Chargement…")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.healthMapSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            } else if sessions.isEmpty {
                Section {
                    Text("Aucune session active.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.healthMapSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section {
                    ForEach(sessions, id: \.id) { session in
                        sessionRow(session)
                    }
                } footer: {
                    Text("Si tu vois un appareil que tu ne reconnais pas, déconnecte-le immédiatement et change ton mot de passe.")
                        .font(.system(size: 11))
                }

                let otherCount = sessions.filter { $0.id != currentSessionId }.count
                if otherCount > 0 {
                    Section {
                        Button(role: .destructive) {
                            Task { await revokeAllOthers() }
                        } label: {
                            HStack {
                                if isRevokingAll {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "iphone.slash")
                                }
                                Text("Déconnecter de tous les autres appareils (\(otherCount))")
                            }
                        }
                        .disabled(isRevokingAll || revokingSessionId != nil)
                    }
                }
            }
        }
        .navigationTitle("Mes sessions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
        .refreshable { await loadSessions() }
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let isCurrent = session.id == currentSessionId
        let isRevokingThis = revokingSessionId == session.id

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: deviceIconName(for: session))
                    .font(.system(size: 14))
                    .foregroundStyle(isCurrent ? Color.healthMapBlue : Color.healthMapSecondary)
                Text(deviceLabel(for: session))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.healthMapText)
                if isCurrent {
                    Text("CET APPAREIL")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.healthMapBlue.opacity(0.12))
                        .foregroundStyle(Color.healthMapBlue)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(relativeLastActive(for: session))
                if let location = locationLabel(for: session), !location.isEmpty {
                    Text("·")
                    Text(location)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.healthMapSecondary)

            if !isCurrent {
                Button(role: .destructive) {
                    Task { await revoke(session) }
                } label: {
                    HStack(spacing: 4) {
                        if isRevokingThis {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 11))
                        }
                        Text("Déconnecter")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .disabled(isRevokingThis || isRevokingAll)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data loading + actions

    private func loadSessions() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let user = Clerk.shared.user else {
            errorMessage = "Tu n'es pas connecté."
            return
        }

        do {
            let list = try await user.getSessions()
            // Tri : session courante en premier, puis par lastActiveAt desc
            sessions = list.sorted { lhs, rhs in
                if lhs.id == currentSessionId { return true }
                if rhs.id == currentSessionId { return false }
                let lhsDate = lhs.lastActiveAt ?? .distantPast
                let rhsDate = rhs.lastActiveAt ?? .distantPast
                return lhsDate > rhsDate
            }
        } catch {
            AppLogger.auth.report(error, context: "SecuritySessionsView.loadSessions")
            errorMessage = "Impossible de charger les sessions. Réessaie."
        }
    }

    private func revoke(_ session: Session) async {
        guard session.id != currentSessionId else { return }
        revokingSessionId = session.id
        defer { revokingSessionId = nil }

        do {
            try await session.revoke()
            HapticService.shared.success()
            await loadSessions()
        } catch {
            AppLogger.auth.report(error, context: "SecuritySessionsView.revoke")
            HapticService.shared.warning()
            errorMessage = "Impossible de déconnecter cette session."
        }
    }

    private func revokeAllOthers() async {
        let others = sessions.filter { $0.id != currentSessionId }
        guard !others.isEmpty else { return }
        isRevokingAll = true
        defer { isRevokingAll = false }

        var failures = 0
        for session in others {
            do {
                try await session.revoke()
            } catch {
                failures += 1
                AppLogger.auth.report(error, context: "SecuritySessionsView.revokeAll item")
            }
        }

        if failures == 0 {
            HapticService.shared.success()
        } else {
            HapticService.shared.warning()
            errorMessage = "\(failures) session\(failures > 1 ? "s" : "") n'\(failures > 1 ? "ont" : "a") pas pu être déconnectée\(failures > 1 ? "s" : "")."
        }
        await loadSessions()
    }

    // MARK: - Display helpers

    private func deviceIconName(for session: Session) -> String {
        // L'API SessionWithActivities expose `latestActivity.deviceType` (string).
        // On est défensif sur le format exact.
        let activity = activityDescriptor(for: session)
        let deviceType = (activity?.deviceType ?? "").lowercased()
        if deviceType.contains("iphone") || deviceType.contains("phone") || deviceType.contains("mobile") {
            return "iphone"
        }
        if deviceType.contains("ipad") || deviceType.contains("tablet") {
            return "ipad"
        }
        if deviceType.contains("desktop") || deviceType.contains("mac") || deviceType.contains("pc") {
            return "desktopcomputer"
        }
        return "questionmark.circle"
    }

    private func deviceLabel(for session: Session) -> String {
        let activity = activityDescriptor(for: session)
        let browser = activity?.browserName ?? ""
        let device = activity?.deviceType ?? ""
        if !browser.isEmpty, !device.isEmpty {
            return "\(browser) · \(device)"
        }
        return browser.isEmpty ? (device.isEmpty ? "Appareil inconnu" : device) : browser
    }

    private func locationLabel(for session: Session) -> String? {
        let activity = activityDescriptor(for: session)
        let city = activity?.city
        let country = activity?.country
        if let city, let country, !city.isEmpty, !country.isEmpty {
            return "\(city), \(country)"
        }
        return country ?? city
    }

    private func relativeLastActive(for session: Session) -> String {
        guard let date = session.lastActiveAt else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Récupère le descripteur d'activité (latestActivity / actor selon la
    /// version du SDK) sans casser le compile si la propriété renomme.
    /// On utilise un protocol-like d'accesseurs nommés pour rester souple ;
    /// si la signature change côté ClerkKit, ce sera le seul endroit à patcher.
    private func activityDescriptor(for session: Session) -> SessionActivityDescriptor? {
        // SessionWithActivities expose `.latestActivity` (struct avec deviceType,
        // browserName, browserVersion, country, city, ipAddress).
        // Si la structure exposée change, adapter ici.
        let mirror = Mirror(reflecting: session)
        for child in mirror.children where child.label == "latestActivity" {
            return SessionActivityDescriptor(reflecting: child.value)
        }
        return nil
    }
}

/// Descripteur défensif des champs d'activité d'une session.
/// Lit via `Mirror` pour survivre à des renames mineurs côté ClerkKit.
private struct SessionActivityDescriptor {
    let deviceType: String?
    let browserName: String?
    let browserVersion: String?
    let country: String?
    let city: String?

    init(reflecting value: Any) {
        var deviceType: String?
        var browserName: String?
        var browserVersion: String?
        var country: String?
        var city: String?
        let mirror = Mirror(reflecting: value)
        for child in mirror.children {
            switch child.label {
            case "deviceType":     deviceType = child.value as? String
            case "browserName":    browserName = child.value as? String
            case "browserVersion": browserVersion = child.value as? String
            case "country":        country = child.value as? String
            case "city":           city = child.value as? String
            default: break
            }
        }
        self.deviceType = deviceType
        self.browserName = browserName
        self.browserVersion = browserVersion
        self.country = country
        self.city = city
    }
}

#Preview {
    NavigationStack {
        SecuritySessionsView()
    }
}
