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
use <fillets3d.scad>;

$fn = 100;

// --- Panel dimensions ---
panel_size      = (9 + (6.5/16)) * 25.4;     // mm (10 inches)
panel_thickness = 5;       // mm — total slab thickness
corner_radius   = 4;       // mm — 0 for sharp corners
border_width    = 6;       // mm — raised border around panel edge. 0 to disable.

cord_diameter = 3.5;
cord_corner_inset = (22/16) * 25.4;  // how far from corner to inset cord_holes
cord_hole_separation = cord_diameter * -3;

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

// 2D shape of the inner area (inside the border)
module inner_area() {
    if (border_width > 0) {
        offset(delta = -border_width)
            rounded_square(panel_size, corner_radius);
    } else {
        rounded_square(panel_size, corner_radius);
    }
}

// Clip a cut to only affect the inner area
module clipped_cut(depth) {
    intersection() {
        translate([0, 0, panel_thickness - depth])
            linear_extrude(height = depth + 0.1)
                inner_area();
        children();
    }
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

// Flat background pad that clears topo detail underneath.
// Children are debossed (cut) into the pad surface.
//
//   pos:    [x, y] center of the pad
//   w:      pad width (mm)
//   h:      pad height (mm)
//   depth:  how deep the pad + text are cut (mm)
//   pill:   true → capsule/stadium ends, false → rectangle with corner_r
//   corner_r: corner radius for rectangular mode (default 0)
//
//        ╭──────────────────────────╮
//       (   Ford ProPower            )
//       (   Onboard Generator        )
//        ╰──────────────────────────╯
//
module label_pad(pos, w, h, depth, pill=false, corner_r=0) {
    pad_z = panel_thickness - depth;

    module pad_2d() {
        translate(pos) {
            if (pill) {
                // Capsule: semicircle ends, flat top/bottom
                hull() {
                    translate([-(w - h) / 2, 0]) circle(d = h);
                    translate([ (w - h) / 2, 0]) circle(d = h);
                }
            } else if (corner_r > 0) {
                offset(r = corner_r)
                    square([w - 2*corner_r, h - 2*corner_r], center=true);
            } else {
                square([w, h], center=true);
            }
        }
    }

    // Remove pad volume from children (clears topo detail)
    difference() {
        children();
        translate([0, 0, pad_z])
            linear_extrude(height = depth + 0.1)
                pad_2d();
    }
    // Add back flat pad at panel surface
    translate([0, 0, pad_z])
        linear_extrude(height = depth)
            pad_2d();
}

// Deboss text into the panel surface.
// Use inside or after a label_pad to cut text into the flat area.
//
//   pos:   [x, y] center of the text
//   txt:   string
//   font:  OpenSCAD font spec
//   size:  font size in mm
//   depth: cut depth in mm
module debossed_text(pos, txt, font, size, depth) {
    difference() {
        children();
        translate([pos[0], pos[1], panel_thickness - depth - 0.05])
            linear_extrude(height = depth + 0.2)
                text(txt, font=font, size=size,
                     halign="center", valign="center"); // , spacing=1);
    }
}


// Example usage:
// difference() {
//     cube([50, 50, h+2*r], center=true); // Main object
//     filleted_cylinder_manual(d=10, h=20, r=2); // The hole
// }

// ============================================================
//  Assembly
// ============================================================

debossed_text(
    pos   = [panel_size -60, 16],
    txt   = "Ford ProPower",
//    font  = "Charter:style=Bold Italic",
//font = "DIN Alternate",
//font = "IBM Plex Sans:style=Italic",
font = "Intel One Mono:style=Bold Italic",
    size  = 8,
    depth = 2.0
)
label_pad(
    pos   = [panel_size -60, 15],
    w     = 115,
    h     = 30,
    depth = 2.0,
    corner_r = corner_radius
)

difference() {
    base_panel();
    clipped_cut(contour_depth) contour_cut();
    clipped_cut(road_depth)    road_cut();
    clipped_cut(water_depth)   water_cut();

    label_pad(
        pos = [panel_size - cord_corner_inset - (cord_hole_separation / -2), panel_size - cord_corner_inset],
        w = (cord_diameter * 2) + cord_hole_separation,
        h = cord_diameter * 2,
        depth = 1,
        pill = true
//        corner_r = 2
    );
    translate([panel_size - cord_corner_inset, panel_size - cord_corner_inset, 0]) {
        cylinder(h = panel_thickness, r=cord_diameter/2);
        
        translate([cord_hole_separation, 0, 0])
                cylinder(h = panel_thickness, r=cord_diameter/2);

        }
}

