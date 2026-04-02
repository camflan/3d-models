// ============================================================
//  Topo Panel — Lawrence, KS
//  Debossed topographic contours, roads, and water features
//
//  Prerequisites:
//    Run `uv run topo_panel_generator.py` first to generate
//    the DXF files in ./topo_output/
//
//  Tip: Use F5 (preview) liberally — F6 (render) will be
//  slow due to the polygon count from buffered contour lines.
// ============================================================

$fn = 100;

// --- Panel dimensions ---
panel_size      = 254;     // mm (10 inches)
panel_thickness = 5;       // mm — total slab thickness
corner_radius   = 4;       // mm — 0 for sharp corners

// --- Deboss depths (from top surface) ---
contour_depth   = 1.0;    // mm — contour line grooves
road_depth      = 1.4;    // mm — road grooves (slightly deeper so they pop)
water_depth     = 1.2;    // mm — depressed water surfaces (rivers + lakes)

// --- File paths (relative to this .scad file) ---
contour_file = "topo_output/contours.dxf";
road_file    = "topo_output/roads.dxf";
water_file   = "topo_output/water.dxf";

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

module contour_cut() {
    translate([0, 0, panel_thickness - contour_depth])
        linear_extrude(height = contour_depth + 0.1)
            import(contour_file);
}

module road_cut() {
    translate([0, 0, panel_thickness - road_depth])
        linear_extrude(height = road_depth + 0.1)
            import(road_file);
}

module water_cut() {
    translate([0, 0, panel_thickness - water_depth])
        linear_extrude(height = water_depth + 0.1)
            import(water_file);
}

// ============================================================
//  Assembly
// ============================================================

difference() {
    base_panel();
    contour_cut();
    road_cut();
    water_cut();
}
