#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""Build multi-color logo models: one traced SVG per filament, then a Bambu 3MF.

LOGOS are plaques: the logo raised on a base. MARKS have no base: the logo's
symbol, or its wordmark when it has no symbol, extruded on its own. AVATARS are
marks raised on a round base.

    original ─► large raster ─► label each pixel with a filament
                                        │
             ┌──────────────────────────┘
             ▼
    logos/<slug>/<layer>.svg ─► <slug>.scad ─► OpenSCAD ─► per-part meshes
                                                               │
                         exports/<slug>.3mf (one part per filament) ◄─┘

Usage: build_logos.py [slug ...]
"""

import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass, replace
from pathlib import Path
from xml.sax.saxutils import quoteattr

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

SRC_DIR = Path(__file__).resolve().parent
ORIGINAL_DIR = SRC_DIR / "logos" / "original"
LOGOS_DIR = SRC_DIR / "logos"
EXPORT_DIR = SRC_DIR.parent / "exports"
PROJECT_SETTINGS_TEMPLATE = SRC_DIR / "bambu_project_settings.json"

OPENSCAD = "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD"

MAX_FILAMENTS = 4
RASTER_WIDTH = 3000
MIN_CLEAN_RADIUS_PX = 3
TURD_SIZE_PX = 20
BED_CENTER_MM = 128
THUMBNAIL_PX = 512
DEFAULT_FLUSH_VOLUME = "280"
FLUSH_VECTOR_ENTRIES_PER_FILAMENT = 2

# Bambu Studio cannot save a project back out unless its plate lists these.
PLATE_THUMBNAIL = "Metadata/plate_1.png"
NO_LIGHT_THUMBNAIL = "Metadata/plate_no_light_1.png"
TOP_THUMBNAIL = "Metadata/top_1.png"
PICK_THUMBNAIL = "Metadata/pick_1.png"

# Overrides for the template, which was saved from a part tuned for strength.
# The tower position keeps a 4-filament tower on the bed, clear of a centered plaque.
PLAQUE_PRINT_SETTINGS = {
    "wall_loops": "2",
    "sparse_infill_density": "15%",
    "wipe_tower_x": ["200"],
    "wipe_tower_y": ["170"],
}

WHITE = "#FFFFFF"
BLACK = "#000000"
# For a mark with white ink: white on a white matte would print as a hole.
MAGENTA = "#FF00FF"

MARK_WIDTH = 50
WORDMARK_WIDTH = 70
TIE_WIDTH_MM = 2
TIE_ANCHOR_RADIUS_MM = 0.75
BACK_PART = "back"
AVATAR_DIAMETER_MM = 60
AVATAR_MARGIN_MM = 3


@dataclass(frozen=True)
class Layer:
    """A raised filament. `sources` are the logo colors it prints everywhere.

    `area_sources` print only right of `x_min` (a fraction of the original), so
    one logo color can print differently in different areas.
    """

    name: str
    color: str
    sources: tuple[str, ...]
    area_sources: tuple[str, ...] = ()
    x_min: float = 0.0


@dataclass(frozen=True)
class Logo:
    """`matte` is the color behind transparent pixels. Pick one that differs
    from every logo color: a white wordmark needs a black matte.

    `base_sources` are logo colors that print as the bare base.
    `dropped_sources` are logo colors that do not print, such as a wordmark.

    With no base (`base` is None), loose pieces need joining. By default, bars in
    the logo's colors do that. `tie_color` instead adds a thin back layer in that
    color: the logo's outline plus the bars. It takes one filament.

    `avatar_diameter` makes the base a circle, and sizes the logo to fit inside,
    so `width` has no effect.

    `x_range` keeps part of the logo, as fractions of its inked width. Use it to
    drop text that has the same color as the symbol.
    """

    slug: str
    original: str
    width: int
    base: str | None
    layers: tuple[Layer, ...]
    matte: str = WHITE
    base_sources: tuple[str, ...] = ()
    dropped_sources: tuple[str, ...] = ()
    x_range: tuple[float, float] = (0.0, 1.0)
    tie_color: str | None = None
    avatar_diameter: int | None = None


LOGOS = (
    Logo(
        "ces_utility_solutions",
        "ces_utility_solutions.png",
        80,
        WHITE,
        (
            Layer("blue", "#005F8E", ("#005F8E",)),
            Layer("black", BLACK, (BLACK,)),
        ),
    ),
    Logo(
        "edwin",
        "edwin.svg",
        70,
        "#0D204C",
        (Layer("beige", "#F2F0EA", ("#F2F0EA",)),),
        matte=BLACK,
    ),
    Logo(
        "interflexion",
        "interflexion.png",
        70,
        WHITE,
        (
            Layer("blue", "#055BD5", ("#055BD5",)),
            Layer("purple", "#7613FA", ("#9E15F7", "#7613FA")),
            Layer("green", "#1CC89E", ("#1CC89E", "#0EBBBD", "#2FD17D")),
        ),
    ),
    Logo(
        "issue_voter",
        "issue_voter.png",
        70,
        WHITE,
        (
            Layer("teal", "#027F9D", ("#027F9D",)),
            Layer("red", "#C02C33", ("#C02C33",)),
        ),
    ),
    Logo("keel", "keel.svg", 70, WHITE, (Layer("blue", "#3CB5E6", (BLACK,)),)),
    Logo("lula", "lula.svg", 70, WHITE, (Layer("green", "#28B97B", ("#28B97B",)),)),
    Logo(
        "openfield",
        "openfield.png",
        100,
        "#070708",
        (
            Layer("green", "#046307", ("#046307", "#0A520D")),
            Layer("blue", "#0073BA", ("#0073BA", "#085C90")),
            # The wordmark is black in the original. A black base would hide it.
            Layer(
                "yellow",
                "#FEC905",
                ("#FEC905",),
                area_sources=("#070708", "#18291F"),
                x_min=0.29,
            ),
        ),
        base_sources=("#070708", "#18291F"),
    ),
    Logo(
        "pine_park_health",
        "pine_park_health.svg",
        100,
        WHITE,
        (Layer("green", "#16372C", ("#16372C",)),),
    ),
    Logo(
        "sugar_living",
        "sugar_living.svg",
        70,
        WHITE,
        (
            Layer("navy", "#22303E", ("#22303E",)),
            Layer("blue", "#65CDF9", ("#3FC1F8", "#65CDF9", "#89DAFA")),
        ),
    ),
    Logo(
        "syncari",
        "syncari.svg",
        70,
        "#111111",
        (
            Layer("blue", "#3391EF", ("#3391EF",)),
            Layer("white", WHITE, (WHITE,)),
        ),
        matte=BLACK,
    ),
    Logo(
        "zur_institute",
        "zur_institute.jpg",
        100,
        WHITE,
        (
            Layer("yellow", "#F2BF34", ("#F1E26D", "#F2BF34")),
            Layer("orange", "#F17A21", ("#F39C21", "#F17A21", "#E66255")),
            Layer("black", "#231F20", ("#231F20", "#242021")),
        ),
    ),
)

MARKS = (
    Logo(
        "ces_utility_solutions_mark",
        "ces_utility_solutions.png",
        WORDMARK_WIDTH,
        None,
        (Layer("blue", "#005F8E", ("#005F8E",)),),
        dropped_sources=(BLACK,),
    ),
    Logo(
        "edwin_mark",
        "edwin.svg",
        MARK_WIDTH,
        None,
        (Layer("beige", "#F2F0EA", ("#F2F0EA",)),),
        matte=BLACK,
        x_range=(0.82, 1.0),
    ),
    Logo(
        "interflexion_mark",
        "interflexion_mark.png",
        MARK_WIDTH,
        None,
        (
            Layer("blue", "#055BD5", ("#055BD5",)),
            Layer("purple", "#7613FA", ("#9E15F7", "#7613FA")),
            Layer("green", "#1CC89E", ("#1CC89E", "#0EBBBD", "#2FD17D")),
        ),
    ),
    Logo(
        "issue_voter_mark",
        "issue_voter.png",
        100,
        None,
        (
            Layer("teal", "#027F9D", ("#027F9D",)),
            Layer("red", "#C02C33", ("#C02C33",)),
        ),
    ),
    Logo(
        "keel_mark",
        "keel.svg",
        WORDMARK_WIDTH,
        None,
        (Layer("blue", "#3CB5E6", (BLACK,)),),
    ),
    Logo(
        "lula_mark",
        "lula.svg",
        WORDMARK_WIDTH,
        None,
        (Layer("green", "#28B97B", ("#28B97B",)),),
    ),
    Logo(
        "openfield_mark",
        "openfield.png",
        MARK_WIDTH,
        None,
        (
            Layer("black", "#070708", ("#070708", "#18291F")),
            Layer("green", "#046307", ("#046307", "#0A520D")),
            Layer("blue", "#0073BA", ("#0073BA", "#085C90")),
            Layer("yellow", "#FEC905", ("#FEC905",)),
        ),
        x_range=(0.0, 0.28),
    ),
    Logo(
        "pine_park_health_mark",
        "pine_park_health_mark.svg",
        MARK_WIDTH,
        None,
        (Layer("green", "#16372C", ("#16372C",)),),
    ),
    Logo(
        "sugar_living_mark",
        "sugar_living.svg",
        MARK_WIDTH,
        None,
        (
            Layer("blue", "#65CDF9", ("#3FC1F8", "#65CDF9", "#89DAFA")),
            Layer("white", WHITE, (WHITE,)),
        ),
        matte=MAGENTA,
        dropped_sources=("#22303E",),
    ),
    Logo(
        "syncari_mark",
        "syncari.svg",
        MARK_WIDTH,
        None,
        (Layer("blue", "#3391EF", ("#3391EF",)),),
    ),
    Logo(
        "zur_institute_mark",
        "zur_institute.jpg",
        MARK_WIDTH,
        None,
        (
            Layer("yellow", "#F2BF34", ("#F1E26D", "#F2BF34")),
            Layer("orange", "#F17A21", ("#F39C21", "#F17A21", "#E66255")),
        ),
        dropped_sources=("#231F20", "#242021"),
    ),
)

AVATAR_BASES = {
    "ces_utility_solutions": WHITE,
    "edwin": "#0D204C",
    "interflexion": WHITE,
    "issue_voter": WHITE,
    "keel": WHITE,
    "pine_park_health": WHITE,
}

AVATARS = tuple(
    replace(
        mark,
        slug=mark.slug.replace("_mark", "_avatar"),
        base=AVATAR_BASES[mark.slug.removesuffix("_mark")],
        avatar_diameter=AVATAR_DIAMETER_MM,
    )
    for mark in MARKS
    if mark.slug.removesuffix("_mark") in AVATAR_BASES
)

ALL_MODELS = (*LOGOS, *MARKS, *AVATARS)


def run(*args: str | Path) -> None:
    subprocess.run([str(arg) for arg in args], check=True, capture_output=True)


def filament_colors(logo: Logo) -> list[str]:
    under = [color for color in (logo.base, logo.tie_color) if color is not None]

    return [*under, *(layer.color for layer in logo.layers)]


def part_names(logo: Logo) -> list[str]:
    """The parts of a model, in the same order as filament_colors."""
    under = {"base": logo.base, BACK_PART: logo.tie_color}

    return [
        *(name for name, color in under.items() if color is not None),
        *(layer.name for layer in logo.layers),
    ]


def hex_to_rgb(color: str) -> tuple[int, int, int]:
    value = color.lstrip("#")

    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def load_raster(logo: Logo, tmp: Path) -> tuple[np.ndarray, float]:
    """Return an RGB array on the logo's matte, and how far the original was enlarged."""
    path = ORIGINAL_DIR / logo.original
    scale = 1.0

    if path.suffix == ".svg":
        raster = tmp / "raster.png"
        run("rsvg-convert", "-w", RASTER_WIDTH, path, "-o", raster)
        image = Image.open(raster).convert("RGBA")
    else:
        image = Image.open(path).convert("RGBA")
        scale = RASTER_WIDTH / image.width
        height = round(image.height * scale)
        image = image.resize((RASTER_WIDTH, height), Image.Resampling.BICUBIC)

    matte = Image.new("RGBA", image.size, hex_to_rgb(logo.matte) + (255,))

    return np.asarray(Image.alpha_composite(matte, image).convert("RGB")), scale


