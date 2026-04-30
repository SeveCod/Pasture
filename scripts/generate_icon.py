#!/usr/bin/env python3
"""Generate Pasture app icon: sage-to-amber gradient background with a white leaf."""

from PIL import Image, ImageDraw, ImageFont
import math
import os
import subprocess
import tempfile

SIZE = 1024
CENTER = SIZE // 2
CORNER_RADIUS = int(SIZE * 0.22)

# Brand colors from DesignTokens.swift
SAGE = (139, 184, 138)       # #8BB88A
AMBER = (232, 148, 74)       # #E8944A
SAGE_DARK = (90, 140, 90)    # #5A8C5A
GRASS_DARK = (45, 107, 63)   # #2D6B3F


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_rounded_rect(draw, xy, radius, fill):
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def make_gradient(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size * 0.6 + y / size * 0.4)
            t = max(0.0, min(1.0, t))
            r, g, b = lerp_color(SAGE, AMBER, t)
            pixels[x, y] = (r, g, b, 255)
    return img


def draw_leaf(draw, cx, cy, scale):
    """Draw a stylized leaf shape using ellipses and lines."""
    leaf_h = int(420 * scale)
    leaf_w = int(260 * scale)
    stem_len = int(120 * scale)
    stem_w = int(14 * scale)
    vein_w = int(6 * scale)

    angle = -15

    img_leaf = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img_leaf)

    # Main leaf body (ellipse)
    leaf_top = cy - leaf_h // 2
    leaf_left = cx - leaf_w // 2
    d.ellipse(
        [leaf_left, leaf_top, leaf_left + leaf_w, leaf_top + leaf_h],
        fill=(255, 255, 255, 230)
    )

    # Leaf tip - make top pointy with a polygon overlay
    tip_y = leaf_top + int(leaf_h * 0.02)
    d.polygon(
        [(cx - leaf_w // 3, leaf_top + leaf_h // 4),
         (cx, tip_y),
         (cx + leaf_w // 3, leaf_top + leaf_h // 4)],
        fill=(255, 255, 255, 230)
    )

    # Central vein
    d.line(
        [(cx, leaf_top + int(leaf_h * 0.1)), (cx, leaf_top + int(leaf_h * 0.85))],
        fill=SAGE_DARK + (140,), width=vein_w
    )

    # Side veins
    for i in range(4):
        vy = leaf_top + int(leaf_h * (0.28 + i * 0.15))
        spread = int(leaf_w * (0.28 - i * 0.03))
        offset_y = int(40 * scale)
        d.line([(cx, vy), (cx - spread, vy - offset_y)],
               fill=SAGE_DARK + (100,), width=max(2, vein_w - 2))
        d.line([(cx, vy), (cx + spread, vy - offset_y)],
               fill=SAGE_DARK + (100,), width=max(2, vein_w - 2))

    # Stem
    stem_top = leaf_top + int(leaf_h * 0.82)
    stem_bottom = stem_top + stem_len
    d.line([(cx, stem_top), (cx + int(20 * scale), stem_bottom)],
           fill=GRASS_DARK + (200,), width=stem_w)

    # Rotate the leaf slightly
    img_leaf = img_leaf.rotate(angle, center=(cx, cy), resample=Image.BICUBIC)
    return img_leaf


def generate_icon():
    # Gradient background
    gradient = make_gradient(SIZE)

    # Apply rounded rectangle mask
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=CORNER_RADIUS, fill=255)
    gradient.putalpha(mask)

    # Subtle inner shadow / depth
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    # Slight darkening at bottom
    for y in range(SIZE // 2, SIZE):
        t = (y - SIZE // 2) / (SIZE // 2)
        alpha = int(30 * t * t)
        overlay_draw.line([(0, y), (SIZE, y)], fill=(0, 0, 0, alpha))
    gradient = Image.alpha_composite(gradient, overlay)
    gradient.putalpha(mask)

    # Draw leaf
    leaf = draw_leaf(ImageDraw.Draw(Image.new("RGBA", (SIZE, SIZE))),
                     CENTER, CENTER - int(SIZE * 0.02), 1.0)
    # Actually redraw properly
    leaf_img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    leaf_draw = ImageDraw.Draw(leaf_img)

    # Leaf parameters
    cx, cy = CENTER, CENTER - int(SIZE * 0.02)
    scale = 1.0
    leaf_h = int(420 * scale)
    leaf_w = int(260 * scale)
    stem_w = int(14 * scale)
    vein_w = int(6 * scale)

    leaf_top = cy - leaf_h // 2
    leaf_left = cx - leaf_w // 2

    # Main leaf
    leaf_draw.ellipse(
        [leaf_left, leaf_top, leaf_left + leaf_w, leaf_top + leaf_h],
        fill=(255, 255, 255, 230)
    )

    # Pointy tip
    leaf_draw.polygon(
        [(cx - leaf_w // 3, leaf_top + leaf_h // 4),
         (cx, leaf_top - int(leaf_h * 0.05)),
         (cx + leaf_w // 3, leaf_top + leaf_h // 4)],
        fill=(255, 255, 255, 230)
    )

    # Central vein
    leaf_draw.line(
        [(cx, leaf_top + int(leaf_h * 0.05)), (cx, leaf_top + int(leaf_h * 0.85))],
        fill=SAGE_DARK + (140,), width=vein_w
    )

    # Side veins
    for i in range(4):
        vy = leaf_top + int(leaf_h * (0.28 + i * 0.15))
        spread = int(leaf_w * (0.28 - i * 0.03))
        offset_y = int(40 * scale)
        leaf_draw.line([(cx, vy), (cx - spread, vy - offset_y)],
                       fill=SAGE_DARK + (100,), width=max(2, vein_w - 2))
        leaf_draw.line([(cx, vy), (cx + spread, vy - offset_y)],
                       fill=SAGE_DARK + (100,), width=max(2, vein_w - 2))

    # Stem
    stem_top = leaf_top + int(leaf_h * 0.82)
    stem_bottom = stem_top + int(120 * scale)
    leaf_draw.line([(cx, stem_top), (cx + int(20 * scale), stem_bottom)],
                   fill=GRASS_DARK + (200,), width=stem_w)

    # Rotate leaf
    leaf_img = leaf_img.rotate(-15, center=(cx, cy), resample=Image.BICUBIC)

    # Composite
    result = Image.alpha_composite(gradient, leaf_img)
    result.putalpha(mask)

    return result


def create_icns(icon_img, output_path):
    """Create .icns from a 1024x1024 PIL Image using iconutil."""
    iconset_dir = tempfile.mkdtemp(suffix=".iconset")

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = icon_img.resize((s, s), Image.LANCZOS)
        # Standard resolution
        if s <= 512:
            resized.save(os.path.join(iconset_dir, f"icon_{s}x{s}.png"))
        # @2x versions
        if s >= 32:
            half = s // 2
            if half in [16, 32, 64, 128, 256, 512]:
                resized.save(os.path.join(iconset_dir, f"icon_{half}x{half}@2x.png"))

    # Rename iconset dir to have .iconset extension
    iconset_path = iconset_dir  # already has suffix
    os.rename(iconset_dir, iconset_dir)  # noop, already correct name

    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", output_path], check=True)

    # Cleanup
    for f in os.listdir(iconset_dir):
        os.remove(os.path.join(iconset_dir, f))
    os.rmdir(iconset_dir)


if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)

    icon = generate_icon()

    # Save PNG for reference
    png_path = os.path.join(project_dir, "AppIcon.png")
    icon.save(png_path)
    print(f"PNG saved: {png_path}")

    # Create .icns
    icns_path = os.path.join(project_dir, "AppIcon.icns")
    create_icns(icon, icns_path)
    print(f"ICNS saved: {icns_path}")
