import XCTest
@testable import HealthMap

/// Scans every `.swift` source file in the HealthMap bundle for
/// forbidden French vocabulary. These words break the brand voice
/// ("tutoiement bienveillant, jamais diagnostic") defined in the
/// product guidelines.
///
/// If a legitimate use of a forbidden word is needed (e.g. medical
/// reference in a comment), add it to `allowedFilesByKeyword` below.
final class VoiceComplianceTests: XCTestCase {

    /// Words that must never appear in user-facing Swift strings.
    /// Case-insensitive, whole-word match.
    private let forbiddenWords: [String] = [
        "carence",
        "diagnostic",
        "patient",
        "maladie",
    ]

    /// Files that are allowed to contain a given keyword because the
    /// keyword is used in a neutral, technical context (e.g. a doc
    /// comment referencing the web app's legacy naming).
    private let allowedFilesByKeyword: [String: Set<String>] = [
        "diagnostic": ["AppLogger.swift", "ConnectivityService.swift"],
        "maladie": ["RedFlagDetector.swift", "QuestionnaireSection.swift"],
    ]

    func testNoForbiddenWordsInSwiftSources() throws {
        let sourceRoot = Self.sourceRootURL()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Unable to enumerate source tree at \(sourceRoot.path)")
            return
        }

        var violations: [String] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            // Skip the test target itself
            if fileURL.path.contains("HealthMapTests") { continue }

            let contents: String
            do {
                contents = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                continue
            }

            let lines = contents.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                for word in forbiddenWords {
                    guard lower.range(of: "\\b\(word)\\b", options: .regularExpression) != nil else { continue }
                    let filename = fileURL.lastPathComponent
                    if allowedFilesByKeyword[word]?.contains(filename) == true {
                        continue
                    }
                    violations.append("\(filename):\(index + 1) — forbidden word \"\(word)\": \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "\nVoice compliance violations found:\n" + violations.joined(separator: "\n")
        )
    }

    // MARK: - Helpers

    /// Locates the `HealthMap/` source root relative to the test bundle.
    private static func sourceRootURL() -> URL {
        // Start from this test file and walk up to the workspace, then
        // down into HealthMap/. Using #filePath keeps the test portable
        // whether it runs from SPM or Xcode.
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()          // HealthMapTests/
            .deletingLastPathComponent()          // Healthmap-iOS/
            .appendingPathComponent("HealthMap")
    }
}