def label_pixels(logo: Logo, rgb: np.ndarray, scale: float) -> np.ndarray:
    """Give each pixel a layer index: 0 is the base, N is logo.layers[N - 1]."""
    sources = [logo.matte, *logo.base_sources, *logo.dropped_sources]
    for layer in logo.layers:
        for color in (*layer.sources, *layer.area_sources):
            if color not in sources:
                sources.append(color)

    palette = np.array([hex_to_rgb(color) for color in sources], dtype=np.int32)
    width = rgb.shape[1]
    nearest = np.empty(rgb.shape[:2], dtype=np.uint8)

    # One row at a time: a full-image distance table would need gigabytes.
    for row in range(rgb.shape[0]):
        delta = rgb[row, :, None, :].astype(np.int32) - palette
        nearest[row] = np.argmin((delta**2).sum(axis=2), axis=1)

    labels = np.zeros(rgb.shape[:2], dtype=np.uint8)
    for index, layer in enumerate(logo.layers, start=1):
        for color in layer.sources:
            labels[nearest == sources.index(color)] = index

        for color in layer.area_sources:
            area = nearest == sources.index(color)
            area[:, : int(layer.x_min * width)] = False
            labels[area] = index

    dropped_label = len(logo.layers) + 1
    for color in logo.dropped_sources:
        labels[nearest == sources.index(color)] = dropped_label

    classes = remove_edge_fringes(labels, nearest, sources.index(logo.matte), scale)
    classes[classes == dropped_label + BASE_INK_CLASS] = 0

    return classes


