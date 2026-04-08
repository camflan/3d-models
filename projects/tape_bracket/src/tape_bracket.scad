// ============================================================
// Tape Roll Bracket - Truss Style with MultiConnect
// ============================================================
// V2 truss with filleted edges throughout.
//
// Wall at X=0, +X away from wall, Y along rod, Z vertical
// ============================================================

$fn = 128;

min_rod_gap = 40;
max_rod_gap = 100;

// === ROD PARAMETERS ===
rod_diameter    = 16;
rod_clearance   = 0.2;
rod_hole_dia    = rod_diameter + rod_clearance;

bracket_separation = 30;

// === BRACKET DIMENSIONS ===
arm_width       = 15;
min_wall        = 5.4;
arm_h           = rod_hole_dia + min_wall * 2;

// === ROD POSITIONS ===
rod_hole_positions = [
    [45, 0],
    [110, 24]
];

// === BACK PLATE ===
back_plate_t    = 8.6;
back_plate_height = 4 * 20; // 20mm units for skadis alignment?
back_plate_thickness = 5.4; // should match t-clip thickness?


// Tape rolls
rolls = [
    // inner, outer, width
    [38, 76, 19], // electrical
    [76, 127, 48], // duct
    [76, 114, 48], // packing
    [76, 102, 40], // masking
];


// ============================================================
// DERIVED
// ============================================================
rod_radius = rod_diameter / 2;
rod_hole_radius = rod_hole_dia / 2;


// ================= SKADIS / T-CLIP ==============================
// SKADIS
// Controls whether we calculate all internal clips that fit, or only the outer/corners
only_outer_clips = false;

// t-clip from: https://www.printables.com/model/256896-skadis-t-clip-system/files plus https://www.formware.co/onlinestlrepair
clip_path = "./clip-seat_fixed.stl";
clip_size = 28.2;
clip_depth = 5.4;

back_height = back_plate_height;
outer_width = (arm_width * 2) + bracket_separation;

// Horizontal clip layout (even rows)
skadis_hole_count = max(1, ceil((outer_width - clip_size) / 40) - 1);
skadis_hole_offset = (((outer_width - clip_size) % 40) / 2);

// Vertical row layout — 40mm Skadis grid spacing
skadis_row_count = max(0, ceil((back_height - clip_size) / 20) - 1);
skadis_row_offset_z = (((back_height - clip_size) % 20) / 2);

// Odd rows are offset 20mm horizontally per Skadis alternating pattern
skadis_hole_count_odd = max(-1, floor((outer_width - clip_size - skadis_hole_offset - 20) / 40));
skadis_hole_offset_odd = skadis_hole_offset + 20;


// ============================================================
// MODULES
// ============================================================
module draw_clip() {
    translate([-clip_depth, clip_size/2, clip_size/2])
        rotate([0, 0, 90])
        import(clip_path);
}

module rod_cuts(rx, rz) {
    translate([rx, 0, rz])
        rotate([90, 0, 0])
        translate([0, 0, -arm_width - 1])
        cylinder(h = arm_width * 2 + 2, d = rod_hole_dia);
}

// Rounded polygon cutout
module rounded_cutout(pts) {
    offset(r=cutout_r)
        offset(r=-cutout_r)
        polygon(pts);
}


module bracket_body() {
    // Extrude with edge rounding on the 2D profile
    translate([0, arm_width/2, 0])
        rotate([90, 0, 0])
        linear_extrude(arm_width)
        offset(r=edge_r) offset(r=-edge_r)
        solid_profile_2d();
}

// ============================================================
// ASSEMBLY
// ============================================================
module rod_slots() {
    for(pos = rod_hole_positions) {
        rod_cuts(pos[0], pos[1]);
    }
}

module tape_bracket() {
    difference() {
        bracket_body();
        rod_slots();
    }
}

module tape_roll(spool_diameter, outer_diameter, width) {
    translate([0,0,0])
        rotate([90, 0, 0])
        difference() {
            cylinder(h = width, r = outer_diameter/2, center=true);
            cylinder(h = width, r = spool_diameter/2, center=true);
        }
}

// module rod(x, z, length = 300) {
//     translate([x, 0, z])
//         rotate([90, 0, 0])
//         cylinder(h = length, r = rod_diameter/2);
// }

// module inner_rod() {
//     rod(inner_rod_x, inner_rod_y);
// }
//
// module outer_rod() {
//     rod(outer_rod_x, outer_rod_y);
// }

function cumulative_y(i, sum = 0) =
    i + 1 >= len(rolls)
    ? sum
    : cumulative_y(i + 1, sum + rolls[i][2]);

module sector(radius, angles, fn = 24) {
    r = radius / cos(180 / fn);
    step = -360 / fn;

    points = concat([[0, 0]],
        [for(a = [angles[0] : step : angles[1] - 360])
            [r * cos(a), r * sin(a)]
        ],
        [[r * cos(angles[1]), r * sin(angles[1])]]
    );

    difference() {
        circle(radius, $fn = fn);
        polygon(points);
    }
}

