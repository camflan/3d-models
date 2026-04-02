#!/usr/bin/env python3
"""
Topo Panel Generator
====================
Generates DXF files of topographic contour lines and roads for
3D printing debossed panels in OpenSCAD or FreeCAD.

Workflow:
  1. Downloads SRTM elevation data for the target area
  2. Generates contour lines at a configurable interval
  3. Fetches road geometries from OpenStreetMap
  4. Buffers all lines to a printable groove width
  5. Outputs DXF files ready for OpenSCAD import

Usage:
  pip install -r requirements.txt
  python topo_panel_generator.py

Then open panel.scad in OpenSCAD.
"""

import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")  # No GUI needed
import matplotlib.pyplot as plt
import hashlib
import json
import srtm
import ezdxf
import requests
from shapely.geometry import LineString, Polygon, MultiPolygon
from shapely.ops import unary_union
from pathlib import Path


# ============================================================
#  CONFIGURATION — Tweak these to customize your panel
# ============================================================

# Map center — Lawrence, KS
CENTER_LAT = 38.9717
CENTER_LON = -95.2353

# How much area to cover (km from center to each edge)
MAP_RADIUS_KM = 8

# Panel size in mm (10 inches ≈ 254mm)
PANEL_SIZE_MM = 254

# Contour settings
CONTOUR_INTERVAL_M = 20        # Meters between contour lines
CONTOUR_LINE_WIDTH_MM = 0.6    # Width of debossed contour grooves

# Road settings
# OSM highway types — pick from:
#   motorway, trunk, primary, secondary, tertiary,
#   residential, unclassified, service
ROAD_TYPES = ["motorway", "trunk", "primary", "secondary"]
ROAD_LINE_WIDTH_MM = 1.0       # Width of debossed road grooves

# Elevation sampling resolution (NxN grid)
# Higher = more detail but slower. 300-500 is a good range.
GRID_RESOLUTION = 500

# Geometry simplification tolerance (mm). Higher = fewer vertices,
# faster OpenSCAD render but less precise curves.
SIMPLIFY_TOLERANCE_MM = 0.1

# Elevation relief — makes the panel surface follow the terrain
RELIEF_ENABLED = True
RELIEF_HEIGHT_MM = 3.0         # Height range mapped to elevation (min→max becomes 0→this)
RELIEF_RESOLUTION = 400        # Heightmap image resolution (NxN pixels)

# Output directory (relative to this script)
OUTPUT_DIR = "topo_output"


# ============================================================
#  INTERNALS — You probably don't need to change these
# ============================================================

def get_bbox(center_lat, center_lon, radius_km):
    """Calculate geographic bounding box from center point and radius."""
    lat_deg_per_km = 1.0 / 111.0
    lon_deg_per_km = 1.0 / (111.0 * np.cos(np.radians(center_lat)))

    south = center_lat - radius_km * lat_deg_per_km
    north = center_lat + radius_km * lat_deg_per_km
    west = center_lon - radius_km * lon_deg_per_km
    east = center_lon + radius_km * lon_deg_per_km

    return south, north, west, east


def get_elevation_grid(south, north, west, east, resolution):
    """
    Sample elevation data on a regular grid using SRTM.

    First run will download ~25MB tile files to a local cache.
    """
    print(f"  Sampling {resolution}x{resolution} elevation grid...")
    elevation_data = srtm.get_data()

    lats = np.linspace(south, north, resolution)
    lons = np.linspace(west, east, resolution)

    grid = np.zeros((resolution, resolution))
    failed = 0
    for i, lat in enumerate(lats):
        for j, lon in enumerate(lons):
            e = elevation_data.get_elevation(lat, lon)
            if e is not None:
                grid[i, j] = e
            else:
                grid[i, j] = np.nan
                failed += 1
        if (i + 1) % 100 == 0:
            print(f"    ...row {i + 1}/{resolution}")

    # Fill any gaps with nearest neighbor interpolation
    if failed > 0:
        print(f"  Filling {failed} missing elevation points...")
        from scipy.ndimage import generic_filter
        mask = np.isnan(grid)
        if mask.any():
            # Simple fill: replace NaNs with local mean
            def fill_nan(values):
                valid = values[~np.isnan(values)]
                return np.mean(valid) if len(valid) > 0 else 0
            grid = generic_filter(grid, fill_nan, size=3)

    return lons, lats, grid