# label_pixels returns 0 for the matte, this for ink that prints as the base,
# and the next values for logo.layers in order.
BASE_INK_CLASS = 1


def remove_edge_fringes(
    labels: np.ndarray, nearest: np.ndarray, matte_index: int, scale: float
) -> np.ndarray:
    """Blended edge pixels can match an unrelated color (black on yellow reads as
    green). Drop thin slivers of each color and give them to the closest survivor.

    The matte/ink split is cleaned as its own class, so a sliver of base-colored
    ink next to the matte does not count as the base and vice versa.
    """
    radius = max(MIN_CLEAN_RADIUS_PX, round(scale))
    disk = np.hypot(*np.ogrid[-radius : radius + 1, -radius : radius + 1]) <= radius

    classes = labels.astype(np.int16) + 1
    classes[nearest == matte_index] = 0

    kept = np.zeros(classes.shape, dtype=bool)
    for value in np.unique(classes):
        kept |= ndimage.binary_opening(classes == value, structure=disk)

    closest = ndimage.distance_transform_edt(
        ~kept, return_distances=False, return_indices=True
    )
    classes = classes[tuple(closest)]

    return classes


def trim_to_ink(classes: np.ndarray) -> np.ndarray:
    rows = np.flatnonzero((classes != 0).any(axis=1))
    cols = np.flatnonzero((classes != 0).any(axis=0))

    return classes[rows[0] : rows[-1] + 1, cols[0] : cols[-1] + 1]


