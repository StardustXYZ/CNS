"""Draw the CNS icons: green headphones (#008000) on black.

Writes the icons of the web app into web/icons/ and those of the Android app into
mobile/android/app/src/main/res/: the classic icon (old Android versions), the two layers of
the adaptive icon (Android shapes it as a circle, squircle…), the single-colour version for
themed icons (Android 13+) and the small white icon of the notifications. The PNG files are
committed, so this runs only when the icon changes. Needs Pillow: pip install -e ".[icone]"

Usage:
    python tools/crea_icone.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONS_DIR = ROOT / "web" / "icons"
ANDROID_RES = ROOT / "mobile" / "android" / "app" / "src" / "main" / "res"
GREEN = (0, 128, 0, 255)  # #008000
BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)
SUPERSAMPLE = 4  # drawn bigger, then reduced: smooth edges

# Density folder -> scale (classic icon 48 px, adaptive layers 108 px at mdpi)
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def draw_headphones(size: int, scale: float = 1.0, background=BLACK, colour=GREEN) -> Image.Image:
    """Headphones on a square of ``background`` (CLEAR for the Android layers).

    ``scale`` < 1 keeps them inside the safe zone of the shaped icons, > 1 fills a small icon.
    """
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), background)
    draw = ImageDraw.Draw(img)
    unit = big / 512 * scale  # the drawing is designed on a 512 grid
    cx, cy = big / 2, big / 2 + 14 * unit

    def box(x0, y0, x1, y1):  # coordinates relative to the centre, in grid units
        return [cx + x0 * unit, cy + y0 * unit, cx + x1 * unit, cy + y1 * unit]

    # Headband: the upper half of a thick ring
    radius, band = 140, 34
    draw.arc(box(-radius - band / 2, -radius - band / 2, radius + band / 2, radius + band / 2),
             start=180, end=360, fill=colour, width=round(band * unit))
    # Short straight pieces from the band down into the ear cups
    draw.rectangle(box(-radius - band / 2, -2, -radius + band / 2, 30), fill=colour)
    draw.rectangle(box(radius - band / 2, -2, radius + band / 2, 30), fill=colour)
    # Ear cups
    cup_w, cup_top, cup_bottom = 82, 10, 150
    corner = round(30 * unit)
    for side in (-1, 1):
        x_mid = side * (radius + 4)
        draw.rounded_rectangle(box(x_mid - cup_w / 2, cup_top, x_mid + cup_w / 2, cup_bottom), radius=corner, fill=colour)
    return img.resize((size, size), Image.LANCZOS)


def classic(size: int) -> Image.Image:
    """The full icon of old Android versions: rounded black square with the headphones."""
    big = size * SUPERSAMPLE
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.22, fill=255)
    icon = Image.new("RGBA", (size, size), CLEAR)
    icon.paste(draw_headphones(size), (0, 0), mask.resize((size, size), Image.LANCZOS))
    return icon


def web_icons() -> None:
    ICONS_DIR.mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        draw_headphones(size).save(ICONS_DIR / f"icon-{size}.png", optimize=True)
    # Android crops "maskable" icons to a circle or a rounded shape: smaller drawing, same black
    draw_headphones(512, scale=0.78).save(ICONS_DIR / "icon-maskable-512.png", optimize=True)
    print(f"Icone del web salvate in {ICONS_DIR}")


def android_icons() -> None:
    for name, density in DENSITIES.items():
        folder = ANDROID_RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        classic(round(48 * density)).save(folder / "ic_launcher.png", optimize=True)
        layer = round(108 * density)
        Image.new("RGBA", (layer, layer), BLACK).save(folder / "ic_launcher_background.png", optimize=True)
        # Only the circle of 66 in the middle of 108 is always visible: the headphones stay inside it
        draw_headphones(layer, 0.62, background=CLEAR).save(folder / "ic_launcher_foreground.png", optimize=True)
        draw_headphones(layer, 0.62, background=CLEAR, colour=WHITE).save(
            folder / "ic_launcher_monochrome.png", optimize=True)
        # Notifications: 24 dp, white on transparent (Android colours it), almost edge to edge
        small = ANDROID_RES / f"drawable-{name}"
        small.mkdir(parents=True, exist_ok=True)
        draw_headphones(round(24 * density), 1.3, background=CLEAR, colour=WHITE).save(
            small / "ic_notifica.png", optimize=True)

    adaptive = ANDROID_RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    print(f"Icone di Android salvate in {ANDROID_RES}")


def main() -> None:
    web_icons()
    if ANDROID_RES.is_dir():
        android_icons()


if __name__ == "__main__":
    main()
