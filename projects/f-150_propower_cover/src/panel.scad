// ============================================================
//  Topo Panel — Lawrence, KS
//  Stepped topographic relief with debossed contour and road grooves.
//
//  Prerequisites:
//    Run `uv run topo_panel_generator.py` first to generate
//    the DXF files and relief.scad in ./topo_output/
//
//  Tip: Use F5 (preview) liberally — F6 (render) will be
//  slow due to the polygon count from buffered contour lines.
// ============================================================

use <topo_output/relief.scad>

$fn = 100;

// --- Panel dimensions ---
panel_size      = 254;     // mm (10 inches)
panel_thickness = 5;       // mm — base slab thickness
corner_radius   = 4;       // mm — 0 for sharp corners

// --- Deboss depths ---
contour_depth  = 1.0;     // mm — how deep contour grooves cut into each step
road_depth     = 0;       // mm — roads cut from top of relief. 0 to disable.

// --- Elevation relief ---
//  Must match RELIEF_HEIGHT_MM in topo_panel_generator.py.
//  Set to 0 to disable (flat panel with debossed grooves only).
relief_height  = 3.0;     // mm — total height across all steps

// --- File paths (relative to this .scad file) ---
road_file      = "topo_output/roads.dxf";

// ============================================================
//  Modules
// ============================================================

module rounded_square(size, radius) {
    if (radius > 0) {
        offset(r = radius)
        offset(delta = -radius)
            square(size);
    } else {
        square(size);
    }
}

module base_panel() {
    linear_extrude(height = panel_thickness)
        rounded_square(panel_size, corner_radius);
}

module relief_clipped() {
    if (relief_height > 0) {
        translate([0, 0, panel_thickness])
        intersection() {
            linear_extrude(height = relief_height + 0.1)
                rounded_square(panel_size, corner_radius);
            relief_layers(contour_depth);
        }
    }
}

module road_cut() {
    if (road_depth > 0) {
        translate([0, 0, panel_thickness + relief_height - road_depth])
            linear_extrude(height = road_depth + 0.1)
                import(road_file);
    }
}

// ============================================================
//  Assembly
// ============================================================

difference() {
    union() {
        base_panel();
        relief_clipped();
    }
    road_cut();
}