def crop_to_range(classes: np.ndarray, x_range: tuple[float, float]) -> np.ndarray:
    width = classes.shape[1]

    return classes[:, int(x_range[0] * width) : int(x_range[1] * width)]


def tie_pieces(
    classes: np.ndarray, bar_px: int, anchor_radius_px: float
) -> dict[int, np.ndarray]:
    """Plan bars that join a mark's loose pieces, so it prints as one object.

    Starting from the largest piece, each step bridges the shortest gap to a piece
    not joined yet:

        ██████  ━━  ████      ━━ bar, low in the mark and owned by the piece
        ██████      ████         that it reaches out from

    Bars anchor where a piece is at least 2 x `anchor_radius_px` thick, because a
    bar on a thin tip would snap the tip off. A piece with no part that thick
    anchors anywhere.

    Returns one mask of bars for each class that owns any.
    """
    ink = classes != 0
    pieces, count = ndimage.label(ink, structure=np.ones((3, 3)))
    if count == 1:
        return {}

    anchors = ndimage.distance_transform_edt(ink) >= anchor_radius_px
    for piece in set(range(1, count + 1)) - set(np.unique(pieces[anchors]).tolist()):
        anchors[pieces == piece] = True

    sizes = ndimage.sum_labels(ink, pieces, range(1, count + 1))
    joined = pieces == int(np.argmax(sizes)) + 1
    drawings: dict[int, Image.Image] = {}

    for _ in range(count - 1):
        distance, closest = ndimage.distance_transform_edt(
            ~(joined & anchors), return_indices=True
        )
        loose = anchors & ~joined
        row, col = np.unravel_index(
            np.argmin(np.where(loose, distance, np.inf)), classes.shape
        )
        target = closest[:, row, col]

        # Run each bar past both ends, so that it overlaps the pieces it joins.
        reach = np.array((col, row)) - target[::-1]
        reach = reach / np.linalg.norm(reach) * bar_px / 2
        start = np.array((col, row)) + reach
        end = target[::-1] - reach

        owner = int(classes[row, col])
        canvas = drawings.setdefault(
            owner, Image.new("1", (classes.shape[1], classes.shape[0]))
        )
        ImageDraw.Draw(canvas).line(
            [tuple(start.tolist()), tuple(end.tolist())], fill=1, width=bar_px
        )

        joined |= pieces == pieces[row, col]

    return {owner: np.asarray(canvas) for owner, canvas in drawings.items()}


