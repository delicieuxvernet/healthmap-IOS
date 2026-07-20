import Foundation
import UIKit

// MARK: - Vignettes locales des repas scannés
/// Stocke sur l'appareil une petite vignette (~120 pt JPEG) de la photo d'un
/// scan repas, pour l'afficher dans « Scans récents » et « Tes derniers
/// repas » (retour build 319). Choix assumé : stockage LOCAL uniquement —
/// `meal_scans` ne stocke aucune photo (décision RGPD/coût), donc la vignette
/// n'existe que sur l'appareil qui a fait le scan. Un repas sans vignette
/// (dictée, recherche, autre appareil) garde son illustration actuelle.
///
/// Clés :
///   - `id` de la row `meal_scans` quand l'Edge Function le renvoie (cas nominal) ;
///   - repli `ts-<epoch>` sinon, associé ensuite au repas dont `consumedAt`
///     est à ±5 min (les scans photo sont rares — 2/jour en free — le risque
///     de collision est négligeable).
enum MealThumbnailStore {

    private static let maxSide: CGFloat = 240   // 120 pt @2x
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MealThumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(forKey key: String) -> URL {
        directory.appendingPathComponent("\(key).jpg")
    }

    // MARK: - Écriture (au moment du scan)

    /// Redimensionne et enregistre la photo du scan. `mealId` = id de la row
    /// renvoyée par l'Edge Function ; nil → clé temporelle de repli.
    static func save(photo data: Data, mealId: String?, scannedAt: Date = Date()) {
        guard let image = UIImage(data: data) else { return }
        let key = mealId ?? "ts-\(Int(scannedAt.timeIntervalSince1970))"

        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }

        guard let jpeg = thumb.jpegData(compressionQuality: 0.7) else { return }
        try? jpeg.write(to: url(forKey: key), options: .atomic)
        purgeOld()
    }

    // MARK: - Lecture (affichage des listes)

    /// Vignette d'un repas : par id d'abord, sinon par proximité temporelle
    /// avec une clé de repli `ts-<epoch>` (±5 min).
    static func image(mealId: String, consumedAt: Date) -> UIImage? {
        if let img = UIImage(contentsOfFile: url(forKey: mealId).path) {
            return img
        }
        let target = consumedAt.timeIntervalSince1970
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return nil }
        for file in files where file.hasPrefix("ts-") {
            let epochPart = file.dropFirst(3).replacingOccurrences(of: ".jpg", with: "")
            if let epoch = TimeInterval(epochPart), abs(epoch - target) <= 300 {
                return UIImage(contentsOfFile: directory.appendingPathComponent(file).path)
            }
        }
        return nil
    }

    /// Vide tout (déconnexion — les photos de repas sont des données du compte).
    static func clearAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Les vignettes de plus de 30 jours ne servent plus à rien (les listes
    /// montrent les derniers repas) : on les jette pour ne pas grossir.
    private static func purgeOld() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limit = Date().addingTimeInterval(-maxAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < limit {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
