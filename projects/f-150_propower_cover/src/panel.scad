// ============================================================
//  Topo Panel — Lawrence, KS
//  Debossed topographic contours and roads
//
//  Prerequisites:
//    Run `python topo_panel_generator.py` first to generate
//    the DXF files in ./topo_output/
//
//  Tip: Use F5 (preview) liberally — F6 (render) will be
//  slow due to the polygon count from buffered contour lines.
// ============================================================

$fn = 100;

// --- Panel dimensions ---
panel_size     = 254;     // mm (10 inches)
panel_thickness = 5;       // mm — total slab thickness
corner_radius   = 4;       // mm — 0 for sharp corners

// --- Deboss depths (from top surface) ---
contour_depth  = 1.0;     // mm — how deep the contour grooves cut
road_depth     = 1.4;     // mm — roads slightly deeper so they pop

// --- File paths (relative to this .scad file) ---
contour_file = "topo_output/contours.dxf";
road_file    = "topo_output/roads.dxf";

// ============================================================
//  Modules
// ============================================================

module rounded_square(size, radius) {
    // 2D rounded square for extrusion
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

// ============================================================
//  Assembly
// ============================================================

difference() {
    base_panel();
    contour_cut();
    road_cut();
}

// --- Optional: uncomment to see the border outline for alignment ---
// %translate([0, 0, panel_thickness])
//     linear_extrude(height = 0.1)
//         import("topo_output/border.dxf");
