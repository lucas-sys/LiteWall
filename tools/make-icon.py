#!/usr/bin/env python3
"""Render the LiteWall app icon and build AppIcon.icns.

The emblem is drawn programmatically so that every pixel is original and the
small-size variants stay crisp: a flying sword (飞剑) in a wisp of spiritual
energy (灵气), standing on a magic formation (法阵), with one cinnabar elixir
pill (丹药) as the single warm accent. No official artwork, character likeness
or logo is referenced.

Layout follows the macOS Big Sur icon grid: a 1024x1024 canvas whose content
occupies a centred 824x824 squircle (superellipse, exponent 5).

Small sizes get a dedicated treatment: a slender blade plus a thin hilt
dissolves into noise below 64 px, so the 16/32 px variants use a shorter,
bolder blade, a wider guard, no hilt and a brighter edge.

Usage:
    python3 tools/make-icon.py                 # master + iconset + icns
    python3 tools/make-icon.py --variant light # light-background variant
    python3 tools/make-icon.py --preview        # also write small-size proofs
"""

from __future__ import annotations

import argparse
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ASSETS = PROJECT_ROOT / "Assets"

CANVAS = 1024          # exported master canvas
CONTENT = 824          # content box inside the canvas (macOS Big Sur grid)
SS = 2                 # supersampling factor for the master
SS_SMALL = 4           # supersampling for the tiny variants

# --- palette ---------------------------------------------------------------
DARK = {
    "bg_top": (5, 9, 16),
    "bg_bottom": (16, 30, 47),
    "halo": (26, 92, 96),
    "qi": (79, 214, 201),
    "qi_dim": (47, 169, 160),
    "blade_top": (247, 251, 253),
    "blade_bottom": (172, 194, 207),
    "gold": (236, 196, 132),
    "gold_dark": (194, 148, 88),
    "hilt": (58, 150, 146),
    "hilt_dark": (28, 88, 90),
    "pill": (226, 80, 60),
    "pill_light": (255, 152, 126),
}

LIGHT = {
    "bg_top": (243, 247, 250),
    "bg_bottom": (206, 224, 232),
    "halo": (168, 214, 214),
    "qi": (18, 122, 118),
    "qi_dim": (26, 138, 132),
    "blade_top": (32, 52, 70),
    "blade_bottom": (96, 122, 138),
    "gold": (176, 126, 44),
    "gold_dark": (140, 96, 30),
    "hilt": (20, 96, 94),
    "hilt_dark": (10, 60, 62),
    "pill": (198, 58, 40),
    "pill_light": (232, 112, 88),
}

# --- emblem geometry, in content coordinates (0..CONTENT) --------------------
BLADE_TOP = 138
BLADE_GUARD = 548
BLADE_HALF_WIDTH = 32.0
GUARD_HALF = 98.0
GUARD_HEIGHT = 18
HILT_HALF = 11.0
BLADE_CX = 412.0

RIBBON = [  # cubic segments of the 灵气 ribbon
    ((452, 182), (610, 226), (614, 392), (300, 432)),
    ((300, 432), (112, 460), (176, 566), (332, 574)),
]
RIBBON_WIDTH = 15.0

FORMATION_CX = 412.0
FORMATION_CY = 688.0
FORMATION_RX = 250.0
FORMATION_RY = 58.0

PILL_CX = 556.0
PILL_CY = 166.0
PILL_R = 32.0


