import XCTest
import ImageIO
@testable import HealthMap

// MARK: - Le signe Kiwio (maquette « Identité · un seul logo, partout »)
//
// Le signe est dessiné en SwiftUI à partir du SVG source : ces tests le tiennent
// point par point (palette, disques, douze graines), vérifient que l'icône et
// l'image de lancement du dépôt sont bien celles du signe, et que le loader
// « pépins qui chargent » fait son tour en 1,8 s.

final class KiwiSigneTests: XCTestCase {

    // MARK: La palette et la géométrie

    func testLaPaletteEstCelleDeLaMaquette() {
        XCTAssertEqual(KiwiMarque.hexPeau, "2F5A16")
        XCTAssertEqual(KiwiMarque.hexChair, "5DA838")
        XCTAssertEqual(KiwiMarque.hexHalo, "9FD46F")
        XCTAssertEqual(KiwiMarque.hexCoeur, "EAF3DE")
        XCTAssertEqual(KiwiMarque.nombreDeGraines, 12)
        XCTAssertEqual(KiwiMarque.graineLargeur, 3.8)
        XCTAssertEqual(KiwiMarque.graineHauteur, 7.2)
    }

    func testLesDisquesSontCeuxDuSVG() {
        XCTAssertEqual(KiwiMarque.Geometrie.standard.disques.map(\.rayon), [48, 43, 21, 12])
        XCTAssertEqual(KiwiMarque.Geometrie.standard.disques.map(\.teinte), [.peau, .chair, .halo, .coeur])
        XCTAssertEqual(KiwiMarque.Geometrie.surVert.disques.map(\.rayon), [46, 22.5, 12.8])
        XCTAssertFalse(KiwiMarque.Geometrie.surVert.disques.contains { $0.teinte == .peau },
                       "sur fond vert kiwi, la peau disparaît")
    }

    /// Les centres et les rotations des douze graines du SVG source.
    func testLesGrainesSontCellesDuSVG() {
        let attendues: [(x: CGFloat, y: CGFloat, rotation: Double)] = [
            (76, 50, 90), (72.52, 63, 120), (63, 72.52, 150), (50, 76, 180),
            (37, 72.52, 210), (27.48, 63, 240), (24, 50, 270), (27.48, 37, 300),
            (37, 27.48, 330), (50, 24, 360), (63, 27.48, 390), (72.52, 37, 420),
        ]
        for (index, attendue) in attendues.enumerated() {
            let graine = KiwiMarque.graine(index, orbite: KiwiMarque.Geometrie.standard.orbiteDesGraines)
            XCTAssertEqual(graine.centre.x, attendue.x, accuracy: 0.01, "graine \(index)")
            XCTAssertEqual(graine.centre.y, attendue.y, accuracy: 0.01, "graine \(index)")
            XCTAssertEqual(graine.rotation * 180 / .pi, attendue.rotation, accuracy: 0.001, "graine \(index)")
        }
        // « sur-vert » : l'orbite s'écarte à 28 (78, 50) · (74,25 ; 64).
        let surVert = KiwiMarque.graine(1, orbite: KiwiMarque.Geometrie.surVert.orbiteDesGraines)
        XCTAssertEqual(surVert.centre.x, 74.25, accuracy: 0.01)
        XCTAssertEqual(surVert.centre.y, 64, accuracy: 0.01)
    }

    // MARK: Le loader : les pépins qui chargent

    func testLaTraineeFaitUnTourEn1Virgule8Seconde() {
        XCTAssertEqual(KiwiLoader.periode, 1.8)
        let maintenant = KiwiLoader.opacites(ecoule: 2.3)
        let unTourPlusTard = KiwiLoader.opacites(ecoule: 2.3 + KiwiLoader.periode)
        XCTAssertEqual(maintenant.count, KiwiMarque.nombreDeGraines)
        for (a, b) in zip(maintenant, unTourPlusTard) { XCTAssertEqual(a, b, accuracy: 1e-9) }
    }

    /// Une seule graine à plein éclat, les autres s'estompent sans disparaître.
    func testUneGraineSAllumeLesAutresSEstompent() {
        let eclats = KiwiLoader.opacites(ecoule: 0.46)
        XCTAssertEqual(eclats.filter { $0 > 0.95 }.count, 1)
        XCTAssertGreaterThanOrEqual(eclats.min() ?? 0, KiwiLoader.eclatMinimum - 1e-9)
        XCTAssertLessThanOrEqual(eclats.max() ?? 2, 1)
    }