def trace_layer(mask: np.ndarray, output: Path, tmp: Path) -> None:
    pbm = tmp / "mask.pbm"
    Image.fromarray(~mask).save(pbm)

    run(
        "potrace",
        "--svg",
        "--resolution",
        "72",
        "--turdsize",
        TURD_SIZE_PX,
        "--output",
        output,
        pbm,
    )


def avatar_logo_width(classes: np.ndarray, diameter: int) -> float:
    """The logo width that keeps all ink inside the circle, inside the margin."""
    rows, cols = np.nonzero(classes)
    height, width = classes.shape
    radius_px = np.hypot(rows - height / 2, cols - width / 2).max()

    return round(float((diameter / 2 - AVATAR_MARGIN_MM) * width / radius_px), 2)


def write_scad(
    logo: Logo, frame: tuple[int, int], width: float, tied: set[str]
) -> Path:
    if logo.base is None:
        module = "logo_mark"
        extra_lines = ""
        if logo.tie_color is not None:
            has_ties = str(BACK_PART in tied).lower()
            extra_lines = (
                f'    back_color = "{logo.tie_color}",\n'
                f"    back_has_ties = {has_ties},\n"
            )

        rows = [
            f'["{layer.name}", "{layer.color}", {str(layer.name in tied).lower()}]'
            for layer in logo.layers
        ]
    else:
        module = "logo_plaque"
        extra_lines = f'    base_color = "{logo.base}",\n'
        if logo.avatar_diameter is not None:
            extra_lines += f"    diameter = {logo.avatar_diameter},\n"

        rows = [f'["{layer.name}", "{layer.color}"]' for layer in logo.layers]

    path = SRC_DIR / f"{logo.slug}.scad"

    path.write_text(
        f"// Generated by build_logos.py. Edit the LOGOS table there.\n"
        f"use <lib/logo_plaque.scad>\n\n"
        f'part = "all";\n\n'
        f"{module}(\n"
        f'    dir = "logos/{logo.slug}",\n'
        f"    frame = [{frame[0]}, {frame[1]}],\n"
        f"    width = {width},\n"
        f"{extra_lines}"
        f"    layers = [{', '.join(rows)}],\n"
        f"    part = part\n"
        f");\n"
    )

    return path


