import SwiftUI

// MARK: - Scan View (barcode product lookup via Open Food Facts)
struct ScanView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @State private var barcode = ""
    @State private var isSearching = false
    @State private var product: ScannedProduct?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.healthMapBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.spacingLG) {
                        // Input
                        barcodeInput

                        // Quick examples
                        if product == nil && !isSearching {
                            quickExamples
                        }

                        // Results
                        if isSearching {
                            VStack(spacing: Theme.spacingSM) {
                                ProgressView()
                                    .tint(Color.healthMapBlue)
                                Text("Recherche en cours...")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(Color.healthMapSecondary)
                            }
                            .padding(Theme.spacingXL)
                        } else if let product {
                            productResultView(product)
                        }

                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.vertical, Theme.spacingMD)
                }
            }
            .navigationTitle("Scanner produit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Barcode Input

    private var barcodeInput: some View {
        HStack {
            Image(systemName: "barcode.viewfinder")
                .foregroundStyle(Color.healthMapBlue)

            TextField("Code-barres (ex: 3017620422003)", text: $barcode)
                .font(Theme.bodyFont)
                .keyboardType(.numberPad)

            Button {
                Task { await search() }
            } label: {
                Text("Chercher")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.healthMapBlue)
                    .clipShape(Capsule())
            }
            .disabled(barcode.isEmpty || isSearching)
        }
        .padding(Theme.spacingSM)
        .background(Color.healthMapCard)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Quick Examples

    private var quickExamples: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Exemples rapides")
                .font(Theme.captionFont)
                .foregroundStyle(Color.healthMapSecondary)

            HStack(spacing: 8) {
                exampleButton("Nutella", code: "3017624010701")
                exampleButton("Evian", code: "3068320114286")
                exampleButton("Gerble", code: "3175681105058")
            }
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    private func exampleButton(_ name: String, code: String) -> some View {
        Button {
            barcode = code
            Task { await search() }
        } label: {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.healthMapBlue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.healthMapBlueLight)
                .clipShape(Capsule())
        }
    }

    // MARK: - Search

    @MainActor
    private func search() async {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        product = nil

        // Collect user deficiencies from dashboard
        let userDeficiencies: [NutrientID] = dashboardVM.deficiencies.compactMap {
            NutrientID(rawValue: $0.id)
        }

        do {
            let result = try await FoodScanService.shared.lookupBarcode(
                trimmed,
                userDeficiencies: userDeficiencies
            )
            product = result
            GamificationService.shared.recordCheckin()
            AnalyticsService.shared.track(.productScanned, properties: [
                "barcode": trimmed,
                "product_name": result.name,
                "personal_score": result.personalScore,
            ])
        } catch let error as FoodScanError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Erreur inattendue. Reessaie."
        }

        isSearching = false
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.scoreDeficient)
            Text(message)
                .font(Theme.captionFont)
                .foregroundStyle(Color.scoreDeficient)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.scoreDeficient.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Product Result View

    private func productResultView(_ product: ScannedProduct) -> some View {
        VStack(spacing: Theme.spacingMD) {
            productHeader(product)
            macrosGrid(product)
            personalScoreCard(product)

            if !product.impacts.isEmpty {
                impactTagList(product)
            }

            dataQualityBadge(product.dataQuality)
        }
        .padding(.horizontal, Theme.spacingLG)
    }

    // MARK: - Product Header

    private func productHeader(_ product: ScannedProduct) -> some View {
        VStack(spacing: Theme.spacingMD) {
            // Product image
            if let imageURL = product.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
                    case .failure:
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.healthMapMuted)
                            .frame(height: 80)
                    case .empty:
                        ProgressView()
                            .frame(height: 80)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.healthMapText)
                    Text(product.brand)
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapSecondary)
                    if let qty = product.quantity, !qty.isEmpty {
                        Text(qty)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.healthMapMuted)
                    }
                }

                Spacer()

                if let ns = product.nutriScore {
                    nutriScoreBadge(ns)
                }
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
    }

    // MARK: - NutriScore Badge

    private func nutriScoreBadge(_ grade: String) -> some View {
        VStack(spacing: 2) {
            Text("Nutri-Score")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
            Text(grade)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(FoodScanService.nutriScoreColor(grade))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Macros Grid

    private func macrosGrid(_ product: ScannedProduct) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Valeurs nutritionnelles (100g)")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)

            HStack(spacing: 0) {
                macroPill("Energie", "\(product.energy)", "kcal", Color.healthMapBlue)
                macroPill("Proteines", String(format: "%.1f", product.proteins), "g", Color(hex: "34C759"))
                macroPill("Glucides", String(format: "%.1f", product.carbs), "g", Color(hex: "FF9500"))
                macroPill("Lipides", String(format: "%.1f", product.fats), "g", Color(hex: "FF3B30"))
                macroPill("Sucres", String(format: "%.1f", product.sugars), "g", Color(hex: "AF52DE"))
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
    }

    private func macroPill(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(Color.healthMapMuted)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.healthMapSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Personal Score Card

    private func personalScoreCard(_ product: ScannedProduct) -> some View {
        let score = product.personalScore
        let defCount = dashboardVM.deficiencies.count
        let coveredCount = product.impacts.filter { $0.classification == .tresPositif }.count

        return VStack(spacing: Theme.spacingMD) {
            // Header
            Text("Score personnel")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Large score display
            HStack(spacing: Theme.spacingMD) {
                VStack(spacing: 4) {
                    Text(scoreEmoji(score))
                        .font(.system(size: 36))
                    Text("\(score)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.globalScoreColor(for: score))
                    Text("/ 100")
                        .font(Theme.captionFont)
                        .foregroundStyle(Color.healthMapMuted)
                }

                Spacer()

                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text(scoreVerdict(score))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.globalScoreColor(for: score))

                    if defCount > 0 {
                        if coveredCount > 0 {
                            Text("Ce produit couvre \(coveredCount) de tes \(defCount) besoins")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                        } else {
                            Text("Ce produit ne couvre aucun de tes \(defCount) besoins")
                                .font(Theme.captionFont)
                                .foregroundStyle(Color.healthMapSecondary)
                        }
                    }

                    Text(scoreExplanation(score))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.healthMapMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Theme.spacingMD)
        .background(Color.globalScoreColor(for: score).opacity(0.06))
        .cardStyle()
    }

    private func scoreEmoji(_ score: Int) -> String {
        if score >= 80 { return "😁" }
        if score >= 60 { return "🙂" }
        if score >= 40 { return "😐" }
        if score >= 20 { return "😟" }
        return "😞"
    }

    private func scoreVerdict(_ score: Int) -> String {
        if score >= 80 { return "Excellent choix !" }
        if score >= 60 { return "Bon choix" }
        if score >= 40 { return "Choix moyen" }
        if score >= 20 { return "A eviter" }
        return "Deconseille"
    }

    private func scoreExplanation(_ score: Int) -> String {
        if score >= 80 {
            return "Ce produit repond bien a tes besoins nutritionnels et couvre plusieurs de tes points faibles."
        }
        if score >= 60 {
            return "Ce produit a des apports interessants pour ton profil, mais pas ideaux."
        }
        if score >= 40 {
            return "Ce produit a un impact limite sur tes besoins. Cherche des alternatives."
        }
        return "Ce produit apporte peu a ton profil et contient des elements a limiter."
    }

    // MARK: - Impact Tag List

    private func impactTagList(_ product: ScannedProduct) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingSM) {
            Text("Impact nutritionnel")
                .font(Theme.captionBoldFont)
                .foregroundStyle(Color.healthMapSecondary)

            FlowLayout(spacing: 8) {
                ForEach(product.impacts) { impact in
                    impactTag(impact)
                }
            }
        }
        .padding(Theme.spacingMD)
        .cardStyle()
    }

    private func impactTag(_ impact: NutrientImpact) -> some View {
        HStack(spacing: 4) {
            Text(impact.emoji)
                .font(.system(size: 12))
            Text(impact.label)
                .font(.system(size: 11, weight: .semibold))
            if impact.pctRDA > 0 {
                Text("\(impact.pctRDA)% AJR")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(impact.classification == .neutre ? Color.healthMapSecondary : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(impact.classification == .neutre
            ? Color.healthMapMuted.opacity(0.15)
            : impact.classification.color)
        .clipShape(Capsule())
    }

    // MARK: - Data Quality Badge

    private func dataQualityBadge(_ quality: DataQuality) -> some View {
        HStack(spacing: Theme.spacingSM) {
            Image(systemName: quality.level.icon)
                .foregroundStyle(quality.level.color)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(quality.available)/\(quality.total) nutriments disponibles")
                    .font(Theme.captionBoldFont)
                    .foregroundStyle(Color.healthMapText)
                Text(quality.level.label)
                    .font(.system(size: 11))
                    .foregroundStyle(quality.level.color)
            }

            Spacer()
        }
        .padding(Theme.spacingSM)
        .background(quality.level.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
    }
}

// MARK: - Flow Layout (wrapping tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return (offsets, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

#Preview {
    ScanView()
        .environmentObject(DashboardViewModel())
}
