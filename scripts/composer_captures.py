"""Compose les captures de la fiche App Store (1290 x 2796, iPhone 6,9 / 6,7 pouces).

Chaque capture : fond dégradé aux couleurs de Kiwio, un titre vendeur sur deux
lignes (la seconde en vert), une ligne de sous-titre, et le vrai écran de l'app
(capture simulateur du workflow screenshots.yml) dans un iPhone qui déborde en
bas. Style validé par Arthur le 12 oct. 2026 (maquette 4).

Usage : python scripts/composer_captures.py <dossier_captures_brutes> <dossier_sortie>
Les écrans et les textes sont listés dans PLANCHES ci-dessous.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

L, H = 1290, 2796

# (fichier de sortie, capture brute, ligne 1, ligne 2 (verte), sous-titre, teinte du fond)
PLANCHES = [
    ("01_dictee", "09-dictee-un-toucher", "Dis ce que tu as mangé.", "C'est déjà compté.",
     "Calories, macros et 26 vitamines et minéraux", "vert"),
    ("02_journal", "v6-journal", "Ta journée,", "en un coup d'œil.",
     "Calories, macros, eau et poids au même endroit", "peche"),
    ("03_bilan", "89-bilan-ressenti", "Un bilan qui te", "connaît vraiment.",
     "Ressenti, sommeil, soleil, sport : une question à la fois", "lilas"),
    ("04_journee_type", "96-bilan-repas-b-midi", "Ta journée type,", "repas par repas.",
     "Kiwio part de ce que tu manges vraiment", "vert"),
    ("05_fiche_apport", "v6-fiche-apport", "Le pourquoi,", "et quoi faire.",
     "Pour chacun de tes dix apports clés", "peche"),
    ("06_plan", "30-plan", "Ce que tu ressens,", "relié à ton assiette.",
     "Ton plan, pour savoir par où commencer", "ciel"),
    ("07_unites", "v6-unites", "Des portions", "qui te parlent.",
     "Pièce, poignée, carré : pas besoin de balance", "peche"),
    ("08_complements", "v6-complements", "Des conseils", "sans parti pris.",
     "Aucune commission, aucun partenariat", "vert"),
]

FONDS = {
    "vert": ((226, 241, 205), (247, 250, 236)),
    "peche": ((252, 228, 205), (250, 246, 234)),
    "ciel": ((214, 236, 246), (244, 249, 240)),
    "lilas": ((232, 226, 247), (247, 246, 238)),
}
ENCRE = (31, 58, 12)
VERT = (73, 145, 26)
GRIS = (74, 92, 58)

POLICES = Path("C:/Windows/Fonts")


def police(nom, taille):
    return ImageFont.truetype(str(POLICES / nom), taille)


def fond(teinte):
    haut, bas = FONDS[teinte]
    image = Image.new("RGB", (L, H))
    trait = ImageDraw.Draw(image)
    for y in range(H):
        t = y / (H - 1)
        couleur = tuple(round(haut[i] + (bas[i] - haut[i]) * t) for i in range(3))
        trait.line([(0, y), (L, y)], fill=couleur)
    # Deux halos doux, comme le fond vivant de l'app.
    halo = Image.new("L", (L, H), 0)
    ImageDraw.Draw(halo).ellipse((-300, 1300, 900, 2500), fill=90)
    ImageDraw.Draw(halo).ellipse((700, -200, 1600, 800), fill=70)
    halo = halo.filter(ImageFilter.GaussianBlur(220))
    blanc = Image.new("RGB", (L, H), (255, 255, 255))
    return Image.composite(blanc, image, halo)


def centrer(trait, y, texte, fonte, couleur):
    largeur = trait.textlength(texte, font=fonte)
    trait.text(((L - largeur) / 2, y), texte, font=fonte, fill=couleur)


def titre_qui_tient(trait, lignes, taille_max=118):
    taille = taille_max
    while taille > 70:
        fonte = police("seguibl.ttf", taille)
        if all(trait.textlength(l, font=fonte) <= L - 140 for l in lignes):
            return fonte
        taille -= 4
    return police("seguibl.ttf", taille)


def telephone(ecran):
    """L'écran dans un iPhone : coins arrondis, cadre noir, ombre douce."""
    largeur = 1010
    ecran = ecran.convert("RGB").resize((largeur, round(ecran.height * largeur / ecran.width)), Image.LANCZOS)
    cadre = 26
    rayon = 132
    w, h = ecran.width + 2 * cadre, ecran.height + 2 * cadre
    tel = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    masque_tel = Image.new("L", (w, h), 0)
    ImageDraw.Draw(masque_tel).rounded_rectangle((0, 0, w - 1, h - 1), rayon + cadre, fill=255)
    tel.paste((22, 22, 24, 255), (0, 0), masque_tel)
    masque_ecran = Image.new("L", ecran.size, 0)
    ImageDraw.Draw(masque_ecran).rounded_rectangle((0, 0, ecran.width - 1, ecran.height - 1), rayon, fill=255)
    tel.paste(ecran, (cadre, cadre), masque_ecran)
    return tel


# Écrans dont le haut est vide (feuille à moitié ouverte) : part de la hauteur
# retirée en haut avant de poser l'écran dans l'iPhone.
RECADRAGE = {}


def composer(brute, l1, l2, sous_titre, teinte, recadrage=0.0):
    image = fond(teinte).convert("RGBA")
    trait = ImageDraw.Draw(image)
    fonte = titre_qui_tient(trait, [l1, l2])
    hauteur_ligne = round(fonte.size * 1.12)
    y = 170
    centrer(trait, y, l1, fonte, ENCRE)
    centrer(trait, y + hauteur_ligne, l2, fonte, VERT)
    centrer(trait, y + 2 * hauteur_ligne + 36, sous_titre, police("seguisb.ttf", 50), GRIS)

    ecran = Image.open(brute)
    if recadrage:
        ecran = ecran.crop((0, round(ecran.height * recadrage), ecran.width, ecran.height))
    tel = telephone(ecran)
    haut_tel = y + 2 * hauteur_ligne + 160
    ombre = Image.new("RGBA", image.size, (0, 0, 0, 0))
    x = (L - tel.width) // 2
    ImageDraw.Draw(ombre).rounded_rectangle((x + 10, haut_tel + 30, x + tel.width - 10, haut_tel + tel.height + 30),
                                            150, fill=(40, 60, 20, 70))
    ombre = ombre.filter(ImageFilter.GaussianBlur(40))
    image = Image.alpha_composite(image, ombre)
    image.alpha_composite(tel, (x, haut_tel))
    return image.convert("RGB")


def main():
    source, sortie = Path(sys.argv[1]), Path(sys.argv[2])
    sortie.mkdir(parents=True, exist_ok=True)
    for nom, brute, l1, l2, sous_titre, teinte in PLANCHES:
        candidats = sorted(source.rglob(f"*{brute}*.png"))
        if not candidats:
            print(f"MANQUE {brute}")
            continue
        composer(candidats[0], l1, l2, sous_titre, teinte, RECADRAGE.get(nom, 0.0)).save(sortie / f"final_{nom}.png", optimize=True)
        print(f"OK {nom} <- {candidats[0].name}")


if __name__ == "__main__":
    main()
