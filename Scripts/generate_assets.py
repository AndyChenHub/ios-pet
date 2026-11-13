#!/usr/bin/env python3
"""
Generates all assets required by IslandPup (App + WidgetExtension):
1. Shared/Resources/PetTimerGate-Regular.ttf — OpenType 2-digit seconds ligature gate font
   modeled on Apple CoreText's `Text(..., style: .timer)` run-splitting behavior.
2. Shared/Assets.xcassets — Crisp @3x PNG sprite frames (even frame counts 4 or 6)
   for Alfie and Teddy across all 22 solo emotions/tasks/quirks, plus all 20 combined
   Alfie & Teddy duo interaction animations, AccentColor, and 1024x1024 AppIcon.
"""

from __future__ import annotations

import json
import math
import shutil
import struct
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
TARGET_CANVAS = 144  # Crisp @3x square size optimized for WidgetKit / Dynamic Island 30MB Jetsam budget

DUO_CELL_W = 288
DUO_CELL_H = 208
DUO_TARGET_W = 200
DUO_TARGET_H = 144

SKIT_WEBP_W = 240
SKIT_WEBP_H = 162

PETS = {
    "alfie": {
        "base": SPRITES_DIR / "Alfie" / "spritesheet.png",
        "extra": SPRITES_DIR / "Alfie" / "extra_spritesheet.png",
    },
    "teddy": {
        "base": SPRITES_DIR / "Teddy" / "spritesheet.png",
        "extra": SPRITES_DIR / "Teddy" / "extra_spritesheet.png",
    },
}

DUO_SHEET_PATH = SPRITES_DIR / "Duo" / "duo_spritesheet.png"
DUO_META_PATH = SPRITES_DIR / "Duo" / "duo_animations.json"
LONG_SKITS_DIR = SPRITES_DIR / "Duo" / "LongSkits"
LONG_SKITS_MANIFEST = LONG_SKITS_DIR / "skits_manifest.json"

# Every solo action has an EVEN frame count (4 or 6) for 2-stack Painter's Algorithm gating.
SOLO_ACTIONS = [
    # Core & Everyday Tasks (7)
    ("idle", "base", 0, [0, 1, 2, 3, 4, 5]),
    ("walk", "extra", 0, [0, 1, 2, 3]),
    ("working", "extra", 1, [0, 1, 2, 3]),
    ("sleeping", "extra", 2, [0, 1, 2, 3]),
    ("eating", "extra", 3, [0, 1, 2, 3]),
    ("review", "base", 8, [0, 1, 2, 3, 4, 5]),
    ("waiting", "base", 6, [0, 1, 2, 3, 4, 5]),
    # Everyday Emotions (7)
    ("happy", "extra", 4, [0, 1, 2, 3]),
    ("love", "extra", 6, [0, 1, 2, 3]),
    ("waving", "base", 3, [0, 1, 2, 3]),
    ("celebrate", "extra", 9, [0, 1, 2, 3]),
    ("sad", "extra", 5, [0, 1, 2, 3]),
    ("confused", "extra", 7, [0, 1, 2, 3]),
    ("grumpy", "extra", 8, [0, 1, 2, 3]),
    # Special Triggered Solo Quirks (8)
    ("zoomies", "extra", 10, [0, 1, 2, 3, 4, 5]),
    ("begging", "extra", 11, [0, 1, 2, 3]),
    ("spinning", "extra", 12, [0, 1, 2, 3, 4, 5]),
    ("dizzy", "extra", 13, [0, 1, 2, 3]),
    ("booping", "extra", 14, [0, 1, 2, 3]),
    ("splooting", "extra", 15, [0, 1, 2, 3]),
    ("sideEye", "extra", 16, [0, 1, 2, 3]),
    ("blep", "extra", 17, [0, 1, 2, 3]),
]

DIGIT_NAMES = [
    "zero", "one", "two", "three", "four",
    "five", "six", "seven", "eight", "nine",
]


