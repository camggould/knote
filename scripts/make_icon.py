#!/usr/bin/env python3
"""
Build a macOS app icon (.icns) from Icon/knote-source.png.

Applies the standard Big Sur icon grid: the artwork is scaled to 824×824 with
a rounded-rectangle (~22.37% radius) mask and centered on a 1024×1024 canvas
with transparent margins, so it renders as a native rounded-square rather than a
hard-edged full-bleed square. Then emits every required iconset size and runs
`iconutil` to produce Icon/AppIcon.icns.

Usage: python3 scripts/make_icon.py
"""
import pathlib
import subprocess
import tempfile
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Icon" / "knote-source.png"
OUT_ICNS = ROOT / "Icon" / "AppIcon.icns"

CANVAS = 1024
ART = 824                       # icon body size on the 1024 grid
MARGIN = (CANVAS - ART) // 2    # 100px
RADIUS = round(ART * 0.2237)    # Big Sur continuous-corner approximation
SS = 4                          # supersample factor for a crisp mask


def rounded_master() -> Image.Image:
    art = Image.open(SRC).convert("RGBA").resize((ART, ART), Image.LANCZOS)

    # Supersampled rounded-rect alpha mask for smooth edges.
    mask_hi = Image.new("L", (ART * SS, ART * SS), 0)
    ImageDraw.Draw(mask_hi).rounded_rectangle(
        [0, 0, ART * SS - 1, ART * SS - 1], radius=RADIUS * SS, fill=255)
    mask = mask_hi.resize((ART, ART), Image.LANCZOS)
    art.putalpha(mask)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(art, (MARGIN, MARGIN), art)
    return canvas


def main():
    master = rounded_master()
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    imgs = {s: master.resize((s, s), Image.LANCZOS) for s in sizes}

    # Standard iconset naming (base + @2x).
    entries = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for name, size in entries:
            imgs[size].save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(OUT_ICNS)],
            check=True)

    print(f"✓ wrote {OUT_ICNS}")


if __name__ == "__main__":
    main()