def generate_contours(lons, lats, elevations, interval):
    """Generate contour polylines from the elevation grid."""
    min_elev = np.floor(elevations.min() / interval) * interval
    max_elev = np.ceil(elevations.max() / interval) * interval
    levels = np.arange(min_elev, max_elev + interval, interval)

    print(f"  Generating contours at {interval}m interval "
          f"({len(levels)} levels from {min_elev:.0f}m to {max_elev:.0f}m)...")

    fig, ax = plt.subplots()
    cs = ax.contour(lons, lats, elevations, levels=levels)
    plt.close(fig)

    contour_lines = []
    for i, level in enumerate(cs.levels):
        if i < len(cs.allsegs):
            for seg in cs.allsegs[i]:
                if len(seg) >= 2:
                    contour_lines.append({
                        "coords": np.array(seg),
                        "elevation": float(level),
                    })

    print(f"  → {len(contour_lines)} contour segments")
    return contour_lines


CACHE_DIR = Path(OUTPUT_DIR) / ".cache"

def _road_cache_key(south, north, west, east, road_types):
    """Deterministic cache key based on query parameters."""
    key = f"{south:.6f},{north:.6f},{west:.6f},{east:.6f}|{'|'.join(sorted(road_types))}"
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def _parse_road_data(data):
    """Parse Overpass JSON response into road segment dicts."""
    nodes = {}
    for elem in data["elements"]:
        if elem["type"] == "node":
            nodes[elem["id"]] = (elem["lon"], elem["lat"])

    roads = []
    for elem in data["elements"]:
        if elem["type"] == "way":
            coords = [nodes[nid] for nid in elem.get("nodes", []) if nid in nodes]
            if len(coords) >= 2:
                roads.append({
                    "coords": np.array(coords),
                    "highway": elem.get("tags", {}).get("highway", "unknown"),
                    "name": elem.get("tags", {}).get("name", ""),
                })
    return roads