module rod_holes() {
    // rod holes
    for(pos = rod_hole_positions) {
        translate([
            back_plate_thickness + pos[0] + rod_hole_radius,
            pos[1] + rod_hole_radius + min_wall
        ])
        circle(r = rod_hole_radius);
    }
}

module bracket_2d() {
    hull(){
        offset(r=min_wall)
            rod_holes();

        // back plate
        polygon([
                [0, 0], // BL
                [0, back_plate_height], // TL
                [back_plate_thickness, back_plate_height], // TR
                [back_plate_thickness, 0], // BR
        ]);
    }
}


linear_extrude(height = 10, center = false, convexity = 10, twist = 0, slices = 20, scale = 1.0) {
    difference() {
        bracket_2d();
        rod_holes();
    }
}

translate([0, 0, bracket_separation + arm_width]){
    linear_extrude(height = 10, center = false, convexity = 10, twist = 0, slices = 20, scale = 1.0) {
        difference() {
            bracket_2d();
            rod_holes();
        }
    }
}

cube([
    back_plate_thickness,
    back_plate_height,
    bracket_separation + arm_width
]);

linear_extrude(h=bracket_separation + arm_width) {
    difference() {
        offset(r=min_wall) {
            rod_holes();
        }
        rod_holes();
    }
}

module back_plate_filet(side) {
    pos = side == "left" ? [back_plate_thickness, -arm_width] : [back_plate_thickness, 0 - arm_width - bracket_separation];
    sector_pos = side == "left" ? [min_wall, 0] : [min_wall, min_wall];

    rotate([270, 0, 0]) {
        translate(pos){
            linear_extrude(height = back_plate_height) {
                difference(){
                    #polygon([
                            [0, 0],
                            [min_wall, 0],
                            [min_wall, min_wall],
                            [0, min_wall]
                    ]);

                    translate(sector_pos)
                        circle(
                                r = min_wall,
                              );
                }
            }
        }
    }
}

intersection() {
translate([0,0,0]) {
back_plate_filet(side = "left");
back_plate_filet(side = "right");
}

linear_extrude(height = 100, center = false, convexity = 10, twist = 0, slices = 20, scale = 1.0) {
bracket_2d();
}
}



outer_height = back_plate_height;

module rounded_rect(width, depth, height, radius) {
    // Ensure the radius is not too large
    radius = min(radius, min(width, depth) / 2);

    linear_extrude(height = height) {
        hull() {
            // Bottom-left
            translate([radius, radius]) circle(r = radius);
            // Bottom-right
            translate([width - radius, radius]) circle(r = radius);
            // Top-left
            translate([radius, depth - radius]) circle(r = radius);
            // Top-right
            translate([width - radius, depth - radius]) circle(r = radius);
        }
    }
}

// backside
difference() {
    rotate([90, 270, 270]) rounded_rect(outer_height, outer_width,clip_depth,  5);
    for (row = [0:skadis_row_count]) {
        row_h_count = (row % 2 == 0) ? skadis_hole_count : skadis_hole_count_odd;
        row_h_offset = (row % 2 == 0) ? skadis_hole_offset : skadis_hole_offset_odd;
        if (row_h_count >= 0)
        translate([0, row_h_offset, skadis_row_offset_z + 20 * row]) for (a = [0:row_h_count]) {
            is_outer = (a == 0 || a == row_h_count) && (row == 0 || row == skadis_row_count);
            if (!only_outer_clips || is_outer) {
                translate([-clip_depth - 0.1, (40 * a) + clip_size / 2, clip_size / 2]) rotate([0, 90]) cylinder(h=clip_depth + 0.2, d=clip_size);
            }
        }
    }
}

// draw clips
#for (row = [0:skadis_row_count]) {
    row_h_count = (row % 2 == 0) ? skadis_hole_count : skadis_hole_count_odd;
    row_h_offset = (row % 2 == 0) ? skadis_hole_offset : skadis_hole_offset_odd;
    
    if (row_h_count >= 0)
    translate([0, row_h_offset, skadis_row_offset_z + 20 * row]) for (a = [0:row_h_count]) {
        is_outer = (a == 0 || a == row_h_count) && (row == 0 || row == skadis_row_count);
        if (!only_outer_clips || is_outer) {
            translate([0, 40 * a]) draw_clip();
        }
    }
}


//
//
//
//!difference() {
//    hull() {
//        tape_bracket();
//        translate([0, -arm_width, plate_bottom])
//            cube([0, arm_width, plate_top - plate_bottom]);
//    }
//
//    rod_slots();
//}
//
//
//    for (roll_idx = [0:2]) {
//        roll = rolls[roll_idx];
//        id = roll[0];
//        od = roll[1];
//        w = roll[2];
//
//        offset = cumulative_y(roll_idx);
//        echo(offset);
//
//        translate([od/2, cumulative_y(roll_idx), 10])
//            tape_roll(id, od, w);
//    }
//
//inner_rod();
//outer_rod();