def trace_logo(logo: Logo, tmp: Path) -> Path:
    if len(filament_colors(logo)) > MAX_FILAMENTS:
        raise ValueError(f"{logo.slug} needs more than {MAX_FILAMENTS} filaments")

    rgb, scale = load_raster(logo, tmp)
    classes = label_pixels(logo, rgb, scale)

    classes = trim_to_ink(crop_to_range(trim_to_ink(classes), logo.x_range))

    layer_dir = LOGOS_DIR / logo.slug
    layer_dir.mkdir(exist_ok=True)

    # A changed setting can leave tie outlines that the model no longer uses.
    for stale in layer_dir.glob("*.svg"):
        stale.unlink()

    for index, layer in enumerate(logo.layers, start=1):
        trace_layer(
            classes == index + BASE_INK_CLASS, layer_dir / f"{layer.name}.svg", tmp
        )

    tied = set()
    if logo.base is None:
        px_per_mm = classes.shape[1] / logo.width
        bars = tie_pieces(
            classes, round(TIE_WIDTH_MM * px_per_mm), TIE_ANCHOR_RADIUS_MM * px_per_mm
        )

        if logo.tie_color is not None and bars:
            all_bars = np.logical_or.reduce(list(bars.values()))
            trace_layer(all_bars, layer_dir / "ties.svg", tmp)
            tied.add(BACK_PART)

        if logo.tie_color is None:
            for owner, mask in bars.items():
                layer = logo.layers[owner - BASE_INK_CLASS - 1]
                trace_layer(mask, layer_dir / f"{layer.name}_ties.svg", tmp)
                tied.add(layer.name)

    width = logo.width
    if logo.avatar_diameter is not None:
        width = avatar_logo_width(classes, logo.avatar_diameter)

    return write_scad(logo, (classes.shape[1], classes.shape[0]), width, tied)


def render_part(scad: Path, part: str, output: Path) -> None:
    run(
        OPENSCAD,
        "--backend=manifold",
        "--export-format=binstl",
        "-D",
        f'part="{part}"',
        "-o",
        output,
        scad,
    )


def read_binary_stl(path: Path) -> tuple[np.ndarray, np.ndarray]:
    """Return unique vertices and triangles that index them."""
    record = np.dtype(
        [("normal", "<f4", 3), ("corners", "<f4", (3, 3)), ("attr", "<u2")]
    )
    facets = np.fromfile(path, dtype=record, offset=84)
    corners = facets["corners"].reshape(-1, 3)
    vertices, inverse = np.unique(corners, axis=0, return_inverse=True)

    return vertices, inverse.reshape(-1, 3)


def mesh_xml(object_id: int, vertices: np.ndarray, triangles: np.ndarray) -> str:
    vertex_rows = "".join(
        f'<vertex x="{x:.5f}" y="{y:.5f}" z="{z:.5f}"/>' for x, y, z in vertices
    )
    triangle_rows = "".join(
        f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in triangles
    )

    return (
        f'<object id="{object_id}" type="model"><mesh>'
        f"<vertices>{vertex_rows}</vertices>"
        f"<triangles>{triangle_rows}</triangles>"
        f"</mesh></object>"
    )


