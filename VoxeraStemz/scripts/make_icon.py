#!/usr/bin/env python3
"""Build opaque Voxera Stemz icons from the supplied logo.

The source is a rounded black tile on a square canvas. Pixels outside that
tile become pure black (#000). The VX mark, white slash, VOXERA word and
STEMZ word stay pixel-identical. PNGs are RGB, with no alpha channel.
"""
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Artwork" / "voxera-stemz-logo.jpg"
APPICON = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND = ROOT / "Resources" / "Assets.xcassets" / "BrandLogo.imageset"
LAUNCH = ROOT / "Resources" / "Assets.xcassets" / "LaunchBackground.colorset"

# Outer edge of the grey rim, expanded a few pixels so the rim and the
# artwork stay inside. Measured on the 1500x1500 master.
LEFT, TOP, RIGHT, BOTTOM = 16, 18, 1472, 1474
RADIUS = 396

SIZES = {
    "icon-20.png": 20,
    "icon-29.png": 29,
    "icon-40.png": 40,
    "icon-20@2x.png": 40,
    "icon-20@3x.png": 60,
    "icon-29@2x.png": 58,
    "icon-29@3x.png": 87,
    "icon-40@2x.png": 80,
    "icon-40@3x.png": 120,
    "icon-60@2x.png": 120,
    "icon-76.png": 76,
    "icon-76@2x.png": 152,
    "icon-83.5@2x.png": 167,
    "icon-60@3x.png": 180,
    "icon-1024.png": 1024,
}


def contains(x, y, left, top, right, bottom, radius):
    if x < left or y < top or x > right or y > bottom:
        return False
    cx0 = left + radius
    cy0 = top + radius
    cx1 = right - radius
    cy1 = bottom - radius
    if x < cx0 and y < cy0:
        return (x - cx0) ** 2 + (y - cy0) ** 2 <= radius ** 2
    if x > cx1 and y < cy0:
        return (x - cx1) ** 2 + (y - cy0) ** 2 <= radius ** 2
    if x < cx0 and y > cy1:
        return (x - cx0) ** 2 + (y - cy1) ** 2 <= radius ** 2
    if x > cx1 and y > cy1:
        return (x - cx1) ** 2 + (y - cy1) ** 2 <= radius ** 2
    return True


def fill_outside(image, left, top, right, bottom, radius):
    filled = image.copy()
    pixels = filled.load()
    source = image.load()
    width, height = image.size
    changed = 0
    for y in range(height):
        for x in range(width):
            if contains(x + 0.5, y + 0.5, left, top, right, bottom, radius):
                if pixels[x, y] != source[x, y]:
                    raise SystemExit(f"inside pixel changed at {x},{y}")
                continue
            if pixels[x, y] != (0, 0, 0):
                changed += 1
            pixels[x, y] = (0, 0, 0)
    return filled, changed


def png_color_type(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path.name} is not a PNG")
    length, kind = struct.unpack(">I4s", data[8:16])
    if kind != b"IHDR":
        raise SystemExit(f"{path.name} missing IHDR")
    ihdr = data[16 : 16 + length]
    return ihdr[9]


def save_rgb(image, path):
    rgb = image.convert("RGB")
    if rgb.mode != "RGB":
        raise SystemExit(rgb.mode)
    rgb.save(path, "PNG")
    color_type = png_color_type(path)
    if color_type != 2:
        raise SystemExit(f"{path.name} color type {color_type}, expected RGB (2)")
    return rgb