def get_roads(south, north, west, east, road_types):
    """Fetch road geometries from OpenStreetMap via Overpass API (cached)."""
    highway_filter = "|".join(road_types)

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"roads_{_road_cache_key(south, north, west, east, road_types)}.json"

    if cache_file.exists():
        print(f"  Using cached road data ({cache_file.name})")
        data = json.loads(cache_file.read_text())
        roads = _parse_road_data(data)
        print(f"  → {len(roads)} road segments")
        return roads

    print(f"  Fetching roads from OSM (types: {highway_filter})...")

    query = f"""
    [out:json][timeout:60];
    way["highway"~"^({highway_filter})$"]({south},{west},{north},{east});
    (._;>;);
    out body;
    """

    try:
        resp = requests.post(
            "https://overpass-api.de/api/interpreter",
            data={"data": query},
            timeout=90,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  ⚠ Could not fetch roads: {e}")
        print(f"    Continuing without roads. You can retry later.")
        return []

    data = resp.json()
    cache_file.write_text(json.dumps(data))

    roads = _parse_road_data(data)
    print(f"  → {len(roads)} road segments")
    return roads


def geo_to_panel_coords(coords, south, north, west, east, panel_size_mm, center_lat):
    """
    Transform geographic (lon, lat) coordinates to panel (mm) coordinates.
    Applies a cos(lat) correction so the map isn't horizontally stretched.
    Centers the result on the panel.
    """
    lat_scale = 111.0  # km per degree of latitude
    lon_scale = 111.0 * np.cos(np.radians(center_lat))  # corrected for latitude

    real_width_km = (east - west) * lon_scale
    real_height_km = (north - south) * lat_scale

    # Scale to fit panel, maintaining aspect ratio
    scale = panel_size_mm / max(real_width_km, real_height_km)

    transformed = np.zeros_like(coords, dtype=float)
    transformed[:, 0] = (coords[:, 0] - west) * lon_scale * scale
    transformed[:, 1] = (coords[:, 1] - south) * lat_scale * scale

    # Center on panel
    rendered_w = real_width_km * scale
    rendered_h = real_height_km * scale
    transformed[:, 0] += (panel_size_mm - rendered_w) / 2
    transformed[:, 1] += (panel_size_mm - rendered_h) / 2

    return transformed


def buffer_lines(coord_sets, width_mm, simplify_tol):
    """
    Buffer a list of polylines to create filled polygons of a given width.
    Merges overlapping results. Returns a single shapely geometry.
    """
    polys = []
    for coords in coord_sets:
        if len(coords) < 2:
            continue
        try:
            line = LineString(coords)
            # cap_style=2 (flat), join_style=2 (miter)
            buffered = line.buffer(width_mm / 2, cap_style=2, join_style=2)
            if not buffered.is_empty:
                polys.append(buffered)
        except Exception:
            continue

    if not polys:
        return None

    merged = unary_union(polys)

    # Morphological closing: dilate then erode to fuse sliver gaps between segments
    closed = merged.buffer(0.15).buffer(-0.15)

    simplified = closed.simplify(simplify_tol, preserve_topology=True)

    cleaned = _remove_small_polygons(simplified)
    return cleaned


MIN_POLYGON_AREA_MM2 = 2.0  # Discard polygons smaller than this (removes buffer artifacts)


def _clean_polygon(poly):
    """Remove small interior rings (holes) that cause groove artifacts."""
    kept_holes = [
        ring for ring in poly.interiors
        if Polygon(ring).area >= MIN_POLYGON_AREA_MM2
    ]
    return Polygon(poly.exterior, kept_holes)


def _remove_small_polygons(geometry):
    """Strip small polygons and small interior rings."""
    if geometry is None or geometry.is_empty:
        return geometry
    if isinstance(geometry, Polygon):
        if geometry.area < MIN_POLYGON_AREA_MM2:
            return None
        return _clean_polygon(geometry)
    # MultiPolygon or GeometryCollection
    kept = []
    for g in geometry.geoms:
        if isinstance(g, Polygon) and g.area >= MIN_POLYGON_AREA_MM2:
            kept.append(_clean_polygon(g))
    if not kept:
        return None
    if len(kept) == 1:
        return kept[0]
    return MultiPolygon(kept)

def write_dxf(geometry, filepath, layer_name="0"):
    """Write a shapely polygon/multipolygon to DXF as closed polylines."""
    doc = ezdxf.new("R2010")
    doc.layers.add(layer_name)
    msp = doc.modelspace()

    poly_count = 0
    skipped = 0

    def add_polygon(poly):
        nonlocal poly_count, skipped
        if poly.area < MIN_POLYGON_AREA_MM2:
            skipped += 1
            return
        # Exterior ring
        coords = list(poly.exterior.coords)
        if len(coords) >= 3:
            msp.add_lwpolyline(
                [(x, y) for x, y in coords],
                close=True,
                dxfattribs={"layer": layer_name},
            )
            poly_count += 1
        # Interior rings (holes) — OpenSCAD handles these correctly
        for interior in poly.interiors:
            coords = list(interior.coords)
            if len(coords) >= 3:
                msp.add_lwpolyline(
                    [(x, y) for x, y in coords],
                    close=True,
                    dxfattribs={"layer": layer_name},
                )
                poly_count += 1

    if geometry is None:
        print(f"  ⚠ No geometry to write for {filepath}")
    elif isinstance(geometry, Polygon):
        add_polygon(geometry)
    elif isinstance(geometry, MultiPolygon):
        for poly in geometry.geoms:
            add_polygon(poly)
    else:
        # Could be GeometryCollection
        for geom in getattr(geometry, "geoms", []):
            if isinstance(geom, Polygon):
                add_polygon(geom)

    doc.saveas(str(filepath))
    skipped_msg = f", {skipped} artifacts removed" if skipped else ""
    print(f"  → {filepath}  ({poly_count} polygons{skipped_msg})")


def write_heightmap(elevations, filepath, resolution, contour_interval):
    """
    Write a grayscale PNG heightmap for OpenSCAD surface().

    Elevations are quantized to contour_interval steps so the surface
    produces flat plateaus with edges aligned to the contour lines.

    Pixel value 0 = lowest elevation, 255 = highest.
    OpenSCAD surface() reads row 0 as y=0 (bottom), which matches our
    lat grid (south at index 0), so no vertical flip needed.
    """
    from PIL import Image
    from scipy.ndimage import zoom

    e_min, e_max = elevations.min(), elevations.max()

    # Quantize to contour intervals: snap each elevation to its contour floor
    quantized = np.floor(elevations / contour_interval) * contour_interval
    q_min, q_max = quantized.min(), quantized.max()

    normalized = (quantized - q_min) / (q_max - q_min) if q_max > q_min else np.zeros_like(quantized)

    # Resample to desired output resolution (use nearest-neighbor to preserve steps)
    if normalized.shape[0] != resolution:
        zoom_factor = resolution / normalized.shape[0]
        normalized = zoom(normalized, zoom_factor, order=0)

    n_steps = int((q_max - q_min) / contour_interval) + 1
    img_data = (normalized * 255).clip(0, 255).astype(np.uint8)
    img = Image.fromarray(img_data, mode="L")
    img.save(str(filepath))
    print(f"  → {filepath}  ({resolution}x{resolution}px, {n_steps} steps, {e_min:.0f}m–{e_max:.0f}m)")


def write_border_dxf(panel_size_mm, filepath):
    """Write a simple border rectangle DXF for reference alignment."""
    doc = ezdxf.new("R2010")
    doc.layers.add("border")
    msp = doc.modelspace()
    s = panel_size_mm
    msp.add_lwpolyline(
        [(0, 0), (s, 0), (s, s), (0, s)],
        close=True,
        dxfattribs={"layer": "border"},
    )
    doc.saveas(str(filepath))
    print(f"  → {filepath}")


# ============================================================
#  MAIN PIPELINE
# ============================================================

def main():
    output = Path(OUTPUT_DIR)
    output.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("  TOPO PANEL GENERATOR")
    print(f"  Center: {CENTER_LAT:.4f}°N, {CENTER_LON:.4f}°W")
    print(f"  Radius: {MAP_RADIUS_KM} km  |  Panel: {PANEL_SIZE_MM} mm")
    print("=" * 60)

    # 1 — Bounding box
    south, north, west, east = get_bbox(CENTER_LAT, CENTER_LON, MAP_RADIUS_KM)
    print(f"\n[1/7] Bounding box: "
          f"{south:.4f}–{north:.4f}°N, {west:.4f}–{east:.4f}°W")

    # 2 — Elevation data
    print("\n[2/7] Elevation data (SRTM)")
    lons, lats, elevations = get_elevation_grid(
        south, north, west, east, GRID_RESOLUTION
    )
    print(f"  Elevation range: {elevations.min():.0f}m – {elevations.max():.0f}m")

    # 3 — Contour lines
    print(f"\n[3/7] Contour generation")
    contours = generate_contours(lons, lats, elevations, CONTOUR_INTERVAL_M)

    # 4 — Roads
    print(f"\n[4/7] Road data (OpenStreetMap)")
    roads = get_roads(south, north, west, east, ROAD_TYPES)

    # 5 — Transform to panel coordinates
    print(f"\n[5/7] Coordinate transform (geo → {PANEL_SIZE_MM}mm panel)")
    contour_mm = [
        geo_to_panel_coords(
            c["coords"], south, north, west, east, PANEL_SIZE_MM, CENTER_LAT
        )
        for c in contours
    ]
    road_mm = [
        geo_to_panel_coords(
            r["coords"], south, north, west, east, PANEL_SIZE_MM, CENTER_LAT
        )
        for r in roads
    ]

    # 6 — Buffer lines to printable groove widths
    print(f"\n[6/7] Buffering geometry")
    print(f"  Contours: {CONTOUR_LINE_WIDTH_MM}mm groove width...")
    contour_geom = buffer_lines(contour_mm, CONTOUR_LINE_WIDTH_MM, SIMPLIFY_TOLERANCE_MM)

    print(f"  Roads: {ROAD_LINE_WIDTH_MM}mm groove width...")
    road_geom = buffer_lines(road_mm, ROAD_LINE_WIDTH_MM, SIMPLIFY_TOLERANCE_MM)

    # 7 — Write output files
    print(f"\n[7/8] Writing DXF files to ./{OUTPUT_DIR}/")
    write_dxf(contour_geom, output / "contours.dxf", layer_name="contours")
    write_dxf(road_geom, output / "roads.dxf", layer_name="roads")
    write_border_dxf(PANEL_SIZE_MM, output / "border.dxf")

    # 8 — Heightmap
    print(f"\n[8/8] Heightmap")
    if RELIEF_ENABLED:
        write_heightmap(elevations, output / "heightmap.png", RELIEF_RESOLUTION, CONTOUR_INTERVAL_M)
    else:
        print("  Skipped (RELIEF_ENABLED = False)")

    # Summary
    print("\n" + "=" * 60)
    print("  DONE!")
    print(f"  Output: ./{OUTPUT_DIR}/contours.dxf")
    print(f"          ./{OUTPUT_DIR}/roads.dxf")
    print(f"          ./{OUTPUT_DIR}/border.dxf")
    if RELIEF_ENABLED:
        print(f"          ./{OUTPUT_DIR}/heightmap.png")
    print()
    print("  Next: open panel.scad in OpenSCAD")
    print("=" * 60)


if __name__ == "__main__":
    main()