def build_timer_gate_font(output_path: Path, family_name: str, cycle_seconds: int) -> None:
    assert 60 % cycle_seconds == 0 and cycle_seconds % 2 == 0
    half_cycle = cycle_seconds // 2
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
        0x2236: "colon",
    }
    for idx, dname in enumerate(DIGIT_NAMES):
        cmap[0x0030 + idx] = dname

    ps_name = f"{family_name}-Regular"
    fb.setupCharacterMap(cmap)
    fb.setupHorizontalHeader(ascent=500, descent=0)
    fb.setupNameTable({
        "familyName": family_name,
        "styleName": "Regular",
        "uniqueFontIdentifier": f"IslandPup.{ps_name}.2.0",
        "fullName": f"{family_name} Regular",
        "psName": ps_name,
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
            sec = tens * 10 + ones
            target = "ligaturefull" if ((sec % cycle_seconds) < half_cycle) else "ligatureempty"
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
    print(f"[OK] Built {output_path} ({output_path.stat().st_size} bytes, cycle={cycle_seconds}s)")


def verify_two_stack_animation(font_path: Path, cycle_seconds: float, frame_counts: tuple[int, ...]) -> None:
    import uharfbuzz as hb

    blob = hb.Blob.from_file_path(str(font_path))
    face = hb.Face(blob)
    font = hb.Font(face)

    def last_glyph_is_full(timer_str: str) -> bool:
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

    anchor = -60.0
    half_cycle = cycle_seconds / 2.0
    for n_frames in frame_counts:
        half = n_frames // 2
        frame_dur = cycle_seconds / n_frames

        def blink_on(t_now: float, delta_date: float) -> bool:
            elapsed = int(math.floor(t_now - (anchor + delta_date)))
            s = f"{elapsed // 60}:{elapsed % 60:02d}"
            return last_glyph_is_full(s)

        for step in range(1200):
            t = step * 0.05 + 0.001
            expected = int(math.floor((t % cycle_seconds) / frame_dur)) % n_frames

            top_frame = 0
            for i in range(1, half):
                if blink_on(t, i * frame_dur):
                    top_frame = i

            if blink_on(t, half_cycle):
                top_frame = half
                for i in range(half + 1, n_frames):
                    if blink_on(t, i * frame_dur):
                        top_frame = i

            assert top_frame == expected, (
                f"cycle={cycle_seconds}s N={n_frames} t={t:.3f}: got {top_frame}, expected {expected}"
            )

    print(f"[OK] Verified HarfBuzz 2-stack Painter's Algorithm for cycle={cycle_seconds}s N={frame_counts}!")


def extract_webp_anmf_durations(webp_bytes: bytes) -> list[int]:
    pos = 12
    durs: list[int] = []
    n = len(webp_bytes)
    while pos + 8 <= n:
        fourcc = webp_bytes[pos : pos + 4]
        size = struct.unpack("<I", webp_bytes[pos + 4 : pos + 8])[0]
        payload = webp_bytes[pos + 8 : pos + 8 + size]
        if fourcc == b"ANMF" and len(payload) >= 15:
            dur = payload[12] | (payload[13] << 8) | (payload[14] << 16)
            durs.append(max(20, dur))
        pos += 8 + size + (size & 1)
    return durs


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def save_imageset(group_dir: Path, asset_name: str, image: Image.Image) -> None:
    imageset_dir = group_dir / f"{asset_name}.imageset"
    imageset_dir.mkdir(parents=True, exist_ok=True)
    png_filename = f"{asset_name}.png"
    image.save(imageset_dir / png_filename, format="PNG", optimize=True)
    write_json(
        imageset_dir / "Contents.json",
        {
            "images": [{"filename": png_filename, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {
                "preserves-vector-representation": False,
                "template-rendering-intent": "original",
            },
        },
    )


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

    solo_count = 0
    for pet_key, sheet_map in PETS.items():
        loaded_sheets = {
            kind: Image.open(path).convert("RGBA")
            for kind, path in sheet_map.items()
        }
        for action_key, sheet_kind, row_idx, cols in SOLO_ACTIONS:
            sheet = loaded_sheets[sheet_kind]
            raw_cells = [
                sheet.crop((c * CELL_W, row_idx * CELL_H, (c + 1) * CELL_W, (row_idx + 1) * CELL_H))
                for c in cols
            ]
            bboxes = [c.getbbox() for c in raw_cells if c.getbbox() is not None]
            assert bboxes, f"No visible pixels for {pet_key} {action_key}"
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
                save_imageset(sprites_group, asset_name, square)
                solo_count += 1

    print(f"[OK] Sliced {solo_count} solo @3x sprite frames ({TARGET_CANVAS}x{TARGET_CANVAS}px)")

    duo_meta = json.loads(DUO_META_PATH.read_text(encoding="utf-8"))
    duo_sheet = Image.open(DUO_SHEET_PATH).convert("RGBA")
    duo_count = 0

    for anim in duo_meta["animations"]:
        row_idx = anim["row"] - 1
        key = anim["key"]
        n_frames = anim["frames"]
        raw_cells = [
            duo_sheet.crop((c * DUO_CELL_W, row_idx * DUO_CELL_H, (c + 1) * DUO_CELL_W, (row_idx + 1) * DUO_CELL_H))
            for c in range(n_frames)
        ]
        bboxes = [c.getbbox() for c in raw_cells if c.getbbox() is not None]
        assert bboxes, f"No visible pixels for duo {key}"
        u_left = min(b[0] for b in bboxes)
        u_top = min(b[1] for b in bboxes)
        u_right = max(b[2] for b in bboxes)
        u_bottom = max(b[3] for b in bboxes)

        u_w = u_right - u_left
        u_h = u_bottom - u_top

        pad = 6
        avail_w = DUO_TARGET_W - pad * 2
        avail_h = DUO_TARGET_H - pad * 2
        scale = min(avail_w / u_w, avail_h / u_h)
        scaled_w = max(1, round(u_w * scale))
        scaled_h = max(1, round(u_h * scale))
        dst_x = (DUO_TARGET_W - scaled_w) // 2
        dst_y = (DUO_TARGET_H - scaled_h) // 2

        for frame_idx, cell in enumerate(raw_cells):
            cropped_union = cell.crop((u_left, u_top, u_right, u_bottom))
            resized = cropped_union.resize((scaled_w, scaled_h), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (DUO_TARGET_W, DUO_TARGET_H), (0, 0, 0, 0))
            canvas.alpha_composite(resized, (dst_x, dst_y))

            asset_name = f"duo_{key}_{frame_idx}"
            save_imageset(sprites_group, asset_name, canvas)
            duo_count += 1

    print(f"[OK] Sliced {duo_count} combined duo @3x sprite frames ({DUO_TARGET_W}x{DUO_TARGET_H}px)")

    long_skits_group = XCASSETS_DIR / "LongSkits"
    write_json(long_skits_group / "Contents.json", {"info": {"author": "xcode", "version": 1}})

    skits_meta = json.loads(LONG_SKITS_MANIFEST.read_text(encoding="utf-8"))
    skit_beat_count = 0
    skit_webp_bytes_total = 0

    for skit in skits_meta["skits"]:
        raw_slug = skit["slug"]  # e.g. "01_kibble_heist_chase"
        clean_key = raw_slug.split("_", 1)[1] if "_" in raw_slug else raw_slug
        dataset_key = f"skit_{clean_key}"

        webp_src = LONG_SKITS_DIR / f"{raw_slug}.webp"
        webp_bytes = webp_src.read_bytes()
        durs = extract_webp_anmf_durations(webp_bytes)

        all_frames: list[Image.Image] = []
        with Image.open(webp_src) as im:
            n_f = getattr(im, "n_frames", 1)
            for idx in range(n_f):
                im.seek(idx)
                all_frames.append(im.convert("RGBA"))

        if len(durs) != len(all_frames):
            durs = [skit.get("frameDurationMs", 85)] * len(all_frames)

        # 1. Bundle full-length smooth RGBA animated WebP dataset for in-app playback
        resized_frames = [
            f.resize((SKIT_WEBP_W, SKIT_WEBP_H), Image.Resampling.LANCZOS)
            for f in all_frames
        ]
        dataset_dir = long_skits_group / f"{dataset_key}.dataset"
        dataset_dir.mkdir(parents=True, exist_ok=True)
        out_webp_name = f"{dataset_key}.webp"
        out_webp_path = dataset_dir / out_webp_name
        resized_frames[0].save(
            out_webp_path,
            format="WEBP",
            save_all=True,
            append_images=resized_frames[1:],
            duration=durs,
            loop=0,
            quality=86,
            method=4,
        )
        skit_webp_bytes_total += out_webp_path.stat().st_size
        write_json(
            dataset_dir / "Contents.json",
            {
                "data": [{"filename": out_webp_name, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            },
        )

        # 2. Slice 6 evenly timed 3-act story-beat frames for 6s Dynamic Island / Lock Screen loop
        total_ms = max(1, sum(durs))
        cum_ends: list[int] = []
        acc = 0
        for d in durs:
            acc += d
            cum_ends.append(acc)

        beat_frames: list[Image.Image] = []
        for beat_idx in range(6):
            target_ms = total_ms * (beat_idx + 0.5) / 6.0
            chosen_idx = len(all_frames) - 1
            for f_i, end_ms in enumerate(cum_ends):
                if target_ms <= end_ms:
                    chosen_idx = f_i
                    break
            beat_frames.append(all_frames[chosen_idx])

        bboxes = [f.getbbox() for f in all_frames if f.getbbox() is not None]
        assert bboxes, f"No visible pixels in skit {raw_slug}"
        u_left = min(b[0] for b in bboxes)
        u_top = min(b[1] for b in bboxes)
        u_right = max(b[2] for b in bboxes)
        u_bottom = max(b[3] for b in bboxes)

        u_w = u_right - u_left
        u_h = u_bottom - u_top

        pad = 6
        avail_w = DUO_TARGET_W - pad * 2
        avail_h = DUO_TARGET_H - pad * 2
        scale = min(avail_w / u_w, avail_h / u_h)
        scaled_w = max(1, round(u_w * scale))
        scaled_h = max(1, round(u_h * scale))
        dst_x = (DUO_TARGET_W - scaled_w) // 2
        dst_y = (DUO_TARGET_H - scaled_h) // 2

        for beat_idx, bframe in enumerate(beat_frames):
            cropped_union = bframe.crop((u_left, u_top, u_right, u_bottom))
            resized = cropped_union.resize((scaled_w, scaled_h), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (DUO_TARGET_W, DUO_TARGET_H), (0, 0, 0, 0))
            canvas.alpha_composite(resized, (dst_x, dst_y))

            asset_name = f"duo_{dataset_key}_{beat_idx}"
            save_imageset(sprites_group, asset_name, canvas)
            skit_beat_count += 1

    print(
        f"[OK] Bundled 10 ultra-rare long skits ({skit_webp_bytes_total // 1024} KB WebP datasets + "
        f"{skit_beat_count} Dynamic Island 6-beat frames)"
    )


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

    alfie_sheet = Image.open(PETS["alfie"]["base"]).convert("RGBA")
    teddy_sheet = Image.open(PETS["teddy"]["base"]).convert("RGBA")
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
    if RESOURCES_DIR.exists():
        shutil.rmtree(RESOURCES_DIR)
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    gate_font_2s = RESOURCES_DIR / "PetTimerGate-Regular.ttf"
    build_timer_gate_font(gate_font_2s, family_name="PetTimerGate", cycle_seconds=2)
    verify_two_stack_animation(gate_font_2s, cycle_seconds=2.0, frame_counts=(2, 4, 6))

    gate_font_6s = RESOURCES_DIR / "PetTimerGate6s-Regular.ttf"
    build_timer_gate_font(gate_font_6s, family_name="PetTimerGate6s", cycle_seconds=6)
    verify_two_stack_animation(gate_font_6s, cycle_seconds=6.0, frame_counts=(2, 6))

    slice_sprites()
    generate_app_icon()
