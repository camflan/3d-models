#!/usr/bin/env python3
"""
Topo Panel Generator
====================
Generates DXF files of topographic contour lines, roads, and water
features for 3D printing debossed panels in OpenSCAD.

Workflow:
  1. Downloads SRTM elevation data for the target area
  2. Generates contour lines at a configurable interval
  3. Fetches road and water geometries from OpenStreetMap
  4. Buffers all lines to a printable groove width
  5. Outputs DXF files ready for OpenSCAD import

Usage:
  uv run topo_panel_generator.py

Then open panel.scad in OpenSCAD.
"""

import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
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

# Water settings
# Waterways (line features buffered to a given width)
# OSM waterway types — pick from:
#   river, stream, canal, drain, ditch, brook, tidal_channel
# Width in mm per type (only types listed here are fetched):
WATERWAY_WIDTHS_MM = {
    "river": 3.0,
    "stream": 1.0,
}
# Water bodies (area features using actual polygon shapes from OSM)
# OSM water= types to exclude — pick from:
#   basin, canal, ditch, drain, fishpond, lake, lock, moat, oxbow,
#   pond, reflecting_pool, reservoir, river, salt_pool, sewage,
#   shallow, stream_pool, swamp, swimming_pool, wastewater, wetland
WATER_BODY_EXCLUDE = {"wastewater", "basin", "sewage"}

# Elevation sampling resolution (NxN grid)
# Higher = more detail but slower. 300-500 is a good range.
GRID_RESOLUTION = 500

# Geometry simplification tolerance (mm). Higher = fewer vertices,
# faster OpenSCAD render but less precise curves.
SIMPLIFY_TOLERANCE_MM = 0.1

# Output directory (relative to this script)
OUTPUT_DIR = "topo_output"


# ============================================================
#  INTERNALS — You probably don't need to change these
# ============================================================

CACHE_DIR = Path(OUTPUT_DIR) / ".cache"
MIN_POLYGON_AREA_MM2 = 2.0


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
            if e is not None and e > 0:
                grid[i, j] = e
            else:
                grid[i, j] = np.nan
                failed += 1
        if (i + 1) % 100 == 0:
            print(f"    ...row {i + 1}/{resolution}")

    # Fill any gaps via iterative local mean (expanding window until all filled)
    if failed > 0:
        print(f"  Filling {failed} missing elevation points...")
        from scipy.ndimage import generic_filter
        for window in [3, 5, 9, 15]:
            mask = np.isnan(grid)
            if not mask.any():
                break
            def fill_nan(values):
                valid = values[~np.isnan(values)]
                return np.mean(valid) if len(valid) > 0 else np.nan
            filled = generic_filter(grid, fill_nan, size=window)
            grid[mask] = filled[mask]

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


# --- OSM data fetching (cached) ---