def contents():
    rows = [
        ("20x20", "iphone", "2x", "icon-20@2x.png"),
        ("20x20", "iphone", "3x", "icon-20@3x.png"),
        ("29x29", "iphone", "2x", "icon-29@2x.png"),
        ("29x29", "iphone", "3x", "icon-29@3x.png"),
        ("40x40", "iphone", "2x", "icon-40@2x.png"),
        ("40x40", "iphone", "3x", "icon-40@3x.png"),
        ("60x60", "iphone", "2x", "icon-60@2x.png"),
        ("60x60", "iphone", "3x", "icon-60@3x.png"),
        ("20x20", "ipad", "1x", "icon-20.png"),
        ("20x20", "ipad", "2x", "icon-20@2x.png"),
        ("29x29", "ipad", "1x", "icon-29.png"),
        ("29x29", "ipad", "2x", "icon-29@2x.png"),
        ("40x40", "ipad", "1x", "icon-40.png"),
        ("40x40", "ipad", "2x", "icon-40@2x.png"),
        ("76x76", "ipad", "1x", "icon-76.png"),
        ("76x76", "ipad", "2x", "icon-76@2x.png"),
        ("83.5x83.5", "ipad", "2x", "icon-83.5@2x.png"),
        ("1024x1024", "ios-marketing", "1x", "icon-1024.png"),
    ]
    images = []
    for size, idiom, scale, filename in rows:
        images.append(
            f'    {{"size":"{size}","idiom":"{idiom}","filename":"{filename}","scale":"{scale}"}}'
        )
    body = ",\n".join(images)
    return (
        '{\n  "images" : [\n'
        + body
        + '\n  ],\n  "info" : {"author":"xcode","version":1}\n}\n'
    )


def main():
    source = Image.open(SOURCE).convert("RGB")
    width, height = source.size
    if (width, height) != (1500, 1500):
        raise SystemExit(f"expected 1500x1500, got {source.size}")
    master, changed = fill_outside(source, LEFT, TOP, RIGHT, BOTTOM, RADIUS)
    pixels = master.load()
    original = source.load()
    for point in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)):
        if pixels[point] != (0, 0, 0):
            raise SystemExit(f"corner {point} is {pixels[point]}")
    # White slash near the middle and a blue VX sample must be untouched.
    samples = [(750, 750), (430, 620), (980, 620), (750, 980), (750, 1120)]
    for point in samples:
        if pixels[point] != original[point]:
            raise SystemExit(f"artwork changed at {point}")
        if not contains(point[0] + 0.5, point[1] + 0.5, LEFT, TOP, RIGHT, BOTTOM, RADIUS):
            raise SystemExit(f"sample {point} fell outside the tile")
    print(f"master {width}x{height}, exterior pixels set to black: {changed}")

    APPICON.mkdir(parents=True, exist_ok=True)
    BRAND.mkdir(parents=True, exist_ok=True)
    scale = width
    for name, size in SIZES.items():
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        factor = size / scale
        resized, _ = fill_outside(
            resized,
            LEFT * factor,
            TOP * factor,
            RIGHT * factor,
            BOTTOM * factor,
            RADIUS * factor,
        )
        saved = save_rgb(resized, APPICON / name)
        corner = saved.getpixel((0, 0))
        if corner != (0, 0, 0):
            raise SystemExit(f"{name} corner {corner}")
    save_rgb(master.resize((256, 256), Image.Resampling.LANCZOS), BRAND / "brand-logo@2x.png")
    save_rgb(master.resize((384, 384), Image.Resampling.LANCZOS), BRAND / "brand-logo@3x.png")
    (APPICON / "Contents.json").write_text(contents())
    (BRAND / "Contents.json").write_text(
        """{
  "images" : [
    {"idiom":"universal","scale":"2x","filename":"brand-logo@2x.png"},
    {"idiom":"universal","scale":"3x","filename":"brand-logo@3x.png"}
  ],
  "info" : {"author":"xcode","version":1}
}
"""
    )
    LAUNCH.mkdir(parents=True, exist_ok=True)
    (LAUNCH / "Contents.json").write_text(
        """{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {"alpha":"1.000","blue":"0.000","green":"0.000","red":"0.000"}
      },
      "idiom" : "universal"
    }
  ],
  "info" : {"author":"xcode","version":1}
}
"""
    )
    (ROOT / "Resources" / "Assets.xcassets" / "Contents.json").write_text(
        '{ "info" : {"author":"xcode","version":1} }\n'
    )
    print("icons ok")


if __name__ == "__main__":
    main()
