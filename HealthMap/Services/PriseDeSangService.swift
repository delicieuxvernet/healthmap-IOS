import Foundation
import Supabase
import UIKit

/// Prise de sang (Premium) — appelle l'edge function `analyze-blood-report`
/// et lit la table `blood_reports`.
///
/// ⚠️ RÈGLES (décisions du 6 juil. 2026, reprises le 30 sept.) :
///   · le fichier du laboratoire ne quitte le téléphone que pour être LU : le
///     serveur n'en garde rien, seules les valeurs extraites sont stockées ;
///   · l'app n'écrit jamais dans `blood_reports` (RLS : lecture et suppression
///     seulement) ;
///   · aucun calcul ici : `PriseDeSangApports` en fait une ligne du registre.
@MainActor
final class PriseDeSangService {

    static let shared = PriseDeSangService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    /// Ce que l'on envoie : un PDF tel quel, ou une photo ramenée en JPEG.
    struct Fichier: Equatable {
        let donnees: Data
        let typeMime: String

        /// Borne serveur (`MAX_OCTETS`) : les deux DOIVENT rester égales.
        static let octetsMax = 8 * 1024 * 1024
        /// Assez pour lire un tableau de labo, pas davantage.
        static let coteMaxPhoto: CGFloat = 2400

        static func pdf(_ donnees: Data) -> Fichier {
            Fichier(donnees: donnees, typeMime: "application/pdf")
        }

        /// JPEG, grand côté ramené à 2400 px. nil si l'image est illisible.
        static func photo(_ image: UIImage) -> Fichier? {
            let taille = image.size
            let echelle = min(1, coteMaxPhoto / max(taille.width, taille.height, 1))
            let cible = CGSize(width: (taille.width * echelle).rounded(), height: (taille.height * echelle).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendu = UIGraphicsImageRenderer(size: cible, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: cible))
            }
            guard let jpeg = rendu.jpegData(compressionQuality: 0.8) else { return nil }
            return Fichier(donnees: jpeg, typeMime: "image/jpeg")
        }
    }

    enum Erreur: LocalizedError, Equatable {
        case premiumRequis
        case trop
        case pasUneAnalyse
        case aucuneValeur
        case tropLourd
        case indisponible

        var errorDescription: String? {
            switch self {
            case .premiumRequis:
                return "La prise de sang fait partie de Kiwio Premium."
            case .trop:
                return "Tu as importé beaucoup de documents aujourd'hui. Réessaie demain."
            case .pasUneAnalyse:
                return "Ce document ne ressemble pas à un compte rendu d'analyse de sang. Essaie avec la page des résultats."
            case .aucuneValeur:
                return "Kiwio n'a trouvé aucune valeur qu'il sait lire (vitamine D, B12, ferritine, magnésium…). Essaie avec une autre page."
            case .tropLourd:
                return "Ce fichier est trop lourd. Essaie avec une photo de la page des résultats."
            case .indisponible:
                return "La lecture n'a pas abouti. Vérifie que la photo est nette, puis réessaie."
            }
        }
    }

    // MARK: - Lecture d'un document

    private struct Body: Encodable {
        let fichier: String
        let typeMime: String
        enum CodingKeys: String, CodingKey {
            case fichier
            case typeMime = "type_mime"
        }
    }

    private struct Reponse: Decodable {
        let report: PriseDeSang
        let dejaImporte: Bool?
        enum CodingKeys: String, CodingKey {
            case report
            case dejaImporte = "deja_importe"
        }
    }

    private struct CorpsErreur: Decodable { let error: String? }

    func analyser(_ fichier: Fichier) async throws -> PriseDeSang {
        guard fichier.donnees.count <= Fichier.octetsMax else { throw Erreur.tropLourd }
        do {
            return try await envoyer(fichier)
        } catch Erreur.premiumRequis {
            // Refusé comme à un compte gratuit alors que l'app voit un
            // abonné : le serveur n'a pas encore suivi l'achat. Une seconde
            // chance, une fois qu'il le reconnaît.
            guard await SubscriptionService.shared.realignerLeServeur() else { throw Erreur.premiumRequis }
            return try await envoyer(fichier)
        }
    }

    private func envoyer(_ fichier: Fichier) async throws -> PriseDeSang {
        do {
            let reponse: Reponse = try await TacheProtegee.executer("Prise de sang") {
                try await client.functions.invoke(
                    "analyze-blood-report",
                    options: .init(body: Body(fichier: fichier.donnees.base64EncodedString(), typeMime: fichier.typeMime))
                )
            }
            return reponse.report
        } catch let error as FunctionsError {
            if case .httpError(let code, let data) = error {
                let motif = (try? JSONDecoder().decode(CorpsErreur.self, from: data))?.error
                AppLogger.analysis.error("analyze-blood-report \(code, privacy: .public) \(motif ?? "", privacy: .public)")
                switch (code, motif) {
                case (403, _): throw Erreur.premiumRequis
                case (429, _): throw Erreur.trop
                case (413, _): throw Erreur.tropLourd
                case (422, "pas_une_analyse"): throw Erreur.pasUneAnalyse
                case (422, _): throw Erreur.aucuneValeur
                default: throw Erreur.indisponible
                }
            }
            throw Erreur.indisponible
        } catch let error as Erreur {
            throw error
        } catch {
            AppLogger.analysis.error("analyze-blood-report a échoué: \(error.localizedDescription, privacy: .public)")
            throw Erreur.indisponible
        }
    }

    // MARK: - Table

    private static let colonnes = "id, taken_at, date_lue, markers"

    /// La prise de sang la plus récente (date du prélèvement), ou nil.
    func derniere(userId: String) async throws -> PriseDeSang? {
        let lignes: [PriseDeSang] = try await client
            .from("blood_reports")
            .select(Self.colonnes)
            .eq("user_id", value: userId)
            .order("taken_at", ascending: false)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return lignes.first
    }

    /// Suppression définitive (la personne efface sa donnée de santé).
    func supprimer(id: String) async throws {
        try await client.from("blood_reports").delete().eq("id", value: id).execute()
    }
}
