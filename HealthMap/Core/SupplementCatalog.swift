import Foundation

// MARK: - Supplement Catalog (extracted from SupplementEngine)
// Catalogue produits vérifié fiche par fiche sur les sites des marques.
// Read-only reference data — no logic here.
//
// Audit du 30 septembre 2026 (`verifiedAt`) : marque, forme, dosage, prix de
// référence (hors promo), prises/jour et URL fiche officielle reverifies une
// fiche apres l'autre. Six ecarts corriges, deux URL mortes remplacees, une
// reference retiree pour rupture. Seul le format de l'omega-3 Nutri&Co n'a pas
// pu etre reconfirme (selecteur 60/120 capsules illisible) : valeur conservee.
// DOCTRINE DE SELECTION (Arthur, 20 septembre 2026) : on recommande TOUJOURS
// la forme la mieux absorbee et la mieux supportee sur la duree — bisglycinate
// pour le fer, le magnesium et le zinc, D3 huileuse pour la vitamine D. Le prix
// arbitre A QUALITE EGALE, jamais contre elle : on ne veut pas d'effets
// indesirables chez les gens. Une reference qui depasse ce que l'ANSES juge
// prudent sort du catalogue, meme si elle est legale.
//
// Règle des tiers : `premium` = meilleure formulation (défaut affiché),
// `value` = option la plus abordable — jamais un « Éco » plus cher qu'un
// « Premium » pour un même nutriment. Le premier produit d'un tier gagne
// (ordre intentionnel), donc lister le meilleur en premier.
//
// Les prix étant volatils, toute réutilisation doit re-vérifier `verifiedAt`.
//
// `whyBrand` (audit de conformité du 9 octobre 2026) : composition et forme,
// rien d'autre. Aucun bienfait, aucun effet sur le corps : une allégation de
// santé sur un complément n'est permise que dans les mots exacts du règlement
// (UE) 432/2012, et l'app n'en a pas besoin pour dire ce qu'il y a dedans.

extension SupplementEngine {

    // ============================================================
    // STATIC PRODUCT CATALOG
    // ============================================================

    static let catalogVerifiedAt = "2026-09-30"

