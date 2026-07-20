import Foundation

// MARK: - Supplement Catalog (extracted from SupplementEngine)
// Catalogue produits vérifié fiche par fiche sur les sites des marques.
// Read-only reference data — no logic here.
//
// Audit du 20 juillet 2026 (`verifiedAt`) : marque, forme, dosage, prix de
// référence (hors promo), prises/jour et URL fiche officielle confirmés.
// Règle des tiers : `premium` = meilleure formulation (défaut affiché),
// `value` = option la plus abordable — jamais un « Éco » plus cher qu'un
// « Premium » pour un même nutriment. Le premier produit d'un tier gagne
// (ordre intentionnel), donc lister le meilleur en premier.
//
// Les prix étant volatils, toute réutilisation doit re-vérifier `verifiedAt`.

extension SupplementEngine {

    // ============================================================
    // STATIC PRODUCT CATALOG
    // ============================================================

    static let catalogVerifiedAt = "2026-07-20"

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
            whyBrand: "Synergie D3 + K2 (brevet K2VITAL) : la K2 aide à orienter le calcium vers les os. D3 d'origine végétale (lichen)."
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
            whyBrand: "Méthylcobalamine (brevet MecobalActive) : forme bioactive directement assimilable et stable."
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
            whyBrand: "Trois formes bioactives (méthyl, adénosyl, hydroxo) en une gélule, sans additifs. ~0,15 €/jour."
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
            price: 19.90,
            unitsPerPackage: 30,
            productURL: "https://nutriandco.com/fr/produits/fer",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: ["calcium", "zinc"],
            tier: .premium,
            whyBrand: "Fer bisglycinate Ferrochel + souche lactique + vitamine C + folate 5-MTHF : douceur digestive et absorption soutenue."
        ),
        SupplementProduct(
            id: "fer-bisglycinate-aromazone",
            name: "Fer Bisglycinate + Vitamine C",
            nutrientID: .iron,
            brand: "Aroma-Zone",
            dosage: "14 mg Ferrochel + vitamine C",
            unitsPerDay: 1,
            timing: .matinAJeun,
            price: 9.90,
            unitsPerPackage: 90,
            productURL: "https://www.aroma-zone.com/product/complement-alimentaire-bisglycinate-de-fer",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: ["calcium", "zinc"],
            tier: .value,
            whyBrand: "Même matière première Ferrochel que le premium, en version simple. ~0,11 €/jour."
        ),

        // --- MAGNESIUM ---
        // Premium seul : la seule alternative « sport » du marché revenait plus
        // cher au mois que ce produit — un « Éco » plus cher serait mensonger.
        SupplementProduct(
            id: "magnesium-3-formes-nutrico",
            name: "Le Magnésium (3 formes)",
            nutrientID: .magnesium,
            brand: "Nutri&Co",
            dosage: "300 mg · 3 formes + B6",
            unitsPerDay: 3,
            timing: .soirRepas,
            price: 19.90,
            unitsPerPackage: 120,
            productURL: "https://nutriandco.com/fr/produits/magnesium",
            isVegan: true,
            contraindications: [.insuffisanceRenaleSevere],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Trois formes de magnésium (bisglycinate, malate, liposomal) + B6 bioactive : plusieurs voies d'absorption."
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
            whyBrand: "Ratio riche en DHA (objectif cognitif), forme triglycéride, capsules Licaps anti-oxydation."
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
            whyBrand: "Alternative végane (huile d'algue Schizochytrium) : DHA + EPA sans poisson, zéro contamination."
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
            price: 21.90,
            unitsPerPackage: 60,
            productURL: "https://www.dynveo.fr/products/vitamine-c-liposomale",
            isVegan: true,
            contraindications: [.hemochromatose],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Forme liposomale : meilleure biodisponibilité et tolérance digestive que la vitamine C classique."
        ),
        SupplementProduct(
            id: "vitc-qualic-nutripure",
            name: "Vitamine C Quali-C 750 mg",
            nutrientID: .vitC,
            brand: "Nutripure",
            dosage: "750 mg Quali-C",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 27.90,
            unitsPerPackage: 60,
            productURL: "https://www.nutripure.fr/fr/sante/68-vitamine-c.html",
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Vitamine C Quali-C (qualité pharmaceutique européenne), sans excipient. 1 gélule/jour."
        ),

        // --- CALCIUM ---
        // Premium = Argalys (formule complète Ca + D3 + K2), Value = Nutrixeal
        // (lithothamne pur, le moins cher au mois).
        SupplementProduct(
            id: "calcium-d3-k2-argalys",
            name: "Calcium + D3 + K2",
            nutrientID: .calcium,
            brand: "Argalys",
            dosage: "500 mg calcium + D3 + K2 (3 gél.)",
            unitsPerDay: 3,
            timing: .midiRepas,
            price: 12.50,
            unitsPerPackage: 60,
            productURL: "https://www.argalys.com/products/calcium-vitamine-d3-et-k2",
            isVegan: true,
            contraindications: [.hypercalcemie],
            antiInteractions: ["iron", "zinc"],
            tier: .premium,
            whyBrand: "Formule complète calcium + D3 + K2 végane en un produit, pour aider à fixer le calcium sur l'os."
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
            whyBrand: "Calcium marin (lithothamne), algue rouge naturellement riche en calcium et oligo-éléments. 100% pur."
        ),

        // --- ZINC ---
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
            whyBrand: "Deux formes brevetées (bisglycinate TRAACS + Zinc Nova liposomal) + sélénium. 100% des apports de référence."
        ),
        SupplementProduct(
            id: "zinc-cuivre-ineldea",
            name: "Suplezinc (Zinc + Cuivre)",
            nutrientID: .zinc,
            brand: "Ineldea (ISN)",
            dosage: "15 mg zinc + 1 mg cuivre",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 12.90,
            unitsPerPackage: 60,
            productURL: "https://www.isn-sante.com/fr/18037-suplezinc.html",
            isVegan: true,
            contraindications: [],
            antiInteractions: ["iron", "calcium"],
            tier: .value,
            whyBrand: "Zinc bisglycinate + cuivre (ratio 15:1) : le cuivre équilibre les cures de zinc prolongées."
        ),

        // --- IODE ---
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
        SupplementProduct(
            id: "iode-enova-budget",
            name: "Iode 150 µg (365 comprimés)",
            nutrientID: .iodine,
            brand: "Enova",
            dosage: "150 µg iodure de potassium",
            unitsPerDay: 1,
            timing: .matinRepas,
            price: 25.00,
            unitsPerPackage: 365,
            productURL: "https://www.laboratoiresenova.com/products/iode-150-mcg-365-petits-comprimes-iode-thyroide-fabrique-en-france-iodure-de-potassium-complement-alimentaire",
            isVegan: true,
            contraindications: [.hyperthyroidie],
            antiInteractions: [],
            tier: .value,
            whyBrand: "1 an de cure pour ~0,07 €/jour. Iodure de potassium à dosage précis, fabriqué en France."
        ),

        // --- FIBRES ---
        SupplementProduct(
            id: "fibres-trio-nutrico",
            name: "Fibres Bio (Acacia + Guar + Psyllium)",
            nutrientID: .fiber,
            brand: "Nutri&Co",
            dosage: "5,25 g fibres par dosette",
            unitsPerDay: 1,
            timing: .entreRepas,
            price: 19.90,
            unitsPerPackage: 28,
            productURL: "https://nutriandco.com/fr/produits/fibres-bio",
            isVegan: true,
            contraindications: [],
            antiInteractions: ["medicaments"],
            tier: .premium,
            whyBrand: "Trio de fibres solubles certifié Low-FODMAP, compatible intestins sensibles (SII)."
        ),
        SupplementProduct(
            id: "psyllium-blond-aromazone",
            name: "Psyllium Blond Bio",
            nutrientID: .fiber,
            brand: "Aroma-Zone",
            dosage: "5 g téguments de psyllium",
            unitsPerDay: 1,
            timing: .entreRepas,
            price: 6.90,
            unitsPerPackage: 60,
            productURL: "https://www.aroma-zone.com/product/complement-alimentaire-psyllium-blond-bio",
            isVegan: true,
            contraindications: [],
            antiInteractions: ["medicaments"],
            tier: .value,
            whyBrand: "Psyllium blond bio pur : fibre soluble de référence pour le transit. Toujours avec un grand verre d'eau."
        ),
    ]
}