def project_settings(colors: list[str]) -> str:
    """Resize the Bambu settings template to this logo's filament count.

    Bambu Studio crashes on a file with partial settings, and refuses to slice
    when a list has the wrong length. Lists come in three shapes:

      per filament  one entry each             (filament_colour)
      per variant   filament_self_index maps   (filament_flow_ratio)
                    entries to filaments
      flush         n x n matrix, 2n vector    (flush_volumes_matrix)

    Every filament copies the first profile, so one plaque never mixes materials
    that need different temperatures.
    """
    settings = json.loads(PROJECT_SETTINGS_TEMPLATE.read_text())
    filament_entries = len(settings["filament_colour"])
    variant_entries = len(settings["filament_self_index"])
    count = len(colors)

    for key, value in settings.items():
        if not isinstance(value, list):
            continue

        is_variant_list = key.startswith("filament_") and len(value) == variant_entries
        if len(value) == filament_entries or is_variant_list:
            settings[key] = value[:1] * count

    settings["filament_colour"] = colors
    settings["filament_self_index"] = [str(i) for i in range(1, count + 1)]
    settings["flush_volumes_matrix"] = [
        "0" if row == col else DEFAULT_FLUSH_VOLUME
        for row in range(count)
        for col in range(count)
    ]
    settings["flush_volumes_vector"] = settings["flush_volumes_vector"][:1] * (
        count * FLUSH_VECTOR_ENTRIES_PER_FILAMENT
    )

    return json.dumps(settings | PLAQUE_PRINT_SETTINGS, indent=1)


def render_thumbnail(scad: Path, output: Path) -> None:
    run(
        OPENSCAD,
        "--backend=manifold",
        "--render",
        "--autocenter",
        "--viewall",
        "--camera=0,0,0,0,0,0,0",
        "--colorscheme=Tomorrow",
        f"--imgsize={THUMBNAIL_PX},{THUMBNAIL_PX}",
        "-o",
        output,
        scad,
    )