    static let catalog: [SupplementProduct] = [

        // --- VITAMINE D ---
        SupplementProduct(
            id: "vitd3-k2-dynveo",
            name: "Vitamine D3 + K2 MK-7",
            nutrientID: .vitD,
            brand: "Dynveo",
            dosage: "2000 UI D3 + 80 µg K2",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 28.90,
            unitsPerPackage: 60,
            productURL: "https://www.dynveo.fr/products/vitamine-d3-k2-mk7",
            isVegan: true,
            contraindications: [.hypercalcemie],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Vitamine D3 d'origine végétale (lichen), associée à de la vitamine K2 MK-7 (K2VITAL)."
        ),
        SupplementProduct(
            id: "vitd3-gouttes-nutrico",
            name: "Vitamine D3 Végétale (gouttes)",
            nutrientID: .vitD,
            brand: "Nutri&Co",
            dosage: "1000 UI par goutte",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 19.90,
            unitsPerPackage: 150,
            productURL: "https://nutriandco.com/fr/produits/vitamine-d",
            isVegan: true,
            contraindications: [.hypercalcemie],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Format gouttes économique (~0,13 €/jour, ~5 mois d'autonomie). D3 végétale extraite du lichen."
        ),

        // --- VITAMINE B12 ---
        SupplementProduct(
            id: "b12-methylcobalamine-nutrico",
            name: "Vitamine B12 Méthylcobalamine",
            nutrientID: .vitB12,
            brand: "Nutri&Co",
            dosage: "1000 µg méthylcobalamine",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 19.90,
            unitsPerPackage: 120,
            productURL: "https://nutriandco.com/fr/produits/vitamine-b12",
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Méthylcobalamine en gélule concentrée, végane."
        ),
        SupplementProduct(
            id: "b12-3-formes-dynveo",
            name: "Vitamine B12 Active (3 formes)",
            nutrientID: .vitB12,
            brand: "Dynveo",
            dosage: "250 µg · 3 formes actives",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 8.90,
            unitsPerPackage: 60,
            productURL: "https://www.dynveo.fr/products/vitamine-b12",
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Trois formes de B12 en une gélule, sans additifs, à ~0,15 €/jour."
        ),

        // --- FER ---
        // La grossesse ne masque plus le fer : elle déclenche une précaution
        // « valide avec ton médecin/sage-femme » côté moteur (besoins accrus).
        SupplementProduct(
            id: "fer-bisglycinate-nutrico",
            name: "Fer Bisglycinate + Souche Lactique",
            nutrientID: .iron,
            brand: "Nutri&Co",
            dosage: "14 mg fer + vitamine C + folate",
            unitsPerDay: 1,
            timing: .matinAJeun,
            price: 18.90,
            unitsPerPackage: 30,
            productURL: "https://nutriandco.com/fr/produits/fer",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: ["calcium", "zinc"],
            tier: .premium,
            whyBrand: "Fer bisglycinate Ferrochel, souche lactique, vitamine C et folate 5-MTHF, en une gélule."
        ),
        SupplementProduct(
            id: "fer-bisglycinate-aromazone",
            name: "Fer Bisglycinate + Vitamine C",
            nutrientID: .iron,
            brand: "Aroma-Zone",
            dosage: "14 mg Ferrochel + vitamine C",
            unitsPerDay: 1,
            timing: .matinAJeun,
            price: 9.95,
            unitsPerPackage: 90,
            // L'ancienne adresse rend un 404 depuis la refonte du site : seules
            // les pages /en/ repondent. Page anglaise faute de mieux, a
            // remplacer des qu'on retrouve l'adresse francaise.
            productURL: "https://www.aroma-zone.com/en/product/food-supplement-iron",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: ["calcium", "zinc"],
            tier: .value,
            whyBrand: "Même matière première Ferrochel que le premium, en version simple. ~0,11 €/jour."
        ),

        // --- MAGNESIUM ---
        // Le melange 3 formes a 300 mg/j est sorti le 20 septembre 2026 : le
        // comite de l'Anses (avis du 31 juillet 2024) ecrit que la dose
        // journaliere ne devrait pas depasser 250 mg, la limite superieure de
        // securite. Remplace par un bisglycinate pur — la forme la mieux
        // toleree, sans effet laxatif — a 225 mg sur la prise conseillee.
        // Premium seul : aucune alternative de meme qualite n'est moins chere
        // au mois, et un « Éco » plus cher serait mensonger.
        SupplementProduct(
            id: "magnesium-bisglycinate-dynveo",
            name: "Magnésium Bisglycinate chélaté",
            nutrientID: .magnesium,
            brand: "Dynveo",
            dosage: "75 mg de magnésium par gélule · TRAACS",
            unitsPerDay: 3,
            timing: .soirRepas,
            price: 29.90,
            unitsPerPackage: 180,
            productURL: "https://www.dynveo.fr/products/magnesium-bisglycinate",
            isVegan: true,
            contraindications: [.insuffisanceRenaleSevere],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Bisglycinate TRAACS pur, sans oxyde ajouté. Fabriqué en France, sans excipient superflu."
        ),

        // --- OMEGA-3 ---
        // Deux entrées premium : Nutri&Co (poisson) pour les omnivores, Dynveo
        // (algue) pour vegan/végétariens qui filtrent le poisson. Ordre = Nutri&Co
        // d'abord, donc l'omnivore reçoit le poisson, le végétal reçoit l'algue.
        SupplementProduct(
            id: "omega3-dha-nutrico",
            name: "Oméga-3 EPAX (DHA dominant)",
            nutrientID: .omega3,
            brand: "Nutri&Co",
            dosage: "750 mg DHA + 150 mg EPA",
            unitsPerDay: 3,
            timing: .midiRepas,
            price: 19.90,
            unitsPerPackage: 120,
            productURL: "https://nutriandco.com/fr/produits/omega-3",
            isVegan: false,   // huile de poisson
            contraindications: [.allergiePoisson],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Riche en DHA, forme triglycéride, en capsules Licaps."
        ),
        SupplementProduct(
            id: "omega3-algue-dynveo",
            name: "Oméga-3 Végétal (Algue)",
            nutrientID: .omega3,
            brand: "Dynveo",
            dosage: "500 mg DHA + 250 mg EPA",
            unitsPerDay: 2,
            timing: .midiRepas,
            price: 24.90,
            unitsPerPackage: 60,
            productURL: "https://www.dynveo.fr/products/omega-3-vegetal",
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Huile d'algue Schizochytrium, végane : DHA et EPA sans poisson."
        ),

        // --- VITAMINE C ---
        SupplementProduct(
            id: "vitc-liposomale-dynveo",
            name: "Vitamine C Liposomale",
            nutrientID: .vitC,
            brand: "Dynveo",
            dosage: "1000 mg liposomale (2 gél.)",
            unitsPerDay: 2,
            timing: .matinRepas,
            price: 29.90,
            unitsPerPackage: 60,
            productURL: "https://www.dynveo.fr/products/vitamine-c-liposomale",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Vitamine C sous forme liposomale."
        ),
        SupplementProduct(
            id: "vitc-qualic-nutripure",
            name: "Vitamine C Quali-C 750 mg",
            nutrientID: .vitC,
            brand: "Nutripure",
            dosage: "750 mg Quali-C",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 13.90,
            unitsPerPackage: 60,
            productURL: "https://www.nutripure.fr/fr/sante/68-vitamine-c.html",
            isVegan: true,
            // Meme raison que la version liposomale : la vitamine C augmente
            // l'absorption du fer. La precaution ne peut pas dependre du
            // produit tire par le moteur.
            contraindications: [.hemochromatose],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Vitamine C Quali-C (qualité pharmaceutique européenne), sans excipient."
        ),

        // --- CALCIUM ---
        // Premium = Argalys (formule complète Ca + D3 + K2), Value = Nutrixeal
        // (lithothamne pur, le moins cher au mois).
        SupplementProduct(
            id: "calcium-d3-k2-argalys",
            name: "Calcium + D3 + K2",
            nutrientID: .calcium,
            brand: "Argalys",
            dosage: "480 mg calcium + D3 + K2 (2 gél.)",
            unitsPerDay: 2,
            timing: .midiRepas,
            price: 12.50,
            unitsPerPackage: 60,
            productURL: "https://www.argalys.com/products/calcium-vitamine-d3-et-k2",
            isVegan: true,
            contraindications: [.hypercalcemie],
            antiInteractions: ["iron", "zinc"],
            tier: .premium,
            whyBrand: "Calcium, vitamine D3 et vitamine K2, véganes, réunis en un produit."
        ),
        SupplementProduct(
            id: "calcium-lithothamne-nutrixeal",
            name: "Lithothamne (Calcium marin)",
            nutrientID: .calcium,
            brand: "Nutrixeal",
            dosage: "~380 mg calcium marin (2 gél.)",
            unitsPerDay: 2,
            timing: .midiRepas,
            price: 13.00,
            unitsPerPackage: 90,
            productURL: "https://www.nutrixeal.fr/175-lithothamne.html",
            isVegan: true,
            contraindications: [.hypercalcemie],
            antiInteractions: ["iron", "zinc"],
            tier: .value,
            whyBrand: "Calcium marin issu du lithothamne, une algue rouge. 100 % pur."
        ),

        // --- ZINC ---
        // La reference a 15 mg est sortie le 20 septembre 2026 : le comite de
        // l'Anses estime que la dose journaliere ne devrait pas depasser
        // 9,7 mg, la population adulte francaise etant deja bien pourvue. Les
        // deux references etaient des bisglycinates — seule la dose les
        // separait, on garde la plus prudente.
        SupplementProduct(
            id: "zinc-bisglycinate-nutrico",
            name: "Zinc Bisglycinate + Liposomal",
            nutrientID: .zinc,
            brand: "Nutri&Co",
            dosage: "10 mg zinc (2 formes) + sélénium",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 12.90,
            unitsPerPackage: 60,
            productURL: "https://nutriandco.com/fr/produits/zinc",
            isVegan: true,
            contraindications: [],
            antiInteractions: ["iron", "calcium"],
            tier: .premium,
            whyBrand: "Deux formes brevetées (bisglycinate TRAACS + Zinc Nova liposomal) + sélénium."
        ),
        // --- IODE ---
        // L'option eco (Enova, 365 comprimes a 25 EUR) est sortie le
        // 30 septembre 2026 : en rupture chez le fabricant. Envoyer quelqu'un
        // vers un produit qu'il ne peut pas acheter est pire que ne proposer
        // qu'une reference. A remettre au prochain audit si elle revient.
        SupplementProduct(
            id: "iode-puresea-nutrico",
            name: "Iode PureSea (algue)",
            nutrientID: .iodine,
            brand: "Nutri&Co",
            dosage: "150 µg (100% AR)",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 14.90,
            unitsPerPackage: 120,
            productURL: "https://nutriandco.com/fr/produits/iode",
            isVegan: true,
            contraindications: [.hyperthyroidie],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Iode d'algue PureSea standardisée à dosage constant (vs kelp générique variable)."
        ),
        // --- FIBRES ---
        SupplementProduct(
            id: "fibres-trio-nutrico",
            name: "Fibres Bio (Acacia + Guar + Psyllium)",
            nutrientID: .fiber,
            brand: "Nutri&Co",
            dosage: "4,5 g de fibres par dosette",
            unitsPerDay: 1,
            timing: .entreRepas,
            price: 19.90,
            unitsPerPackage: 28,
            productURL: "https://nutriandco.com/fr/produits/fibres-bio",
            isVegan: true,
            contraindications: [],
            antiInteractions: [antiInteractionMedicaments],
            tier: .premium,
            whyBrand: "Trois fibres solubles bio (acacia, guar, psyllium), certifiées Low-FODMAP."
        ),
        SupplementProduct(
            id: "psyllium-blond-aromazone",
            name: "Psyllium Blond Bio",
            nutrientID: .fiber,
            brand: "Aroma-Zone",
            dosage: "5 g téguments de psyllium",
            unitsPerDay: 1,
            timing: .entreRepas,
            price: 13.90,
            unitsPerPackage: 60,
            // Meme refonte que le fer : ancienne adresse en 404, page anglaise
            // faute d'equivalent francais retrouvable.
            productURL: "https://www.aroma-zone.com/en/product/food-supplement-organic-blond-psyllium",
            isVegan: true,
            contraindications: [],
            antiInteractions: [antiInteractionMedicaments],
            tier: .value,
            whyBrand: "Téguments de psyllium blond bio, purs. À prendre avec un grand verre d'eau."
        ),
    ]
}
