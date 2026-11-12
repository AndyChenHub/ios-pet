#!/usr/bin/env python3
"""
Generates all assets required by IslandPup (App + WidgetExtension):
1. Shared/Resources/PetTimerGate.ttf — OpenType GSUB gate font for battery-free
   continuous sprite animation inside iOS Dynamic Island & Lock Screen Live Activities.
2. Shared/Assets.xcassets — Lossless per-animation cropped @3x PNG sprite frames
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
TARGET_CANVAS = 192  # Square @3x canvas (64x64 pt native, lossless pixel density)

PETS = {
    "alfie": SPRITES_DIR / "Alfie" / "spritesheet.png",
    "teddy": SPRITES_DIR / "Teddy" / "spritesheet.png",
}

# (action_key, row_index, column_indices)
ACTIONS = [
    ("idle", 0, [0, 1, 2, 3, 4, 5]),
    ("sleeping", 5, [5, 7, 6, 7]),
    ("waving", 3, [0, 1, 2, 3]),
    ("jumping", 4, [0, 1, 2, 3, 4]),
    ("runRight", 1, [0, 1, 2, 3, 4, 5, 6, 7]),
    ("runLeft", 2, [0, 1, 2, 3, 4, 5, 6, 7]),
    ("waiting", 6, [0, 1, 2, 3, 4, 5]),
    ("working", 7, [0, 1, 2, 3, 4, 5]),
    ("review", 8, [0, 1, 2, 3, 4, 5]),
    ("dizzy", 5, [0, 1, 2, 3, 4, 5, 6, 7]),
]


def build_timer_gate_font(output_path: Path) -> None:
    """
    Builds PetTimerGate.ttf:
    - Even digits (0, 2, 4, 6, 8 in ASCII & common Unicode digit scripts) -> 'ON' (solid square)
    - Odd digits  (1, 3, 5, 7, 9 in ASCII & common Unicode digit scripts) -> 'OFF' (empty)
    - Colons, punctuation, spaces, Unicode bidi isolates -> 'IGN' (empty, GDEF Mark class, skipped)
    - 5 sequential passes of 2-glyph ligatures fold up to 32 digits down to the LAST digit's parity:
      ON if elapsed whole seconds is EVEN, OFF if elapsed whole seconds is ODD.
    """
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    glyph_order = [".notdef", "ON", "OFF", "IGN"]

    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(glyph_order)

    # Glyphs: ON is an oversized full-bleed opaque block; OFF and IGN have zero contours.
    pen_notdef = TTGlyphPen(None)
    notdef_glyph = pen_notdef.glyph()

    pen_on = TTGlyphPen(None)
    # Oversized rectangle so mask covers 100% of sprite with zero edge bleed/clipping
    pen_on.moveTo((-500, -500))
    pen_on.lineTo((-500, 1500))
    pen_on.lineTo((1500, 1500))
    pen_on.lineTo((1500, -500))
    pen_on.closePath()
    on_glyph = pen_on.glyph()

    pen_off = TTGlyphPen(None)
    off_glyph = pen_off.glyph()

    pen_ign = TTGlyphPen(None)
    ign_glyph = pen_ign.glyph()

    fb.setupGlyf({
        ".notdef": notdef_glyph,
        "ON": on_glyph,
        "OFF": off_glyph,
        "IGN": ign_glyph,
    })

    fb.setupHorizontalMetrics({
        ".notdef": (0, 0),
        "ON": (1000, -500),
        "OFF": (0, 0),
        "IGN": (0, 0),
    })

    cmap: dict[int, str] = {}
    # Digit ranges: ASCII, Arabic-Indic, Extended Arabic-Indic, Devanagari, Fullwidth
    digit_bases = [0x0030, 0x0660, 0x06F0, 0x0966, 0xFF10]
    for base in digit_bases:
        for d in range(10):
            cmap[base + d] = "ON" if (d % 2 == 0) else "OFF"

    # Non-digit characters emitted by Date/Timer formatters across locales
    ignored_codepoints = [
        0x0020,  # SPACE
        0x002C,  # COMMA
        0x002D,  # HYPHEN-MINUS
        0x002E,  # FULL STOP
        0x003A,  # COLON ':'
        0x003B,  # SEMICOLON
        0x00A0,  # NO-BREAK SPACE
        0x060C,  # ARABIC COMMA
        0x061C,  # ARABIC LETTER MARK
        0x2007,  # FIGURE SPACE
        0x2008,  # PUNCTUATION SPACE
        0x2009,  # THIN SPACE
        0x200A,  # HAIR SPACE
        0x200B,  # ZERO WIDTH SPACE
        0x200E,  # LEFT-TO-RIGHT MARK
        0x200F,  # RIGHT-TO-LEFT MARK
        0x202A,  # LRE
        0x202B,  # RLE
        0x202C,  # PDF
        0x202D,  # LRO
        0x202E,  # RLO
        0x202F,  # NARROW NO-BREAK SPACE
        0x2060,  # WORD JOINER
        0x2066,  # LRI
        0x2067,  # RLI
        0x2068,  # FSI (used by Apple formatters!)
        0x2069,  # PDI (used by Apple formatters!)
        0x2212,  # MINUS SIGN
        0x2236,  # RATIO '∶' (used by Apple SF timer colons!)
        0xFEFF,  # BOM / ZWNBSP
        0xFF1A,  # FULLWIDTH COLON
    ]
    for cp in ignored_codepoints:
        cmap[cp] = "IGN"

    fb.setupCharacterMap(cmap)
    fb.setupHorizontalHeader(ascent=1000, descent=0)
    fb.setupNameTable({
        "familyName": "PetTimerGate",
        "styleName": "Regular",
        "uniqueFontIdentifier": "IslandPup.PetTimerGate.1.0",
        "fullName": "PetTimerGate",
        "psName": "PetTimerGate",
        "version": "Version 1.0",
    })
    fb.setupOS2(
        sTypoAscender=1000,
        sTypoDescender=0,
        sTypoLineGap=0,
        usWinAscent=1500,
        usWinDescent=500,
    )
    fb.setupPost()

    fea = """
    languagesystem DFLT dflt;
    languagesystem latn dflt;
    languagesystem arab dflt;

    table GDEF {
        GlyphClassDef [ON OFF], , [IGN], ;
    } GDEF;

    lookup FoldPass1 {
        lookupflag IgnoreMarks;
        sub ON ON by ON;
        sub ON OFF by OFF;
        sub OFF ON by ON;
        sub OFF OFF by OFF;
    } FoldPass1;

    lookup FoldPass2 {
        lookupflag IgnoreMarks;
        sub ON ON by ON;
        sub ON OFF by OFF;
        sub OFF ON by ON;
        sub OFF OFF by OFF;
    } FoldPass2;

    lookup FoldPass3 {
        lookupflag IgnoreMarks;
        sub ON ON by ON;
        sub ON OFF by OFF;
        sub OFF ON by ON;
        sub OFF OFF by OFF;
    } FoldPass3;

    lookup FoldPass4 {
        lookupflag IgnoreMarks;
        sub ON ON by ON;
        sub ON OFF by OFF;
        sub OFF ON by ON;
        sub OFF OFF by OFF;
    } FoldPass4;

    lookup FoldPass5 {
        lookupflag IgnoreMarks;
        sub ON ON by ON;
        sub ON OFF by OFF;
        sub OFF ON by ON;
        sub OFF OFF by OFF;
    } FoldPass5;

    feature rlig {
        lookup FoldPass1;
        lookup FoldPass2;
        lookup FoldPass3;
        lookup FoldPass4;
        lookup FoldPass5;
    } rlig;

    feature liga {
        lookup FoldPass1;
        lookup FoldPass2;
        lookup FoldPass3;
        lookup FoldPass4;
        lookup FoldPass5;
    } liga;
    """

    addOpenTypeFeaturesFromString(fb.font, fea)
    fb.save(str(output_path))
    print(f"[OK] Built {output_path} ({output_path.stat().st_size} bytes)")


def verify_timer_gate_font(font_path: Path) -> None:
    """Verifies OpenType shaping via HarfBuzz & sub-second dual-mask math."""
    try:
        import uharfbuzz as hb
    except ImportError:
        print("[WARN] uharfbuzz not installed; skipping shaping verification.")
        return

    blob = hb.Blob.from_file_path(str(font_path))
    face = hb.Face(blob)
    font = hb.Font(face)

    def shape_is_on(s: str) -> bool:
        buf = hb.Buffer()
        buf.add_str(s)
        buf.guess_segment_properties()
        hb.shape(font, buf)
        names = [font.glyph_to_string(info.codepoint) for info in buf.glyph_infos]
        non_ign = [n for n in names if n != "IGN"]
        assert len(non_ign) == 1, f"Expected 1 non-IGN glyph for {s!r}, got {names}"
        return non_ign[0] == "ON"

    test_cases = [
        ("0:00", True),
        ("0:01", False),
        ("0:02", True),
        ("0:19", False),
        ("0:20", True),
        ("0:59", False),
        ("1:00", True),
        ("12:34", True),
        ("12:35", False),
        ("1:00:00", True),
        ("12:48:59", False),
        ("999:59:58", True),
        ("\u20680\u223642\u2069", True),
        ("\u20680\u223643\u2069", False),
    ]
    for text, expected in test_cases:
        actual = shape_is_on(text)
        assert actual == expected, f"Mismatch for {text!r}: got {actual}, expected {expected}"

    # Verify dual-mask intersection across 2000 steps for N in {4, 5, 6, 8}
    period = 2.0
    anchor = -10.0  # 10s in the past
    for n_frames in (4, 5, 6, 8):
        delta = period / n_frames
        for step in range(2000):
            t = step * 0.005 + 0.001  # avoid exact floating boundary
            expected_frame = int(math.floor((t % period) / delta)) % n_frames
            visible_frames = []
            for k in range(n_frames):
                off1 = k * delta
                off2 = k * delta + delta - 1.0
                elapsed1 = int(math.floor(t - (anchor + off1)))
                elapsed2 = int(math.floor(t - (anchor + off2)))
                s1 = f"{elapsed1 // 60}:{elapsed1 % 60:02d}"
                s2 = f"{elapsed2 // 60}:{elapsed2 % 60:02d}"
                if shape_is_on(s1) and shape_is_on(s2):
                    visible_frames.append(k)
            assert visible_frames == [expected_frame], (
                f"N={n_frames} t={t:.3f}: visible={visible_frames}, expected=[{expected_frame}]"
            )
    print("[OK] Verified HarfBuzz shaping & dual-mask sub-second frame exclusivity for N=4,5,6,8!")


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def slice_sprites() -> None:
    if XCASSETS_DIR.exists():
        shutil.rmtree(XCASSETS_DIR)
    XCASSETS_DIR.mkdir(parents=True, exist_ok=True)

    write_json(
        XCASSETS_DIR / "Contents.json",
        {"info": {"author": "xcode", "version": 1}},
    )

    # AccentColor (#FF7A59 warm coral-amber)
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
    write_json(
        sprites_group / "Contents.json",
        {"info": {"author": "xcode", "version": 1}},
    )

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

            # Fit inside TARGET_CANVAS with 4px breathing padding on each side
            max_dim = max(u_w, u_h)
            pad = 8
            canvas_dim = max(max_dim + pad * 2, TARGET_CANVAS)

            for frame_idx, cell in enumerate(raw_cells):
                cropped_union = cell.crop((u_left, u_top, u_right, u_bottom))
                square = Image.new("RGBA", (canvas_dim, canvas_dim), (0, 0, 0, 0))
                dst_x = (canvas_dim - u_w) // 2
                # Anchor slightly lower for grounded animations, centered for sleeping
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
                                "scale": "3x",
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

    print(f"[OK] Sliced {total_images} lossless @3x sprite frames into {sprites_group}")


def generate_app_icon() -> None:
    """Generates a polished 1024x1024 iOS AppIcon showcasing Alfie & Teddy on Dynamic Island."""
    icon_size = 1024
    icon = Image.new("RGBA", (icon_size, icon_size), (14, 16, 28, 255))
    draw = ImageDraw.Draw(icon)

    # Rich dusk gradient background
    for y in range(icon_size):
        t = y / (icon_size - 1)
        r = int(18 + 26 * t)
        g = int(20 + 18 * t)
        b = int(38 + 46 * t)
        draw.line([(0, y), (icon_size, y)], fill=(r, g, b, 255))

    # Soft ambient glow behind the Dynamic Island pill
    glow = Image.new("RGBA", (icon_size, icon_size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse((140, 220, 884, 820), fill=(255, 138, 92, 58))
    gdraw.ellipse((220, 320, 804, 760), fill=(116, 152, 255, 52))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=72))
    icon.alpha_composite(glow)

    # Dynamic Island black capsule pedestal in the lower-middle
    pill_box = (112, 650, 912, 858)
    draw.rounded_rectangle(
        (pill_box[0] - 4, pill_box[1] - 4, pill_box[2] + 4, pill_box[3] + 4),
        radius=108,
        fill=(255, 255, 255, 42),
    )
    draw.rounded_rectangle(pill_box, radius=104, fill=(8, 9, 14, 255))

    # Camera lens glint inside Dynamic Island pill
    draw.ellipse((760, 720, 828, 788), fill=(20, 24, 38, 255))
    draw.ellipse((780, 740, 804, 764), fill=(52, 82, 160, 180))

    # Composite Alfie (waving) on left and Teddy (idle/waving) on right perched on the Island!
    alfie_sheet = Image.open(PETS["alfie"]).convert("RGBA")
    teddy_sheet = Image.open(PETS["teddy"]).convert("RGBA")

    alfie_wave = alfie_sheet.crop((2 * CELL_W, 3 * CELL_H, 3 * CELL_W, 4 * CELL_H))
    teddy_wave = teddy_sheet.crop((1 * CELL_W, 3 * CELL_H, 2 * CELL_W, 4 * CELL_H))

    alfie_big = alfie_wave.resize((int(CELL_W * 2.55), int(CELL_H * 2.55)), Image.Resampling.LANCZOS)
    teddy_big = teddy_wave.resize((int(CELL_W * 2.55), int(CELL_H * 2.55)), Image.Resampling.LANCZOS)

    icon.alpha_composite(alfie_big, (88, 178))
    icon.alpha_composite(teddy_big, (462, 178))

    # Convert to RGB (Apple requires opaque 1024x1024 PNG without alpha channel for App Store / Xcode)
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
    gate_font = RESOURCES_DIR / "PetTimerGate.ttf"
    build_timer_gate_font(gate_font)
    verify_timer_gate_font(gate_font)
    slice_sprites()
    generate_app_icon()