def write_3mf(
    logo: Logo, parts: list[tuple[str, Path]], thumbnail: Path, output: Path
) -> None:
    """Write the Bambu project layout: one object, one part per filament, in a
    file that Bambu Studio opens with each part already assigned to its filament.
    """
    core = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    production = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"
    relationship = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    relationships = "http://schemas.openxmlformats.org/package/2006/relationships"
    xml_header = '<?xml version="1.0" encoding="UTF-8"?>\n'
    object_path = "/3D/Objects/object_1.model"
    assembly_id = len(parts) + 1

    meshes = "".join(
        mesh_xml(part_id, *read_binary_stl(path))
        for part_id, (_, path) in enumerate(parts, start=1)
    )
    components = "".join(
        f'<component p:path="{object_path}" objectid="{part_id}"/>'
        for part_id in range(1, assembly_id)
    )
    part_settings = "".join(
        f'<part id="{part_id}" subtype="normal_part">'
        f'<metadata key="name" value={quoteattr(name)}/>'
        f'<metadata key="extruder" value="{part_id}"/>'
        f"</part>"
        for part_id, (name, _) in enumerate(parts, start=1)
    )
    colors = filament_colors(logo)
    filament_maps = " ".join("1" for _ in colors)

    files = {
        "[Content_Types].xml": (
            f"{xml_header}<Types "
            'xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType='
            '"application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="model" ContentType='
            '"application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>'
            "</Types>"
        ),
        "_rels/.rels": (
            f'{xml_header}<Relationships xmlns="{relationships}">'
            f'<Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="{relationship}"/>'
            "</Relationships>"
        ),
        "3D/_rels/3dmodel.model.rels": (
            f'{xml_header}<Relationships xmlns="{relationships}">'
            f'<Relationship Target="{object_path}" Id="rel-1" Type="{relationship}"/>'
            "</Relationships>"
        ),
        "3D/3dmodel.model": (
            f'{xml_header}<model unit="millimeter" xml:lang="en-US" xmlns="{core}" '
            f'xmlns:BambuStudio="http://schemas.bambulab.com/package/2021" '
            f'xmlns:p="{production}" requiredextensions="p">'
            '<metadata name="Application">BambuStudio-02.07.01.57</metadata>'
            '<metadata name="BambuStudio:3mfVersion">1</metadata>'
            f'<resources><object id="{assembly_id}" type="model">'
            f"<components>{components}</components></object></resources>"
            f'<build><item objectid="{assembly_id}" '
            f'transform="1 0 0 0 1 0 0 0 1 {BED_CENTER_MM} {BED_CENTER_MM} 0"/></build>'
            "</model>"
        ),
        object_path.lstrip("/"): (
            f'{xml_header}<model unit="millimeter" xml:lang="en-US" xmlns="{core}">'
            f"<resources>{meshes}</resources><build/></model>"
        ),
        "Metadata/model_settings.config": (
            f'{xml_header}<config><object id="{assembly_id}">'
            f'<metadata key="name" value={quoteattr(logo.slug)}/>'
            '<metadata key="extruder" value="1"/>'
            f"{part_settings}</object>"
            '<plate><metadata key="plater_id" value="1"/>'
            '<metadata key="plater_name" value=""/>'
            '<metadata key="locked" value="false"/>'
            '<metadata key="filament_map_mode" value="Auto For Flush"/>'
            f'<metadata key="filament_maps" value="{filament_maps}"/>'
            f'<metadata key="thumbnail_file" value="{PLATE_THUMBNAIL}"/>'
            f'<metadata key="thumbnail_no_light_file" value="{NO_LIGHT_THUMBNAIL}"/>'
            f'<metadata key="top_file" value="{TOP_THUMBNAIL}"/>'
            f'<metadata key="pick_file" value="{PICK_THUMBNAIL}"/>'
            f'<model_instance><metadata key="object_id" value="{assembly_id}"/>'
            '<metadata key="instance_id" value="0"/>'
            f'<metadata key="identify_id" value="{assembly_id}"/>'
            "</model_instance></plate>"
            f'<assemble><assemble_item object_id="{assembly_id}" instance_id="0" '
            'transform="1 0 0 0 1 0 0 0 1 0 0 0" offset="0 0 0"/></assemble>'
            "</config>"
        ),
        "Metadata/project_settings.config": project_settings(colors),
    }

    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(name, content)

        for name in (
            PLATE_THUMBNAIL,
            NO_LIGHT_THUMBNAIL,
            TOP_THUMBNAIL,
            PICK_THUMBNAIL,
        ):
            archive.write(thumbnail, name)


def export_logo(logo: Logo, scad: Path, tmp: Path) -> None:
    parts = []
    for name in part_names(logo):
        stl = tmp / f"{name}.stl"
        render_part(scad, name, stl)
        parts.append((name, stl))

    thumbnail = tmp / "thumbnail.png"
    render_thumbnail(scad, thumbnail)

    EXPORT_DIR.mkdir(exist_ok=True)
    write_3mf(logo, parts, thumbnail, EXPORT_DIR / f"{logo.slug}.3mf")
    render_part(scad, "all", EXPORT_DIR / f"{logo.slug}.stl")


def main() -> None:
    wanted = set(sys.argv[1:])
    unknown = wanted - {logo.slug for logo in ALL_MODELS}
    if unknown:
        sys.exit(f"unknown logos: {sorted(unknown)}")

    for logo in ALL_MODELS:
        if wanted and logo.slug not in wanted:
            continue

        print(f"building {logo.slug}", file=sys.stderr)
        tmp = Path(tempfile.mkdtemp())
        try:
            export_logo(logo, trace_logo(logo, tmp), tmp)
        finally:
            shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