    /// La tête avance d'une graine toutes les 0,15 s, dans le sens des aiguilles d'une montre.
    func testLaTeteTourneDansLeSensDesAiguilles() {
        func tete(_ temps: Double) -> Int {
            let eclats = KiwiLoader.opacites(ecoule: temps)
            return eclats.firstIndex(of: eclats.max() ?? 1) ?? -1
        }
        let pas = KiwiLoader.periode / Double(KiwiMarque.nombreDeGraines)
        let depart = tete(0.46)
        XCTAssertEqual(tete(0.46 + pas), (depart + 1) % 12)
        XCTAssertEqual(tete(0.46 + 5 * pas), (depart + 5) % 12)
    }

    /// Au premier instant, la couronne est pleine : le passage depuis l'écran
    /// de lancement statique (le signe entier) ne saute pas.
    func testLEntreePartDeLaCouronnePleine() {
        XCTAssertTrue(KiwiLoader.opacites(ecoule: 0).allSatisfy { $0 == 1 })
        let aMiChemin = KiwiLoader.opacites(ecoule: KiwiLoader.entree / 2)
        XCTAssertTrue(aMiChemin.allSatisfy { $0 > 0.5 && $0 <= 1 })
        XCTAssertFalse(aMiChemin.allSatisfy { $0 == 1 })
    }

    // MARK: Les fichiers du dépôt

    private var catalogue: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("HealthMap/Resources/Assets.xcassets")
    }

    /// Lit le fichier tel quel. `UIImage(contentsOfFile:)` irait chercher la
    /// variante @3x voisine sur un simulateur 3x : on passe par ImageIO.
    private func image(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Lit un pixel (RVB) d'une image.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int)? {
        var octets = [UInt8](repeating: 0, count: 4)
        guard let contexte = CGContext(data: &octets, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        contexte.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(octets[0]), Int(octets[1]), Int(octets[2]))
    }

    private func proche(_ a: (Int, Int, Int)?, _ hex: String, tolerance: Int = 6) -> Bool {
        guard let a else { return false }
        let v = Int(hex, radix: 16) ?? 0
        return abs(a.0 - (v >> 16 & 0xFF)) <= tolerance && abs(a.1 - (v >> 8 & 0xFF)) <= tolerance
            && abs(a.2 - (v & 0xFF)) <= tolerance
    }

    /// L'icône Apple est le signe « sur-vert » : 1024 px, opaque, fond chair,
    /// cœur au centre, halo autour.
    func testLIconeEstLeSigneSurVert() throws {
        let icone = try XCTUnwrap(image(catalogue.appendingPathComponent("AppIcon.appiconset/AppIcon.png")))
        XCTAssertEqual(icone.width, 1024)
        XCTAssertEqual(icone.height, 1024)
        XCTAssertTrue([.none, .noneSkipLast, .noneSkipFirst].contains(icone.alphaInfo),
                      "l'App Store refuse une icône avec transparence")
        XCTAssertTrue(proche(pixel(icone, x: 8, y: 8), KiwiMarque.hexChair), "fond")
        XCTAssertTrue(proche(pixel(icone, x: 512, y: 512), KiwiMarque.hexCoeur), "cœur")
        // Entre le cœur (r 12,8 → 92 px) et le halo (r 22,5 → 162 px).
        XCTAssertTrue(proche(pixel(icone, x: 512 + 130, y: 512), KiwiMarque.hexHalo), "halo")
    }

    /// L'écran de lancement statique affiche le signe, en trois résolutions.
    func testLImageDeLancementExiste() throws {
        let dossier = catalogue.appendingPathComponent("LaunchSigne.imageset")
        for (fichier, cote) in [("LaunchSigne.png", 72), ("LaunchSigne@2x.png", 144), ("LaunchSigne@3x.png", 216)] {
            let rendu = try XCTUnwrap(image(dossier.appendingPathComponent(fichier)), fichier)
            XCTAssertEqual(rendu.width, cote, fichier)
            XCTAssertTrue(proche(pixel(rendu, x: cote / 2, y: cote / 2), KiwiMarque.hexCoeur), fichier)
        }
    }
}
