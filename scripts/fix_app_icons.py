#!/usr/bin/env python3
"""
Crop TRA mockup PNGs to the actual icon content, pad to square, export 1024x1024.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

FILL = (0, 37, 31)  # #00251F


def rider_crop_bounds(im: Image.Image) -> tuple[int, int, int, int]:
    px = im.load()
    w, h = im.size

    def is_teal_bg(r: int, g: int, b: int) -> bool:
        return r < 55 and g < 110 and b < 100 and (r + g + b) < 220 and g > 5

    def is_white(r: int, g: int, b: int) -> bool:
        return r > 248 and g > 248 and b > 248

    minx, miny = w, h
    maxx, maxy = 0, 0

    for y in range(h):
        xs = [x for x in range(w) if is_teal_bg(*px[x, y][:3])]
        if len(xs) < 200:
            continue
        minx = min(minx, min(xs))
        maxx = max(maxx, max(xs))
        miny = min(miny, y)
        maxy = max(maxy, y)

    for y in range(miny, maxy + 1):
        for x in range(w):
            if is_white(*px[x, y][:3]):
                minx = min(minx, x)
                maxx = max(maxx, x)

    return minx, miny, maxx, maxy


def driver_crop_bounds(im: Image.Image) -> tuple[int, int, int, int]:
    px = im.load()
    w, h = im.size

    def is_inner(r: int, g: int, b: int) -> bool:
        return r < 20 and g < 50 and b < 45 and (r + g + b) < 120

    def is_white(r: int, g: int, b: int) -> bool:
        return r > 240 and g > 235

    def is_accent(r: int, g: int, b: int) -> bool:
        return r < 100 and g > 160 and b > 140

    minx, miny = w, h
    maxx, maxy = 0, 0
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if is_inner(r, g, b) or is_white(r, g, b) or is_accent(r, g, b):
                minx = min(minx, x)
                miny = min(miny, y)
                maxx = max(maxx, x)
                maxy = max(maxy, y)
    return minx, miny, maxx, maxy


def pad_to_square(im: Image.Image, fill: tuple[int, int, int]) -> Image.Image:
    w, h = im.size
    side = max(w, h)
    out = Image.new("RGB", (side, side), fill)
    ox = (side - w) // 2
    oy = (side - h) // 2
    out.paste(im, (ox, oy))
    return out


def remove_mockup_bleed(im: Image.Image, fill: tuple[int, int, int]) -> Image.Image:
    """Replace blurred iPhone-home grey that shows through rounded corners."""
    px = im.load()
    w, h = im.size
    out = im.copy()
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            # Typical mockup background behind the squircle
            if r > 95 and g > 125 and b > 135 and r < 200:
                opx[x, y] = fill
    return out


def process_rider(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    x0, y0, x1, y1 = rider_crop_bounds(im)
    cropped = im.crop((x0, y0, x1 + 1, y1 + 1))
    cropped = remove_mockup_bleed(cropped, FILL)
    square = pad_to_square(cropped, FILL)
    square.resize((1024, 1024), Image.LANCZOS).save(dst, "PNG")


def process_driver(src: Path, dst: Path) -> None:
    im = Image.open(src).convert("RGB")
    x0, y0, x1, y1 = driver_crop_bounds(im)
    cropped = im.crop((x0, y0, x1 + 1, y1 + 1))
    square = pad_to_square(cropped, FILL)
    square.resize((1024, 1024), Image.LANCZOS).save(dst, "PNG")


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    assets = Path.home() / ".cursor/projects/Users-raffaelloclarck-Desktop-True-Road-Adventures/assets"
    rider_src = assets / "AppIcon_TRA_dark.png"
    driver_src = assets / "AppIcon_TRA_driver.png"

    ios = root / "True Road Adventures/Resources/Assets.xcassets"
    process_rider(rider_src, ios / "AppIcon.appiconset/AppIcon.png")
    process_rider(rider_src, ios / "RiderAppIcon.appiconset/RiderAppIcon.png")
    process_driver(driver_src, ios / "DriverAppIcon.appiconset/DriverAppIcon.png")

    # Android: regenerate mipmaps from fixed 1024 sources
    try:
        from PIL import ImageDraw

        android = Path.home() / "AndroidStudioProjects/TrueRoadAdventures/app/src"
        sizes = {
            "mipmap-mdpi": 48,
            "mipmap-hdpi": 72,
            "mipmap-xhdpi": 96,
            "mipmap-xxhdpi": 144,
            "mipmap-xxxhdpi": 192,
        }

        def round_icon(img: Image.Image, size: int) -> Image.Image:
            img = img.resize((size, size), Image.LANCZOS).convert("RGBA")
            mask = Image.new("L", (size, size), 0)
            ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
            out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            out.paste(img, mask=mask)
            return out

        rider_1024 = Image.open(ios / "RiderAppIcon.appiconset/RiderAppIcon.png").convert("RGB")
        driver_1024 = Image.open(ios / "DriverAppIcon.appiconset/DriverAppIcon.png").convert("RGB")

        for flavor, base in [("customer", rider_1024), ("driver", driver_1024)]:
            res = android / flavor / "res"
            for folder, dim in sizes.items():
                d = res / folder
                d.mkdir(parents=True, exist_ok=True)
                sq = base.resize((dim, dim), Image.LANCZOS)
                sq.save(d / "ic_launcher.png", "PNG")
                round_icon(base, dim).save(d / "ic_launcher_round.png", "PNG")

        main_res = android / "main/res"
        for folder, dim in sizes.items():
            d = main_res / folder
            d.mkdir(parents=True, exist_ok=True)
            sq = rider_1024.resize((dim, dim), Image.LANCZOS)
            sq.save(d / "ic_launcher.png", "PNG")
            round_icon(rider_1024, dim).save(d / "ic_launcher_round.png", "PNG")
    except Exception as e:
        print("Android skip:", e)

    print("Done: iOS icons + Android mipmaps updated.")


if __name__ == "__main__":
    main()
