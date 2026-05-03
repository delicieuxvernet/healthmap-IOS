import Foundation

// MARK: - Supplement Catalog (extracted from SupplementEngine)
// Static product catalog ported from supplements-catalog.js.
// Read-only reference data — no logic here.

extension SupplementEngine {

    // ============================================================
    // STATIC PRODUCT CATALOG (ported from supplements-catalog.js)
    // ============================================================

    static let catalog: [SupplementProduct] = [

        // --- VITAMINE D ---
        SupplementProduct(
            id: "vitd3-k2-dynveo",
            name: "Vitamine D3 + K2 MK-7",
            nutrientID: .vitD,
            brand: "Dynveo",
            dosage: "2000 UI D3 + 75 mcg K2",
            timing: .matinRepas,
            price: 29,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["hypercalcemie"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Synergie D3+K2 dirige 83% du calcium vers les os. K2VITAL brevet de reference."
        ),
        SupplementProduct(
            id: "vitd3-nutrico",
            name: "Vitamine D3 Vegetale",
            nutrientID: .vitD,
            brand: "Nutri&Co",
            dosage: "1000 UI",
            timing: .matinRepas,
            price: 20,
            unitsPerPackage: 150,
            isVegan: true,
            contraindications: ["hypercalcemie"],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Meilleur rapport qualite-prix : ~0.13 EUR/jour pour 5 mois."
        ),

        // --- VITAMINE B12 ---
        SupplementProduct(
            id: "b12-methylcobalamine-nutrico",
            name: "Vitamine B12 Methylcobalamine",
            nutrientID: .vitB12,
            brand: "Nutri&Co",
            dosage: "1000 mcg methylcobalamine",
            timing: .matinRepas,
            price: 20,
            unitsPerPackage: 120,
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Forme bioactive directement utilisable, stabilisee par brevet MecobalActive."
        ),
        SupplementProduct(
            id: "b12-sublingual-jarrow",
            name: "B12 Sublinguale 5000 mcg",
            nutrientID: .vitB12,
            brand: "Jarrow Formulas",
            dosage: "5000 mcg sublinguale",
            timing: .matinAJeun,
            price: 16,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Haute dose pour phase de charge. Voie sublinguale contourne les problemes d'absorption."
        ),
        SupplementProduct(
            id: "b12-3-formes-dynveo",
            name: "Vitamine B12 Active (3 formes)",
            nutrientID: .vitB12,
            brand: "Dynveo",
            dosage: "1000 mcg (3 formes combinees)",
            timing: .matinRepas,
            price: 9,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "La seule formule combinant 3 formes bioactives : methyl, adenosyl, hydroxy."
        ),

        // --- FER ---
        SupplementProduct(
            id: "fer-bisglycinate-nutrico",
            name: "Fer Bisglycinate Ferrochel",
            nutrientID: .iron,
            brand: "Nutri&Co",
            dosage: "14 mg fer element + vit C + B9",
            timing: .matinAJeun,
            price: 19,
            unitsPerPackage: 30,
            isVegan: true,
            contraindications: ["hemochromatose", "grossesse"],
            antiInteractions: ["calcium", "zinc"],
            tier: .premium,
            whyBrand: "Formule la plus complete : fer chelate + probiotique + vit C + folate."
        ),
        SupplementProduct(
            id: "fer-bisglycinate-aromazone",
            name: "Fer Bisglycinate + Vitamine C",
            nutrientID: .iron,
            brand: "Aroma-Zone",
            dosage: "14 mg fer element + vit C",
            timing: .matinAJeun,
            price: 10,
            unitsPerPackage: 90,
            isVegan: true,
            contraindications: ["hemochromatose", "grossesse"],
            antiInteractions: ["calcium", "zinc"],
            tier: .value,
            whyBrand: "Meme matiere premiere Ferrochel que le premium, prix plus accessible."
        ),

        // --- MAGNESIUM ---
        SupplementProduct(
            id: "magnesium-3-formes-nutrico",
            name: "Le Magnesium (3 formes)",
            nutrientID: .magnesium,
            brand: "Nutri&Co",
            dosage: "300 mg Mg element (3 gelules)",
            timing: .soirRepas,
            price: 20,
            unitsPerPackage: 120,
            isVegan: true,
            contraindications: ["insuffisance_renale_severe"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "3 formes = 5 canaux d'absorption. B6 active facilite l'entree du Mg dans les cellules."
        ),
        SupplementProduct(
            id: "magnesium-sport-nutripure",
            name: "Magnesium Bisglycinate + Taurine",
            nutrientID: .magnesium,
            brand: "Nutripure",
            dosage: "240 mg Mg element",
            timing: .soirRepas,
            price: 19,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["insuffisance_renale_severe"],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Reference sport : bisglycinate + taurine pour retention Mg intracellulaire."
        ),

        // --- OMEGA-3 ---
        SupplementProduct(
            id: "omega3-epax-nutripure",
            name: "Omega-3 EPAX Haute Dose",
            nutrientID: .omega3,
            brand: "Nutripure",
            dosage: "1260 mg EPA + 900 mg DHA",
            timing: .midiRepas,
            price: 70,
            unitsPerPackage: 90,
            isVegan: false,   // huile de poisson
            contraindications: ["allergie_poisson"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Le plus dose du marche francais. Forme TG naturelle, TOTOX < 7."
        ),
        SupplementProduct(
            id: "omega3-dha-nutrico",
            name: "Omega-3 EPAX (DHA dominant)",
            nutrientID: .omega3,
            brand: "Nutri&Co",
            dosage: "750 mg DHA + 150 mg EPA",
            timing: .midiRepas,
            price: 20,
            unitsPerPackage: 120,
            isVegan: false,   // huile de poisson
            contraindications: ["allergie_poisson"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Meilleur choix si objectif cognitif : ratio DHA > EPA. Capsules Licaps zero oxydation."
        ),
        SupplementProduct(
            id: "omega3-algue-dynveo",
            name: "Omega-3 Vegetal (Algue)",
            nutrientID: .omega3,
            brand: "Dynveo",
            dosage: "250 mg DHA par capsule",
            timing: .midiRepas,
            price: 25,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "L'alternative vegan de reference. Zero contamination, DHA pur d'algue."
        ),

        // --- VITAMINE C ---
        SupplementProduct(
            id: "vitc-liposomale-dynveo",
            name: "Vitamine C Liposomale 1000 mg",
            nutrientID: .vitC,
            brand: "Dynveo",
            dosage: "1000 mg liposomale",
            timing: .matinRepas,
            price: 28,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["hemochromatose"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "Liposomale = ~90% biodisponibilite vs ~50% classique. Zero irritation gastrique."
        ),
        SupplementProduct(
            id: "vitc-qualic-nutripure",
            name: "Vitamine C Quali-C 750 mg",
            nutrientID: .vitC,
            brand: "Nutripure",
            dosage: "750 mg Quali-C",
            timing: .matinRepas,
            price: 14,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Meilleur rapport dose/prix : ~0.23 EUR/jour. Quali-C = reference de purete."
        ),

        // --- CALCIUM ---
        SupplementProduct(
            id: "calcium-lithothamne-nutrixeal",
            name: "Lithothamne (Calcium marin)",
            nutrientID: .calcium,
            brand: "Nutrixeal",
            dosage: "~400 mg calcium element",
            timing: .midiRepas,
            price: 15,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["hypercalcemie"],
            antiInteractions: ["iron", "zinc"],
            tier: .premium,
            whyBrand: "Calcium naturel le plus complet : algue marine avec 70+ cofacteurs mineraux."
        ),
        SupplementProduct(
            id: "calcium-d3-k2-argalys",
            name: "Calcium + D3 + K2",
            nutrientID: .calcium,
            brand: "Argalys",
            dosage: "500 mg calcium + D3 + K2",
            timing: .midiRepas,
            price: 14,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["hypercalcemie"],
            antiInteractions: ["iron", "zinc"],
            tier: .value,
            whyBrand: "Formule complete Ca+D3+K2 en un seul produit. Pratique et economique."
        ),

        // --- ZINC ---
        SupplementProduct(
            id: "zinc-bisglycinate-nutrico",
            name: "Zinc Bisglycinate TRAACS",
            nutrientID: .zinc,
            brand: "Nutri&Co",
            dosage: "15 mg zinc element",
            timing: .matinRepas,
            price: 13,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: ["iron", "calcium"],
            tier: .premium,
            whyBrand: "Forme bisglycinate TRAACS de reference. +43% bioavailable vs gluconate."
        ),
        SupplementProduct(
            id: "zinc-cuivre-isn",
            name: "Zinc Bisglycinate + Cuivre",
            nutrientID: .zinc,
            brand: "ISN",
            dosage: "15 mg zinc + 1 mg cuivre",
            timing: .matinRepas,
            price: 10,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: [],
            antiInteractions: ["iron", "calcium"],
            tier: .value,
            whyBrand: "Le seul a inclure le cuivre (ratio 15:1). Ideal pour cures longues."
        ),

        // --- IODE ---
        SupplementProduct(
            id: "iode-puresea-nutrico",
            name: "Iode PureSea (algue)",
            nutrientID: .iodine,
            brand: "Nutri&Co",
            dosage: "150 mcg (100% AR)",
            timing: .matinRepas,
            price: 13,
            unitsPerPackage: 60,
            isVegan: true,
            contraindications: ["hyperthyroidie"],
            antiInteractions: [],
            tier: .premium,
            whyBrand: "PureSea = algue standardisee a dosage constant (vs kelp generique variable)."
        ),
        SupplementProduct(
            id: "iode-enova-budget",
            name: "Iode 150 mcg (365 comprimes)",
            nutrientID: .iodine,
            brand: "Enova",
            dosage: "150 mcg iodure de potassium",
            timing: .matinRepas,
            price: 13,
            unitsPerPackage: 365,
            isVegan: true,
            contraindications: ["hyperthyroidie"],
            antiInteractions: [],
            tier: .value,
            whyBrand: "Meilleur rapport qualite-prix : 1 an pour ~13 EUR (~0.04 EUR/jour)."
        ),

        // --- FIBRES ---
        SupplementProduct(
            id: "fibres-trio-nutrico",
            name: "Fibres Bio (Acacia + Guar + Psyllium)",
            nutrientID: .fiber,
            brand: "Nutri&Co",
            dosage: "5.25 g fibres par dosette",
            timing: .entreRepas,
            price: 17,
            unitsPerPackage: 30,
            isVegan: true,
            contraindications: [],
            antiInteractions: ["medicaments"],
            tier: .premium,
            whyBrand: "Mix 3 fibres + certifie Low-FODMAP (compatible intestins sensibles)."
        ),
        SupplementProduct(
            id: "psyllium-blond-naturel",
            name: "Psyllium Blond Bio",
            nutrientID: .fiber,
            brand: "Nu3",
            dosage: "5 g par cuillere",
            timing: .entreRepas,
            price: 12,
            unitsPerPackage: 40,
            isVegan: true,
            contraindications: [],
            antiInteractions: ["medicaments"],
            tier: .value,
            whyBrand: "Le standard fibre soluble. Toujours avec 250 ml d'eau minimum."
        ),
    ]
}
