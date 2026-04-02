// ============================================================
//  Topo Panel — Lawrence, KS
//  Debossed topographic contours and roads with optional
//  elevation relief on the panel surface.
//
//  Prerequisites:
//    Run `python topo_panel_generator.py` first to generate
//    the DXF/PNG files in ./topo_output/
//
//  Tip: Use F5 (preview) liberally — F6 (render) will be
//  slow due to the polygon count from buffered contour lines.
// ============================================================

$fn = 100;

// --- Panel dimensions ---
panel_size      = 254;     // mm (10 inches)
panel_thickness = 5;       // mm — base slab thickness
corner_radius   = 4;       // mm — 0 for sharp corners

// --- Deboss depths (from top surface, including relief) ---
contour_depth  = 1.0;     // mm — how deep the contour grooves cut
road_depth     = 1.4;     // mm — roads slightly deeper so they pop

// --- Elevation relief ---
//  Adds a 3D surface on top of the base panel.
//  Set to 0 to disable (flat panel with debossed grooves only).
relief_height  = 3.0;     // mm — height range added on top of base

// --- File paths (relative to this .scad file) ---
contour_file   = "topo_output/contours.dxf";
road_file      = "topo_output/roads.dxf";
heightmap_file = "topo_output/heightmap.png";

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

//  surface() reads the PNG as a height field.
//  Scale: pixel value 0→0mm, 255→relief_height mm.
//  The image covers panel_size x panel_size mm.
module relief_surface() {
    if (relief_height > 0) {
        translate([0, 0, panel_thickness])
        intersection() {
            // Clip relief to rounded panel outline
            linear_extrude(height = relief_height + 0.1)
                rounded_square(panel_size, corner_radius);
                
            image_scale = ceil((panel_size/400) * 100) / 100;

            scale([image_scale, image_scale, relief_height / 100])
                surface(file = heightmap_file, center = false, convexity = 5);
        }
    }
}

module contour_cut() {
    // Cut from the top of the highest possible point
    top = panel_thickness + relief_height;
    translate([0, panel_size, top - contour_depth])
        rotate([180, 0, 0])

        linear_extrude(height = contour_depth + 0.1)
            import(contour_file);
}

module road_cut() {
    top = panel_thickness + relief_height;
    translate([0, 0, top - road_depth])
        linear_extrude(height = road_depth + 0.1)
            import(road_file);
}

// ============================================================
//  Assembly
// ============================================================

difference() {
    union() {
        base_panel();
        relief_surface();
    }
    contour_cut();
    road_cut();
}

// --- Optional: uncomment to see the border outline for alignment ---
// %translate([0, 0, panel_thickness + relief_height])
//     linear_extrude(height = 0.1)
//         import("topo_output/border.dxf");
