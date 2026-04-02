# Topo Panel Generator

Generate 3D-printable panels with debossed topographic contour lines and roads.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Generate DXF files (downloads SRTM + OSM data on first run)
python topo_panel_generator.py

# Open in OpenSCAD
openscad panel.scad
```

## Customization

Edit the **CONFIGURATION** block at the top of `topo_panel_generator.py`:

| Parameter | Default | Description |
|---|---|---|
| `CENTER_LAT` / `CENTER_LON` | Lawrence, KS | Map center point |
| `MAP_RADIUS_KM` | 8 | Distance from center to edge of map |
| `PANEL_SIZE_MM` | 254 (10") | Physical panel size |
| `CONTOUR_INTERVAL_M` | 20 | Meters between contour lines |
| `CONTOUR_LINE_WIDTH_MM` | 0.6 | Groove width for contours |
| `ROAD_TYPES` | motorway, trunk, primary | OSM highway types to include |
| `ROAD_LINE_WIDTH_MM` | 1.0 | Groove width for roads |
| `GRID_RESOLUTION` | 400 | Elevation sampling density (NxN) |
| `SIMPLIFY_TOLERANCE_MM` | 0.15 | Geometry simplification (lower = smoother) |

### Road type options

From sparse to dense:
- **Major only:** `["motorway", "trunk", "primary"]`
- **+ Arterials:** add `"secondary", "tertiary"`
- **+ Local streets:** add `"residential", "unclassified"`
- **Everything:** add `"service"`

### Deboss depth

Edit `panel.scad` to adjust how deep the grooves cut:
- `contour_depth` — contour line depth (default 1.0mm)
- `road_depth` — road depth (default 1.4mm)

## Output Files

```
topo_output/
  contours.dxf   — Buffered contour line polygons
  roads.dxf      — Buffered road polygons
  border.dxf     — Panel border rectangle (for alignment)
```

## Notes

- **First run** downloads ~25MB of SRTM elevation tiles (cached locally).
- **OpenSCAD F5 preview** is fast. **F6 render** will be slow due to high polygon count — be patient or increase `SIMPLIFY_TOLERANCE_MM`.
- The script applies a `cos(lat)` correction so the map isn't horizontally distorted.
- Contour/road lines are **pre-buffered** to a physical groove width so they show up as real geometry in OpenSCAD (not infinitely-thin lines).
- Lawrence, KS has ~50m of total elevation relief, so 20m contours will give you ~3 visible contour levels. Try 10m or 5m for more detail.

## Dependencies

- `numpy` / `matplotlib` — elevation grid + contour extraction
- `srtm.py` — SRTM elevation data download
- `shapely` — geometry buffering and merging
- `ezdxf` — DXF file output
- `requests` — OpenStreetMap Overpass API
- `scipy` (optional) — fills gaps in elevation data