def _cache_key(prefix, south, north, west, east, tags):
    """Deterministic cache key based on query parameters."""
    key = f"{prefix}|{south:.6f},{north:.6f},{west:.6f},{east:.6f}|{'|'.join(sorted(tags))}"
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def _fetch_osm(query, cache_file):
    """Run an Overpass query, returning cached result if available."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    if cache_file.exists():
        print(f"  Using cached data ({cache_file.name})")
        return json.loads(cache_file.read_text())

    try:
        resp = requests.post(
            "https://overpass-api.de/api/interpreter",
            data={"data": query},
            timeout=90,
        )
        resp.raise_for_status()
    except requests.RequestException as e:
        print(f"  ⚠ Could not fetch OSM data: {e}")
        print(f"    Continuing without this layer. You can retry later.")
        return None

    data = resp.json()
    cache_file.write_text(json.dumps(data))
    return data


def _parse_ways(data):
    """Extract way geometries as coordinate arrays from Overpass JSON."""
    nodes = {}
    for elem in data["elements"]:
        if elem["type"] == "node":
            nodes[elem["id"]] = (elem["lon"], elem["lat"])

    ways = []
    for elem in data["elements"]:
        if elem["type"] == "way":
            coords = [nodes[nid] for nid in elem.get("nodes", []) if nid in nodes]
            if len(coords) >= 2:
                ways.append({
                    "coords": np.array(coords),
                    "tags": elem.get("tags", {}),
                })
    return ways


def get_roads(south, north, west, east, road_types):
    """Fetch road geometries from OpenStreetMap via Overpass API (cached)."""
    highway_filter = "|".join(road_types)
    print(f"  Fetching roads from OSM (types: {highway_filter})...")

    cache_file = CACHE_DIR / f"roads_{_cache_key('roads', south, north, west, east, road_types)}.json"

    query = f"""
    [out:json][timeout:60];
    way["highway"~"^({highway_filter})$"]({south},{west},{north},{east});
    (._;>;);
    out body;
    """

    data = _fetch_osm(query, cache_file)
    if data is None:
        return []

    ways = _parse_ways(data)
    print(f"  → {len(ways)} road segments")
    return ways


def get_waterways(south, north, west, east, waterway_widths):
    """Fetch waterway centerlines (rivers, streams) from OSM."""
    types = list(waterway_widths.keys())
    type_filter = "|".join(types)
    print(f"  Fetching waterways from OSM (types: {type_filter})...")

    cache_file = CACHE_DIR / f"waterways_{_cache_key('ww', south, north, west, east, types)}.json"

    query = f"""
    [out:json][timeout:60];
    way["waterway"~"^({type_filter})$"]({south},{west},{north},{east});
    (._;>;);
    out body;
    """

    data = _fetch_osm(query, cache_file)
    if data is None:
        return []

    ways = _parse_ways(data)
    # Attach the configured width based on waterway type
    for w in ways:
        ww_type = w["tags"].get("waterway", "")
        w["width_mm"] = waterway_widths.get(ww_type, 1.0)

    print(f"  → {len(ways)} waterway segments")
    return ways


def get_water_bodies(south, north, west, east, exclude_types):
    """
    Fetch water body area polygons from OSM: natural=water (lakes, ponds)
    and waterway=riverbank (older river area mapping).
    """
    print(f"  Fetching water bodies from OSM...")
    cache_file = CACHE_DIR / f"water_{_cache_key('water', south, north, west, east, ['water', 'riverbank'])}.json"

    query = f"""
    [out:json][timeout:60];
    (
      way["natural"="water"]({south},{west},{north},{east});
      relation["natural"="water"]({south},{west},{north},{east});
      way["waterway"="riverbank"]({south},{west},{north},{east});
      relation["waterway"="riverbank"]({south},{west},{north},{east});
    );
    (._;>;);
    out body;
    """

    data = _fetch_osm(query, cache_file)
    if data is None:
        return []

    water_bodies, excluded = _parse_water_bodies(data, exclude_types)
    if excluded:
        print(f"  → {len(water_bodies)} water polygons ({excluded} excluded)")
    else:
        print(f"  → {len(water_bodies)} water polygons")

    return water_bodies


def _parse_water_bodies(data, exclude_types=None):
    """Extract closed water body polygons from Overpass JSON, filtering excluded types."""
    exclude_types = exclude_types or set()

    nodes = {}
    for elem in data["elements"]:
        if elem["type"] == "node":
            nodes[elem["id"]] = (elem["lon"], elem["lat"])

    bodies = []
    excluded = 0

    # Simple closed ways
    for elem in data["elements"]:
        if elem["type"] == "way":
            tags = elem.get("tags", {})
            water_type = tags.get("water", "")
            if water_type in exclude_types:
                excluded += 1
                continue
            node_ids = elem.get("nodes", [])
            coords = [nodes[nid] for nid in node_ids if nid in nodes]
            if len(coords) >= 4 and node_ids[0] == node_ids[-1]:
                bodies.append(np.array(coords))

    # Relations (multipolygon) — extract outer ways
    way_lookup = {}
    for elem in data["elements"]:
        if elem["type"] == "way":
            node_ids = elem.get("nodes", [])
            coords = [nodes[nid] for nid in node_ids if nid in nodes]
            if len(coords) >= 2:
                way_lookup[elem["id"]] = coords

    for elem in data["elements"]:
        if elem["type"] == "relation":
            tags = elem.get("tags", {})
            water_type = tags.get("water", "")
            if water_type in exclude_types:
                excluded += 1
                continue
            for member in elem.get("members", []):
                if member["type"] == "way" and member.get("role") == "outer":
                    wid = member["ref"]
                    if wid in way_lookup:
                        coords = way_lookup[wid]
                        if len(coords) >= 4:
                            bodies.append(np.array(coords))

    return bodies, excluded


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
            buffered = line.buffer(width_mm / 2, cap_style=2, join_style=2)
            if not buffered.is_empty:
                polys.append(buffered)
        except Exception:
            continue

    if not polys:
        return None

    merged = unary_union(polys)

    # Morphological closing: dilate then erode to fuse sliver gaps
    closed = merged.buffer(0.15).buffer(-0.15)

    simplified = closed.simplify(simplify_tol, preserve_topology=True)

    cleaned = _remove_small_polygons(simplified)
    return cleaned


def filled_polygons(polygon_coords_list, simplify_tol):
    """
    Create filled shapely polygons from closed coordinate rings.
    Used for water bodies that should be depressed areas, not outlines.
    """
    polys = []
    for coords in polygon_coords_list:
        if len(coords) < 4:
            continue
        try:
            p = Polygon(coords)
            if p.is_valid and not p.is_empty and p.area > 0:
                polys.append(p)
        except Exception:
            continue

    if not polys:
        return None

    merged = unary_union(polys)
    simplified = merged.simplify(simplify_tol, preserve_topology=True)
    return _remove_small_polygons(simplified)


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
        coords = list(poly.exterior.coords)
        if len(coords) >= 3:
            msp.add_lwpolyline(
                [(x, y) for x, y in coords],
                close=True,
                dxfattribs={"layer": layer_name},
            )
            poly_count += 1
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
        for geom in getattr(geometry, "geoms", []):
            if isinstance(geom, Polygon):
                add_polygon(geom)

    doc.saveas(str(filepath))
    skipped_msg = f", {skipped} artifacts removed" if skipped else ""
    print(f"  → {filepath}  ({poly_count} polygons{skipped_msg})")


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

    # 5 — Water features
    print(f"\n[5/7] Water data (OpenStreetMap)")
    waterways = get_waterways(south, north, west, east, WATERWAY_WIDTHS_MM)
    water_bodies = get_water_bodies(south, north, west, east, WATER_BODY_EXCLUDE)

    # 6 — Transform to panel coordinates
    print(f"\n[6/7] Coordinate transform (geo → {PANEL_SIZE_MM}mm panel)")
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
    waterway_mm = [
        {
            "coords": geo_to_panel_coords(
                w["coords"], south, north, west, east, PANEL_SIZE_MM, CENTER_LAT
            ),
            "width_mm": w["width_mm"],
        }
        for w in waterways
    ]
    water_body_mm = [
        geo_to_panel_coords(
            wb, south, north, west, east, PANEL_SIZE_MM, CENTER_LAT
        )
        for wb in water_bodies
    ]

    # 7 — Process geometry
    print(f"\n[7/7] Processing geometry")
    print(f"  Contours: {CONTOUR_LINE_WIDTH_MM}mm groove width...")
    contour_geom = buffer_lines(contour_mm, CONTOUR_LINE_WIDTH_MM, SIMPLIFY_TOLERANCE_MM)

    print(f"  Roads: {ROAD_LINE_WIDTH_MM}mm groove width...")
    road_geom = buffer_lines(road_mm, ROAD_LINE_WIDTH_MM, SIMPLIFY_TOLERANCE_MM)

    # Buffer waterways per-width, then merge with filled water body polygons
    print(f"  Waterways: per-type widths...")
    waterway_polys = []
    for w in waterway_mm:
        try:
            line = LineString(w["coords"])
            buffered = line.buffer(w["width_mm"] / 2, cap_style=2, join_style=2)
            if not buffered.is_empty:
                waterway_polys.append(buffered)
        except Exception:
            continue

    print(f"  Water bodies: filled areas...")
    body_geom = filled_polygons(water_body_mm, SIMPLIFY_TOLERANCE_MM)

    # Merge waterways + water bodies into one water layer
    all_water = waterway_polys[:]
    if body_geom is not None:
        all_water.append(body_geom)
    if all_water:
        water_geom = unary_union(all_water)
        water_geom = water_geom.simplify(SIMPLIFY_TOLERANCE_MM, preserve_topology=True)
        water_geom = _remove_small_polygons(water_geom)
    else:
        water_geom = None

    # Write DXF files
    print(f"\n  Writing DXF files to ./{OUTPUT_DIR}/")
    write_dxf(contour_geom, output / "contours.dxf", layer_name="contours")
    write_dxf(road_geom, output / "roads.dxf", layer_name="roads")
    write_dxf(water_geom, output / "water.dxf", layer_name="water")
    write_border_dxf(PANEL_SIZE_MM, output / "border.dxf")

    # Summary
    print("\n" + "=" * 60)
    print("  DONE!")
    print(f"  Output: ./{OUTPUT_DIR}/contours.dxf")
    print(f"          ./{OUTPUT_DIR}/roads.dxf")
    print(f"          ./{OUTPUT_DIR}/water.dxf")
    print(f"          ./{OUTPUT_DIR}/border.dxf")
    print()
    print("  Next: open panel.scad in OpenSCAD")
    print("=" * 60)


if __name__ == "__main__":
    main()
