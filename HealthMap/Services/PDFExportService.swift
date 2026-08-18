import Foundation
import UIKit
import PDFKit

// MARK: - PDF Export Service (mirrors pdfExport.js)
// Generates A4 portrait PDF with full health report

@MainActor
final class PDFExportService {
    static let shared = PDFExportService()
    private init() {}

    // MARK: - Constants
    private let pageWidth: CGFloat = 595.28   // A4 width in points
    private let pageHeight: CGFloat = 841.89  // A4 height in points
    private let margin: CGFloat = 40
    private let brandBlue = UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1)

    // MARK: - Generate PDF
    func generatePDF(
        profile: UserProfile,
        healthScore: Int,
        nutrients: [EnrichedNutrient],
        analysis: MergedAnalysis?,
        redFlags: [RedFlag]
    ) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            var currentY: CGFloat = 0

            // --- PAGE 1 ---
            context.beginPage()
            currentY = margin

            // Header banner
            currentY = drawHeader(in: context.cgContext, y: currentY, firstName: profile.firstName)

            // Score global
            currentY = drawScoreSection(in: context.cgContext, y: currentY, score: healthScore, headline: analysis?.summary?.headline)

            // Profil summary
            currentY = drawProfileSection(in: context.cgContext, y: currentY, profile: profile)

            // Red flags
            if !redFlags.isEmpty {
                currentY = drawRedFlags(in: context.cgContext, y: currentY, flags: redFlags)
            }

            // Nutriments table
            currentY = drawNutrientsTable(in: context.cgContext, y: currentY, nutrients: nutrients, context: context)

            // --- Check if we need a new page ---
            if currentY > pageHeight - 200 {
                drawFooter(in: context.cgContext, pageNumber: 1)
                context.beginPage()
                currentY = margin
            }

            // Interactions
            if let interactions = analysis?.interactions, !interactions.isEmpty {
                currentY = drawInteractions(in: context.cgContext, y: currentY, interactions: interactions, context: context)
            }

            // Priority actions
            if let actions = analysis?.priorityActions, !actions.isEmpty {
                currentY = drawPriorityActions(in: context.cgContext, y: currentY, actions: actions, context: context)
            }

            // Supplements schedule
            if let schedule = analysis?.supplementsSchedule {
                currentY = drawSupplementsSchedule(in: context.cgContext, y: currentY, schedule: schedule, context: context)
            }

            // Disclaimer
            currentY = drawDisclaimer(in: context.cgContext, y: currentY, context: context)

            // Footer
            drawFooter(in: context.cgContext, pageNumber: currentY > pageHeight - 100 ? 2 : 1)
        }

        return data
    }

    // MARK: - Header
    private func drawHeader(in ctx: CGContext, y: CGFloat, firstName: String) -> CGFloat {
        // Blue banner
        ctx.setFillColor(brandBlue.cgColor)
        ctx.fill(CGRect(x: 0, y: y, width: pageWidth, height: 80))

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let title = "Kiwio" as NSString
        title.draw(at: CGPoint(x: margin, y: y + 15), withAttributes: titleAttrs)

        // Subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ]
        let subtitle = "Bilan Nutritionnel Personnalise" as NSString
        subtitle.draw(at: CGPoint(x: margin, y: y + 48), withAttributes: subtitleAttrs)

        // Date + name
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        let dateStr = formatter.string(from: Date())

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        ]
        let info = "\(firstName) — \(dateStr)" as NSString
        let infoSize = info.size(withAttributes: infoAttrs)
        info.draw(at: CGPoint(x: pageWidth - margin - infoSize.width, y: y + 50), withAttributes: infoAttrs)

        return y + 100
    }

    // MARK: - Score Section
    private func drawScoreSection(in ctx: CGContext, y: CGFloat, score: Int, headline: String?) -> CGFloat {
        var currentY = y + 10

        // Gray background box
        let boxHeight: CGFloat = headline != nil ? 80 : 60
        ctx.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
        ctx.fill(CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: boxHeight))

        // Score
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: scoreUIColor(score),
        ]
        let scoreStr = "\(score)/100" as NSString
        scoreStr.draw(at: CGPoint(x: margin + 16, y: currentY + 10), withAttributes: scoreAttrs)

        // Label
        let label = scoreLabel(score)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: scoreUIColor(score),
        ]
        (label as NSString).draw(at: CGPoint(x: margin + 160, y: currentY + 20), withAttributes: labelAttrs)

        // Headline
        if let headline {
            let headlineAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.darkGray,
            ]
            let headlineRect = CGRect(x: margin + 16, y: currentY + 48, width: pageWidth - margin * 2 - 32, height: 30)
            (headline as NSString).draw(in: headlineRect, withAttributes: headlineAttrs)
        }

        return currentY + boxHeight + 16
    }

    // MARK: - Profile Section
    private func drawProfileSection(in ctx: CGContext, y: CGFloat, profile: UserProfile) -> CGFloat {
        var currentY = y

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        ("Profil" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 22

        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.darkGray,
        ]

        let age = profile.age.isEmpty ? "-" : profile.age
        let genre = profile.gender == .homme ? "Homme" : "Femme"
        let regime = profile.dietType
        let pathway = profile.pathway == .express ? "Express" : "Complet"

        let infoText = "Âge : \(age) ans  |  Genre : \(genre)  |  Régime : \(regime)  |  Questionnaire : \(pathway)"
        (infoText as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: infoAttrs)

        return currentY + 30
    }

    // MARK: - Red Flags
    private func drawRedFlags(in ctx: CGContext, y: CGFloat, flags: [RedFlag]) -> CGFloat {
        var currentY = y

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.systemRed,
        ]
        ("⚠️ Alertes importantes" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 22

        for flag in flags {
            // Pink background
            ctx.setFillColor(UIColor.systemRed.withAlphaComponent(0.06).cgColor)
            ctx.fill(CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 24))

            let flagAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.systemRed,
            ]
            let rect = CGRect(x: margin + 8, y: currentY + 5, width: pageWidth - margin * 2 - 16, height: 18)
            (flag.message as NSString).draw(in: rect, withAttributes: flagAttrs)
            currentY += 28
        }

        return currentY + 8
    }

    // MARK: - Nutrients Table
    private func drawNutrientsTable(in ctx: CGContext, y: CGFloat, nutrients: [EnrichedNutrient], context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        ("Nutriments analyses" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 24

        // Table header
        let colHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: UIColor.gray,
        ]
        ("Nutriment" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: colHeaderAttrs)
        ("Score" as NSString).draw(at: CGPoint(x: margin + 200, y: currentY), withAttributes: colHeaderAttrs)
        ("Statut" as NSString).draw(at: CGPoint(x: margin + 260, y: currentY), withAttributes: colHeaderAttrs)
        ("Verdict" as NSString).draw(at: CGPoint(x: margin + 340, y: currentY), withAttributes: colHeaderAttrs)
        currentY += 18

        // Separator
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: currentY))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
        ctx.strokePath()
        currentY += 6

        for nutrient in nutrients {
            // Check page break
            if currentY > pageHeight - 80 {
                drawFooter(in: ctx, pageNumber: 1)
                context.beginPage()
                currentY = margin
            }

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.black,
            ]
            ("\(nutrient.emoji) \(nutrient.label)" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: nameAttrs)

            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: scoreUIColor(nutrient.score),
            ]
            ("\(nutrient.score)%" as NSString).draw(at: CGPoint(x: margin + 200, y: currentY), withAttributes: scoreAttrs)

            let status = NutrientStatus(score: nutrient.score)
            let statusColor: UIColor = nutrient.score >= 60 ? .systemGreen : nutrient.score >= 40 ? .systemOrange : .systemRed
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: statusColor,
            ]
            (status.rawValue.capitalized as NSString).draw(at: CGPoint(x: margin + 260, y: currentY), withAttributes: statusAttrs)

            // Verdict (truncated)
            if let verdict = nutrient.verdict {
                let verdictAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.darkGray,
                ]
                let maxChars = min(verdict.count, 50)
                let truncated = String(verdict.prefix(maxChars)) + (verdict.count > 50 ? "..." : "")
                let verdictRect = CGRect(x: margin + 340, y: currentY, width: pageWidth - margin - 340 - margin, height: 14)
                (truncated as NSString).draw(in: verdictRect, withAttributes: verdictAttrs)
            }

            currentY += 20
        }

        return currentY + 10
    }

    // MARK: - Interactions
    private func drawInteractions(in ctx: CGContext, y: CGFloat, interactions: [InteractionDetected], context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        if currentY > pageHeight - 150 {
            drawFooter(in: ctx, pageNumber: 1)
            context.beginPage()
            currentY = margin
        }

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        ("Interactions détectées" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 24

        for inter in interactions.prefix(5) {
            if currentY > pageHeight - 100 {
                drawFooter(in: ctx, pageNumber: 1)
                context.beginPage()
                currentY = margin
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.black,
            ]
            let emoji = inter.emoji ?? "⚡"
            ("\(emoji) \(inter.titre ?? "")" as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: titleAttrs)
            currentY += 18

            if let expl = inter.explication {
                let explAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.darkGray,
                ]
                let rect = CGRect(x: margin + 8, y: currentY, width: pageWidth - margin * 2 - 16, height: 28)
                (expl as NSString).draw(in: rect, withAttributes: explAttrs)
                currentY += 32
            }

            if let sol = inter.solution {
                let solAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: UIColor.systemGreen,
                ]
                let rect = CGRect(x: margin + 8, y: currentY, width: pageWidth - margin * 2 - 16, height: 18)
                ("✅ \(sol)" as NSString).draw(in: rect, withAttributes: solAttrs)
                currentY += 24
            }
        }

        return currentY + 8
    }

    // MARK: - Priority Actions
    private func drawPriorityActions(in ctx: CGContext, y: CGFloat, actions: [PriorityAction], context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        if currentY > pageHeight - 120 {
            drawFooter(in: ctx, pageNumber: 1)
            context.beginPage()
            currentY = margin
        }

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        ("Actions prioritaires" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 24

        let sorted = actions.sorted { ($0.rank ?? 0) < ($1.rank ?? 0) }
        for (index, action) in sorted.prefix(5).enumerated() {
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: brandBlue,
            ]
            ("\(index + 1)." as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: numAttrs)

            let actionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: UIColor.black,
            ]
            let rect = CGRect(x: margin + 28, y: currentY, width: pageWidth - margin * 2 - 36, height: 16)
            ((action.action ?? "") as NSString).draw(in: rect, withAttributes: actionAttrs)
            currentY += 18

            if let impact = action.expectedImpact {
                let impactAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.gray,
                ]
                ("Impact : \(impact)" as NSString).draw(at: CGPoint(x: margin + 28, y: currentY), withAttributes: impactAttrs)
                currentY += 16
            }
        }

        return currentY + 8
    }

    // MARK: - Supplements Schedule
    private func drawSupplementsSchedule(in ctx: CGContext, y: CGFloat, schedule: SupplementsSchedule, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        let morning = schedule.morning ?? []
        let afternoon = schedule.afternoon ?? []
        let evening = schedule.evening ?? []

        guard !morning.isEmpty || !afternoon.isEmpty || !evening.isEmpty else { return currentY }

        if currentY > pageHeight - 120 {
            drawFooter(in: ctx, pageNumber: 1)
            context.beginPage()
            currentY = margin
        }

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: UIColor.black,
        ]
        ("Programme supplements" as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: headerAttrs)
        currentY += 24

        let slotAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.black,
        ]
        let itemAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.darkGray,
        ]

        if !morning.isEmpty {
            ("☀️ Matin" as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: slotAttrs)
            currentY += 16
            for item in morning {
                ("  • \(item.displayText)" as NSString).draw(at: CGPoint(x: margin + 16, y: currentY), withAttributes: itemAttrs)
                currentY += 14
            }
            currentY += 6
        }

        if !afternoon.isEmpty {
            ("🌤️ Midi" as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: slotAttrs)
            currentY += 16
            for item in afternoon {
                ("  • \(item.displayText)" as NSString).draw(at: CGPoint(x: margin + 16, y: currentY), withAttributes: itemAttrs)
                currentY += 14
            }
            currentY += 6
        }

        if !evening.isEmpty {
            ("🌙 Soir" as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: slotAttrs)
            currentY += 16
            for item in evening {
                ("  • \(item.displayText)" as NSString).draw(at: CGPoint(x: margin + 16, y: currentY), withAttributes: itemAttrs)
                currentY += 14
            }
            currentY += 6
        }

        // Warnings
        if let warnings = schedule.warnings, !warnings.isEmpty {
            currentY += 4
            let warnAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.systemOrange,
            ]
            for w in warnings {
                ("⚠️ \(w)" as NSString).draw(at: CGPoint(x: margin + 8, y: currentY), withAttributes: warnAttrs)
                currentY += 14
            }
        }

        return currentY + 10
    }

    // MARK: - Disclaimer
    private func drawDisclaimer(in ctx: CGContext, y: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y + 10

        if currentY > pageHeight - 80 {
            drawFooter(in: ctx, pageNumber: 1)
            context.beginPage()
            currentY = margin
        }

        // Separator
        ctx.setStrokeColor(UIColor.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: currentY))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: currentY))
        ctx.strokePath()
        currentY += 10

        let disclaimerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.gray,
        ]
        let text = "Ce document est généré à titre informatif uniquement. Il ne constitue pas un avis médical. Les scores et recommandations reposent sur les informations fournies dans le questionnaire. Consulte un professionnel de santé avant de modifier ton alimentation ou de commencer une complémentation."
        let rect = CGRect(x: margin, y: currentY, width: pageWidth - margin * 2, height: 40)
        (text as NSString).draw(in: rect, withAttributes: disclaimerAttrs)

        return currentY + 50
    }

    // MARK: - Footer
    private func drawFooter(in ctx: CGContext, pageNumber: Int) {
        let y = pageHeight - 30

        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.lightGray,
        ]

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        let dateStr = formatter.string(from: Date())

        ("Page \(pageNumber) — \(dateStr) — www.healthmap.fr" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttrs)

        let pageStr = "Kiwio" as NSString
        let size = pageStr.size(withAttributes: footerAttrs)
        pageStr.draw(at: CGPoint(x: pageWidth - margin - size.width, y: y), withAttributes: footerAttrs)
    }

    // MARK: - Helpers

    private func scoreUIColor(_ score: Int) -> UIColor {
        if score >= 75 { return brandBlue }
        if score >= 50 { return .systemGreen }
        if score >= 40 { return .systemOrange }
        return .systemRed
    }

    private func scoreLabel(_ score: Int) -> String {
        if score >= 75 { return "Excellent" }
        if score >= 60 { return "Bon" }
        if score >= 40 { return "A ameliorer" }
        return "Critique"
    }

    // MARK: - Generate & Share

    func generateAndShare(
        profile: UserProfile,
        healthScore: Int,
        nutrients: [EnrichedNutrient],
        analysis: MergedAnalysis?,
        redFlags: [RedFlag]
    ) {
        guard let pdfData = generatePDF(
            profile: profile,
            healthScore: healthScore,
            nutrients: nutrients,
            analysis: analysis,
            redFlags: redFlags
        ) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let firstName = profile.firstName.isEmpty ? "Utilisateur" : profile.firstName
        let fileName = "Kiwio_Bilan_\(firstName)_\(dateStr).pdf"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? pdfData.write(to: tempURL)

        // Present share sheet
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }

        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = rootVC.view

        rootVC.present(activityVC, animated: true)

        AnalyticsService.shared.track(.pdfExported)
    }
}
