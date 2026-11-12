"""Draw the CNS icons: green headphones (#008000) on black.

The PNG files are saved in web/icons/ and committed, so this runs only when the icon
changes. Needs Pillow: pip install -e ".[icone]"

Usage:
    python tools/crea_icone.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ICONS_DIR = Path(__file__).resolve().parent.parent / "web" / "icons"
GREEN = (0, 128, 0, 255)  # #008000
BLACK = (0, 0, 0, 255)
SUPERSAMPLE = 4  # drawn bigger, then reduced: smooth edges


def draw_headphones(size: int, scale: float = 1.0) -> Image.Image:
    """Headphones on a black square; ``scale`` < 1 keeps them inside the maskable safe zone."""
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), BLACK)
    draw = ImageDraw.Draw(img)
    unit = big / 512 * scale  # the drawing is designed on a 512 grid
    cx, cy = big / 2, big / 2 + 14 * unit

    def box(x0, y0, x1, y1):  # coordinates relative to the centre, in grid units
        return [cx + x0 * unit, cy + y0 * unit, cx + x1 * unit, cy + y1 * unit]

    # Headband: the upper half of a thick ring
    radius, band = 140, 34
    draw.arc(box(-radius - band / 2, -radius - band / 2, radius + band / 2, radius + band / 2),
             start=180, end=360, fill=GREEN, width=round(band * unit))
    # Short straight pieces from the band down into the ear cups
    draw.rectangle(box(-radius - band / 2, -2, -radius + band / 2, 30), fill=GREEN)
    draw.rectangle(box(radius - band / 2, -2, radius + band / 2, 30), fill=GREEN)
    # Ear cups
    cup_w, cup_top, cup_bottom = 82, 10, 150
    corner = round(30 * unit)
    for side in (-1, 1):
        x_mid = side * (radius + 4)
        draw.rounded_rectangle(box(x_mid - cup_w / 2, cup_top, x_mid + cup_w / 2, cup_bottom), radius=corner, fill=GREEN)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    ICONS_DIR.mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        draw_headphones(size).save(ICONS_DIR / f"icon-{size}.png", optimize=True)
    # Android crops "maskable" icons to a circle or a rounded shape: smaller drawing, same black
    draw_headphones(512, scale=0.78).save(ICONS_DIR / "icon-maskable-512.png", optimize=True)
    print(f"Icone salvate in {ICONS_DIR}")


if __name__ == "__main__":
    main()
