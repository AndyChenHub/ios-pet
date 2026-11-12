#!/usr/bin/env python3
"""
Generates all assets required by IslandPup (App + WidgetExtension):
1. Shared/Resources/PetTimerGate-Regular.ttf — OpenType 2-digit seconds ligature gate font
   modeled on Apple CoreText's `Text(..., style: .timer)` run-splitting behavior.
2. Shared/Assets.xcassets — Crisp @3x PNG sprite frames (even frame counts 4/6/8)
   for Alfie and Teddy across all 10 actions, plus AccentColor and 1024x1024 AppIcon.
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SPRITES_DIR = ROOT / "Sprites"
SHARED_DIR = ROOT / "Shared"
RESOURCES_DIR = SHARED_DIR / "Resources"
XCASSETS_DIR = SHARED_DIR / "Assets.xcassets"

CELL_W = 192
CELL_H = 208
TARGET_CANVAS = 144  # Crisp @3x size optimized for WidgetKit / Dynamic Island 30MB Jetsam budget

PETS = {
    "alfie": SPRITES_DIR / "Alfie" / "spritesheet.png",
    "teddy": SPRITES_DIR / "Teddy" / "spritesheet.png",
}

# Every action has an EVEN frame count (4, 6, or 8) for 2-stack Painter's Algorithm gating.
ACTIONS = [
    ("idle", 0, [0, 1, 2, 3, 4, 5]),
    ("sleeping", 5, [5, 7, 6, 7]),
    ("waving", 3, [0, 1, 2, 3]),
    ("jumping", 4, [0, 1, 2, 3, 4, 0]),
    ("runRight", 1, [0, 1, 2, 3, 4, 5, 6, 7]),
    ("runLeft", 2, [0, 1, 2, 3, 4, 5, 6, 7]),
    ("waiting", 6, [0, 1, 2, 3, 4, 5]),
    ("working", 7, [0, 1, 2, 3, 4, 5]),
    ("review", 8, [0, 1, 2, 3, 4, 5]),
    ("dizzy", 5, [0, 1, 2, 3, 4, 5, 6, 7]),
]

DIGIT_NAMES = [
    "zero", "one", "two", "three", "four",
    "five", "six", "seven", "eight", "nine",
]


def build_timer_gate_font(output_path: Path) -> None:
    """
    Builds `PetTimerGate-Regular.ttf`:
    - unitsPerEm = 500, ascent = 500, descent = 0
    - Every individual character (`space`, `zero`..`nine`, `colon`) has advanceWidth=500 & empty glyph
      so CoreText's colon run-splitting never draws stray shapes on minutes/hours/colons.
    - All 60 two-digit seconds pairs (`00`..`59`) substitute via `liga` (LookupFlag 0) into:
        * `ligaturefull`  (500x500 solid square) for even seconds (0, 2, 4, 6, 8)
        * `ligatureempty` (empty 500-wide glyph) for odd seconds  (1, 3, 5, 7, 9)
    - Combined with trailing text alignment + horizontal offset, the final `SS` ligature sits
      dead-center over the `size x size` sprite frame.
    """
    if RESOURCES_DIR.exists():
        shutil.rmtree(RESOURCES_DIR)
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    glyph_order = [
        ".notdef",
        "space",
        *DIGIT_NAMES,
        "colon",
        "ligatureempty",
        "ligaturefull",
    ]

    fb = FontBuilder(500, isTTF=True)
    fb.setupGlyphOrder(glyph_order)

    glyf_map = {}
    metrics_map = {}
    for gname in glyph_order:
        pen = TTGlyphPen(None)
        if gname == "ligaturefull":
            # Clockwise outer contour covering the full 500x500 em square
            pen.moveTo((0, 0))
            pen.lineTo((0, 500))
            pen.lineTo((500, 500))
            pen.lineTo((500, 0))
            pen.closePath()
        glyf_map[gname] = pen.glyph()
        metrics_map[gname] = (500, 0)

    fb.setupGlyf(glyf_map)
    fb.setupHorizontalMetrics(metrics_map)

    cmap: dict[int, str] = {
        0x0020: "space",
        0x00A0: "space",
        0x2007: "space",
        0x202F: "space",
        0x003A: "colon",
        0x2236: "colon",  # Apple SF timer ratio colon '∶'
    }
    for idx, dname in enumerate(DIGIT_NAMES):
        cmap[0x0030 + idx] = dname

    fb.setupCharacterMap(cmap)
    fb.setupHorizontalHeader(ascent=500, descent=0)
    fb.setupNameTable({
        "familyName": "PetTimerGate",
        "styleName": "Regular",
        "uniqueFontIdentifier": "IslandPup.PetTimerGate-Regular.2.0",
        "fullName": "PetTimerGate Regular",
        "psName": "PetTimerGate-Regular",
        "version": "Version 2.0",
    })
    fb.setupOS2(
        sTypoAscender=500,
        sTypoDescender=0,
        sTypoLineGap=0,
        usWinAscent=500,
        usWinDescent=0,
    )
    fb.setupPost()

    lig_rules: list[str] = []
    for tens in range(6):
        for ones in range(10):
            target = "ligaturefull" if (ones % 2 == 0) else "ligatureempty"
            lig_rules.append(f"        sub {DIGIT_NAMES[tens]} {DIGIT_NAMES[ones]} by {target};")

    rules_block = "\n".join(lig_rules)
    fea = f"""
    languagesystem DFLT dflt;
    languagesystem latn dflt;

    lookup SecondsParityLigatures {{
        lookupflag 0;
{rules_block}
    }} SecondsParityLigatures;

    feature liga {{
        lookup SecondsParityLigatures;
    }} liga;

    feature rlig {{
        lookup SecondsParityLigatures;
    }} rlig;
    """

    addOpenTypeFeaturesFromString(fb.font, fea)
    fb.save(str(output_path))
    print(f"[OK] Built {output_path} ({output_path.stat().st_size} bytes)")


def verify_two_stack_animation(font_path: Path) -> None:
    """
    Verifies both CoreText colon-split shaping AND the 2-stack Painter's Algorithm
    so we prove mathematically that every frame 0..N-1 appears in exact forward sequence
    and NEVER renders an empty/black frame.
    """
    import uharfbuzz as hb

    blob = hb.Blob.from_file_path(str(font_path))
    face = hb.Face(blob)
    font = hb.Font(face)

    def last_glyph_is_full(timer_str: str) -> bool:
        # Simulate CoreText splitting runs at ':' or shaping the whole string:
        for mode in ("whole", "colon_split"):
            parts = [timer_str] if mode == "whole" else timer_str.split(":")
            last_part = parts[-1]
            buf = hb.Buffer()
            buf.add_str(last_part)
            buf.guess_segment_properties()
            hb.shape(font, buf)
            glyph_names = [font.glyph_to_string(info.codepoint) for info in buf.glyph_infos]
            if mode == "colon_split":
                assert len(glyph_names) == 1, f"Expected 1 ligature glyph for {last_part!r}, got {glyph_names}"
            is_on = glyph_names[-1] == "ligaturefull"
            if mode == "whole":
                whole_res = is_on
            else:
                split_res = is_on
        assert whole_res == split_res
        return split_res

    for s, expected in [("1:00", True), ("1:01", False), ("12:34", True), ("12:35", False), ("1:00:58", True), ("1:00:59", False)]:
        assert last_glyph_is_full(s) == expected, f"Failed parity for {s}"

    # Verify 2-stack Painter's Algorithm across 2000 steps for N in {4, 6, 8}
    anchor = -60.0  # Exact multiple of 2.0 in the past
    for n_frames in (4, 6, 8):
        half = n_frames // 2
        frame_dur = 2.0 / n_frames

        def blink_on(t_now: float, delta_date: float) -> bool:
            elapsed = int(math.floor(t_now - (anchor + delta_date)))
            s = f"{elapsed // 60}:{elapsed % 60:02d}"
            return last_glyph_is_full(s)

        for step in range(2000):
            t = step * 0.005 + 0.001
            expected = int(math.floor((t % 2.0) / frame_dur)) % n_frames

            # First stack (frames 0 .. half-1); frame 0 is UNMASKED!
            top_frame = 0
            for i in range(1, half):
                if blink_on(t, i * frame_dur):
                    top_frame = i

            # Second stack (frames half .. n_frames-1), outer-masked by delta_date = 1.0
            if blink_on(t, 1.0):
                top_frame = half  # frame `half` has NO inner mask!
                for i in range(half + 1, n_frames):
                    if blink_on(t, i * frame_dur):
                        top_frame = i

            assert top_frame == expected, f"N={n_frames} t={t:.3f}: got {top_frame}, expected {expected}"

    print("[OK] Verified colon-split HarfBuzz shaping & 2-stack Painter's Algorithm for N=4,6,8!")


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def slice_sprites() -> None:
    if XCASSETS_DIR.exists():
        shutil.rmtree(XCASSETS_DIR)
    XCASSETS_DIR.mkdir(parents=True, exist_ok=True)

    write_json(XCASSETS_DIR / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    write_json(
        XCASSETS_DIR / "AccentColor.colorset" / "Contents.json",
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {
                            "alpha": "1.000",
                            "blue": "0.349",
                            "green": "0.478",
                            "red": "1.000",
                        },
                    },
                    "idiom": "universal",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    sprites_group = XCASSETS_DIR / "Sprites"
    write_json(sprites_group / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    total_images = 0
    for pet_key, sheet_path in PETS.items():
        sheet = Image.open(sheet_path).convert("RGBA")
        for action_key, row_idx, cols in ACTIONS:
            raw_cells = [
                sheet.crop((c * CELL_W, row_idx * CELL_H, (c + 1) * CELL_W, (row_idx + 1) * CELL_H))
                for c in cols
            ]
            bboxes = [c.getbbox() for c in raw_cells if c.getbbox() is not None]
            u_left = min(b[0] for b in bboxes)
            u_top = min(b[1] for b in bboxes)
            u_right = max(b[2] for b in bboxes)
            u_bottom = max(b[3] for b in bboxes)

            u_w = u_right - u_left
            u_h = u_bottom - u_top

            max_dim = max(u_w, u_h)
            pad = 6
            canvas_dim = max(max_dim + pad * 2, TARGET_CANVAS)

            for frame_idx, cell in enumerate(raw_cells):
                cropped_union = cell.crop((u_left, u_top, u_right, u_bottom))
                square = Image.new("RGBA", (canvas_dim, canvas_dim), (0, 0, 0, 0))
                dst_x = (canvas_dim - u_w) // 2
                dst_y = (canvas_dim - u_h) // 2
                square.alpha_composite(cropped_union, (dst_x, dst_y))

                if canvas_dim != TARGET_CANVAS:
                    square = square.resize((TARGET_CANVAS, TARGET_CANVAS), Image.Resampling.LANCZOS)

                asset_name = f"{pet_key}_{action_key}_{frame_idx}"
                imageset_dir = sprites_group / f"{asset_name}.imageset"
                imageset_dir.mkdir(parents=True, exist_ok=True)
                png_filename = f"{asset_name}.png"
                square.save(imageset_dir / png_filename, format="PNG", optimize=True)

                write_json(
                    imageset_dir / "Contents.json",
                    {
                        "images": [
                            {
                                "filename": png_filename,
                                "idiom": "universal",
                            }
                        ],
                        "info": {"author": "xcode", "version": 1},
                        "properties": {
                            "preserves-vector-representation": False,
                            "template-rendering-intent": "original",
                        },
                    },
                )
                total_images += 1

    print(f"[OK] Sliced {total_images} @3x sprite frames ({TARGET_CANVAS}x{TARGET_CANVAS}px) into {sprites_group}")


def generate_app_icon() -> None:
    icon_size = 1024
    icon = Image.new("RGBA", (icon_size, icon_size), (14, 16, 28, 255))
    draw = ImageDraw.Draw(icon)

    for y in range(icon_size):
        t = y / (icon_size - 1)
        r = int(18 + 26 * t)
        g = int(20 + 18 * t)
        b = int(38 + 46 * t)
        draw.line([(0, y), (icon_size, y)], fill=(r, g, b, 255))

    glow = Image.new("RGBA", (icon_size, icon_size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((140, 220, 884, 820), fill=(255, 138, 92, 58))
    gdraw.ellipse((220, 320, 804, 760), fill=(116, 152, 255, 52))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=72))
    icon.alpha_composite(glow)

    pill_box = (112, 650, 912, 858)
    draw.rounded_rectangle(
        (pill_box[0] - 4, pill_box[1] - 4, pill_box[2] + 4, pill_box[3] + 4),
        radius=108,
        fill=(255, 255, 255, 42),
    )
    draw.rounded_rectangle(pill_box, radius=104, fill=(8, 9, 14, 255))
    draw.ellipse((760, 720, 828, 788), fill=(20, 24, 38, 255))
    draw.ellipse((780, 740, 804, 764), fill=(52, 82, 160, 180))

    alfie_sheet = Image.open(PETS["alfie"]).convert("RGBA")
    teddy_sheet = Image.open(PETS["teddy"]).convert("RGBA")
    alfie_wave = alfie_sheet.crop((2 * CELL_W, 3 * CELL_H, 3 * CELL_W, 4 * CELL_H))
    teddy_wave = teddy_sheet.crop((1 * CELL_W, 3 * CELL_H, 2 * CELL_W, 4 * CELL_H))

    alfie_big = alfie_wave.resize((int(CELL_W * 2.55), int(CELL_H * 2.55)), Image.Resampling.LANCZOS)
    teddy_big = teddy_wave.resize((int(CELL_W * 2.55), int(CELL_H * 2.55)), Image.Resampling.LANCZOS)

    icon.alpha_composite(alfie_big, (88, 178))
    icon.alpha_composite(teddy_big, (462, 178))

    icon_rgb = icon.convert("RGB")
    appicon_dir = XCASSETS_DIR / "AppIcon.appiconset"
    appicon_dir.mkdir(parents=True, exist_ok=True)
    icon_rgb.save(appicon_dir / "AppIcon.png", format="PNG", optimize=True)

    write_json(
        appicon_dir / "Contents.json",
        {
            "images": [
                {
                    "filename": "AppIcon.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )
    print(f"[OK] Generated 1024x1024 opaque AppIcon at {appicon_dir / 'AppIcon.png'}")


if __name__ == "__main__":
    gate_font = RESOURCES_DIR / "PetTimerGate-Regular.ttf"
    build_timer_gate_font(gate_font)
    verify_two_stack_animation(gate_font)
    slice_sprites()
    generate_app_icon()