def cubic_points(p0, c1, c2, p3, steps=260):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * c1[0] + 3 * mt * t**2 * c2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * c1[1] + 3 * mt * t**2 * c2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def superellipse_mask(size: int, exponent: float = 5.0, samples: int = 1440) -> Image.Image:
    """Apple-style squircle: |x/a|^n + |y/a|^n <= 1."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    a = size / 2.0
    pts = []
    for i in range(samples):
        t = 2 * math.pi * i / samples
        ct, st = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(ct) ** (2.0 / exponent), ct)
        y = a * math.copysign(abs(st) ** (2.0 / exponent), st)
        pts.append((x + a, y + a))
    draw.polygon(pts, fill=255)
    return mask


def vertical_gradient(size: int, top, bottom) -> Image.Image:
    strip = Image.new("RGB", (1, size))
    px = strip.load()
    for y in range(size):
        t = y / max(1, size - 1)
        px[0, y] = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(3))
    return strip.resize((size, size), Image.BILINEAR)


def radial_glow(size: int, color, alpha: int) -> Image.Image:
    """Soft radial light centred in the frame, returned as an RGBA layer."""
    # Image.radial_gradient is black in the centre; invert so the light peaks there.
    grad = Image.radial_gradient("L").resize((size, size), Image.BILINEAR)
    grad = grad.point(lambda v: int((255 - v) * alpha / 255))
    layer = Image.new("RGBA", (size, size), color + (0,))
    mask = Image.new("L", (size, size), 0)
    mask.paste(grad, (0, 0))
    layer.putalpha(mask)
    return layer


def ribbon_polygon(points, half_width: float):
    """Turn a polyline into a tapered ribbon polygon (both ends taper to a point)."""
    left, right = [], []
    n = len(points)
    for i, (x, y) in enumerate(points):
        t = i / max(1, n - 1)
        if i == 0:
            dx, dy = points[1][0] - x, points[1][1] - y
        elif i == n - 1:
            dx, dy = x - points[-2][0], y - points[-2][1]
        else:
            dx, dy = points[i + 1][0] - points[i - 1][0], points[i + 1][1] - points[i - 1][1]
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        w = half_width * (math.sin(math.pi * t) ** 0.55)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    return left + right[::-1]


def render(target: int, palette: dict, simplified: bool, flat: bool = False) -> Image.Image:
    """Draw the emblem at `target` pixels square.

    `flat=True` omits the squircle mask and the drop shadow and lets the art
    fill the whole canvas: macOS 26+ draws a glass squircle container itself,
    so a pre-rounded icon would end up nested inside a second container.
    """
    ss = SS_SMALL if target <= 64 else SS
    canvas_px = target * ss
    if flat:
        # macOS 26+ draws its own glass squircle and crops the art, so the art
        # fills the canvas and is scaled slightly up to sit well inside it.
        content_px = canvas_px * 0.88
    else:
        content_px = canvas_px * CONTENT / CANVAS
    scale = content_px / CONTENT
    offset = (canvas_px - content_px) / 2.0

    def X(v: float) -> float:
        return offset + v * scale

    def Y(v: float) -> float:
        return offset + v * scale

    def S(v: float) -> float:
        return v * scale

    # Small variants: a slender blade plus a thin hilt dissolves below 64 px,
    # so the sword becomes shorter and bolder, the guard widens, the hilt is
    # dropped and the blade edge is pushed brighter for contrast.
    if simplified:
        blade_top, blade_guard = 150.0, 514.0
        blade_half = 46.0
        blade_belly = 0.42
        guard_half = 136.0
        blade_top_c = (255, 255, 255)
        blade_bottom_c = (204, 226, 236)
        pill_cx, pill_cy, pill_r = 566.0, 152.0, 38.0
    else:
        blade_top, blade_guard = float(BLADE_TOP), float(BLADE_GUARD)
        blade_half = BLADE_HALF_WIDTH
        blade_belly = 0.62
        guard_half = GUARD_HALF
        blade_top_c = palette["blade_top"]
        blade_bottom_c = palette["blade_bottom"]
        pill_cx, pill_cy, pill_r = float(PILL_CX), float(PILL_CY), float(PILL_R)

    # --- background -------------------------------------------------------
    base = vertical_gradient(canvas_px, palette["bg_top"], palette["bg_bottom"]).convert("RGBA")
    base = Image.alpha_composite(
        base, radial_glow(canvas_px, palette["halo"], 150 if not simplified else 120)
    )

    # --- magic formation (background layer) -------------------------------
    if not simplified:
        form = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        fd = ImageDraw.Draw(form)
        for ratio, width in ((1.0, 4), (0.74, 3), (0.46, 3)):
            rx = S(FORMATION_RX * ratio)
            ry = S(FORMATION_RY * ratio)
            fd.ellipse(
                [X(FORMATION_CX) - rx, Y(FORMATION_CY) - ry, X(FORMATION_CX) + rx, Y(FORMATION_CY) + ry],
                outline=palette["qi_dim"] + (135,), width=max(1, int(round(S(width)))),
            )
        for k in range(8):
            angle = math.pi * 2 * k / 8 + math.pi / 8
            x0 = FORMATION_CX + math.cos(angle) * FORMATION_RX
            y0 = FORMATION_CY + math.sin(angle) * FORMATION_RY
            x1 = FORMATION_CX + math.cos(angle) * (FORMATION_RX + 17)
            y1 = FORMATION_CY + math.sin(angle) * (FORMATION_RY + 17)
            fd.line([X(x0), Y(y0), X(x1), Y(y1)],
                    fill=palette["qi_dim"] + (120,), width=max(1, int(round(S(3)))))
        base = Image.alpha_composite(base, form)

    # --- spiritual-energy ribbon ------------------------------------------
    if not simplified:
        pts = []
        for seg in RIBBON:
            pts.extend(cubic_points(*seg))
        poly = ribbon_polygon(pts, RIBBON_WIDTH)
        ribbon = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        ImageDraw.Draw(ribbon).polygon(
            [(X(x), Y(y)) for x, y in poly], fill=palette["qi"] + (235,)
        )
        base = Image.alpha_composite(base, ribbon.filter(ImageFilter.GaussianBlur(S(13))))
        base = Image.alpha_composite(base, ribbon)

    # --- flying sword ------------------------------------------------------
    left, right = [], []
    steps = 220
    for i in range(steps + 1):
        t = i / steps
        y = blade_top + t * (blade_guard - blade_top)
        w = blade_half * (math.sin(math.pi * t) ** blade_belly)
        left.append((BLADE_CX - w, y))
        right.append((BLADE_CX + w, y))
    blade_poly = [(X(x), Y(y)) for x, y in left + right[::-1]]

    mask = Image.new("L", (canvas_px, canvas_px), 0)
    ImageDraw.Draw(mask).polygon(blade_poly, fill=255)
    blade = Image.composite(
        vertical_gradient(canvas_px, blade_top_c, blade_bottom_c).convert("RGBA"),
        Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0)), mask,
    )
    # central highlight
    shine = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    ImageDraw.Draw(shine).polygon(
        [(X(BLADE_CX - 7), Y(blade_top + 42)), (X(BLADE_CX + 7), Y(blade_top + 42)),
         (X(BLADE_CX + 4), Y(blade_guard - 8)), (X(BLADE_CX - 4), Y(blade_guard - 8))],
        fill=(255, 255, 255, 70 if simplified else 60),
    )
    blade = Image.alpha_composite(blade, shine)
    base = Image.alpha_composite(base, blade)

    # --- guard (gold) ------------------------------------------------------
    guard = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    gd = ImageDraw.Draw(guard)
    gd.polygon(
        [(X(BLADE_CX - guard_half), Y(blade_guard + 3)),
         (X(BLADE_CX - guard_half + 12), Y(blade_guard)),
         (X(BLADE_CX + guard_half - 12), Y(blade_guard)),
         (X(BLADE_CX + guard_half), Y(blade_guard + 3)),
         (X(BLADE_CX + guard_half), Y(blade_guard + GUARD_HEIGHT - 3)),
         (X(BLADE_CX + guard_half - 12), Y(blade_guard + GUARD_HEIGHT)),
         (X(BLADE_CX - guard_half + 12), Y(blade_guard + GUARD_HEIGHT)),
         (X(BLADE_CX - guard_half), Y(blade_guard + GUARD_HEIGHT - 3))],
        fill=palette["gold"] + (255,),
    )
    gd.line([(X(BLADE_CX - guard_half + 6), Y(blade_guard + GUARD_HEIGHT - 4)),
             (X(BLADE_CX + guard_half - 6), Y(blade_guard + GUARD_HEIGHT - 4))],
            fill=palette["gold_dark"] + (200,), width=max(1, int(round(S(2)))))
    base = Image.alpha_composite(base, guard)

    # --- hilt (full size only) --------------------------------------------
    if not simplified:
        hilt = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        hd = ImageDraw.Draw(hilt)
        hd.rounded_rectangle(
            [X(BLADE_CX - HILT_HALF), Y(blade_guard + GUARD_HEIGHT),
             X(BLADE_CX + HILT_HALF), Y(blade_guard + GUARD_HEIGHT + 74)],
            radius=S(HILT_HALF * 0.8), fill=palette["hilt"] + (255,),
        )
        hd.rounded_rectangle(
            [X(BLADE_CX - HILT_HALF * 0.42), Y(blade_guard + GUARD_HEIGHT + 4),
             X(BLADE_CX + HILT_HALF * 0.42), Y(blade_guard + GUARD_HEIGHT + 70)],
            radius=S(HILT_HALF * 0.4), fill=palette["hilt_dark"] + (190,),
        )
        base = Image.alpha_composite(base, hilt)

    # --- elixir pill -------------------------------------------------------
    pill_glow = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    ImageDraw.Draw(pill_glow).ellipse(
        [X(pill_cx - pill_r), Y(pill_cy - pill_r), X(pill_cx + pill_r), Y(pill_cy + pill_r)],
        fill=palette["pill"] + (255,),
    )
    base = Image.alpha_composite(base, pill_glow.filter(ImageFilter.GaussianBlur(S(13))))
    pill = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    pld = ImageDraw.Draw(pill)
    pld.ellipse([X(pill_cx - pill_r), Y(pill_cy - pill_r), X(pill_cx + pill_r), Y(pill_cy + pill_r)],
                fill=palette["pill"] + (255,))
    pld.ellipse([X(pill_cx - pill_r * 0.42), Y(pill_cy - pill_r * 0.52),
                 X(pill_cx - pill_r * 0.02), Y(pill_cy - pill_r * 0.16)],
                fill=palette["pill_light"] + (225,))
    base = Image.alpha_composite(base, pill)

    # --- squircle mask + soft shadow --------------------------------------
    if flat:
        return base.resize((target, target), Image.LANCZOS)

    box = (int(round(offset)), int(round(offset)),
           int(round(offset + content_px)), int(round(offset + content_px)))
    inner = base.crop(box).resize((int(content_px), int(content_px)), Image.LANCZOS)

    mask = superellipse_mask(int(content_px))
    shadow = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 70 if simplified else 90),
                 (int(offset), int(offset + S(10))), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S(14 if simplified else 16)))

    out = Image.alpha_composite(shadow, Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0)))
    emblem = inner.copy()
    emblem.putalpha(mask)
    out.alpha_composite(emblem, (int(round(offset)), int(round(offset))))
    return out.resize((target, target), Image.LANCZOS)


def write_iconset(palette: dict, simplified_small: bool, out_dir: Path, flat: bool = False) -> None:
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    entries = [
        ("icon_16x16.png", 16, simplified_small),
        ("icon_16x16@2x.png", 32, simplified_small),
        ("icon_32x32.png", 32, simplified_small),
        ("icon_32x32@2x.png", 64, simplified_small),
        ("icon_128x128.png", 128, False),
        ("icon_128x128@2x.png", 256, False),
        ("icon_256x256.png", 256, False),
        ("icon_256x256@2x.png", 512, False),
        ("icon_512x512.png", 512, False),
        ("icon_512x512@2x.png", 1024, False),
    ]
    for name, size, simple in entries:
        render(size, palette, simple, flat).save(out_dir / name)
    print(f"iconset written: {out_dir} ({len(entries)} files)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--variant", choices=["dark", "light"], default="dark")
    parser.add_argument("--style", choices=["flat", "legacy"], default="flat",
                        help="flat: art fills the canvas (macOS 26+ container); "
                             "legacy: art carries its own squircle (macOS 13-15)")
    parser.add_argument("--preview", action="store_true", help="write small-size proof sheets")
    args = parser.parse_args()

    palette = DARK if args.variant == "dark" else LIGHT
    flat = args.style == "flat"
    ASSETS.mkdir(parents=True, exist_ok=True)

    suffix = "" if args.variant == "dark" else "-light"
    if not flat:
        suffix += "-legacy"

    master = render(CANVAS, palette, False, flat)
    master_path = ASSETS / f"icon-master{suffix}-1024.png"
    master.save(master_path)
    print(f"master written: {master_path}")

    iconset = ASSETS / f"AppIcon{suffix}.iconset"
    write_iconset(palette, True, iconset, flat)

    icns = ASSETS / f"AppIcon{suffix}.icns"
    if icns.exists():
        icns.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
    print(f"icns written:   {icns} ({icns.stat().st_size / 1024:.0f} KB)")

    if args.preview:
        proof = ASSETS / f"icon-proof{suffix}.png"
        sheet = Image.new("RGBA", (1120, 360), (22, 22, 26, 255))
        x = 20
        for size in (16, 32, 64, 128, 256):
            img = render(size, palette, size <= 64)
            sheet.alpha_composite(img, (x, 50))
            x += size + 22
        sheet.save(proof)
        print(f"proof sheet:    {proof}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
