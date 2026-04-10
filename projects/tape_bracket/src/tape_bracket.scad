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

filament_diameter = 1.85;

// === ROD PARAMETERS ===
rod_diameter    = 16;
rod_clearance   = 0.25;
rod_hole_dia    = rod_diameter + rod_clearance;

bracket_separation = 10;

// === BRACKET DIMENSIONS ===
arm_width       = 5;
min_wall        = 5;
arm_h           = rod_hole_dia + min_wall * 2;

// === ROD POSITIONS ===
rod_hole_positions = [
    [50, 0],
    [135, 24]
];

// === BACK PLATE ===
back_plate_t    = 8.6;
back_plate_height = 4 * 20; // 20mm units for skadis alignment?
back_plate_thickness = min_wall; // should match t-clip thickness?


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


back_height = back_plate_height;
outer_width = (arm_width * 2) + bracket_separation;


// ============================================================
// MODULES
// ============================================================


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


filament_radius = filament_diameter / 2;

module rod_holes() {
    // rod holes
    for(pos = rod_hole_positions) {
        translate([
                back_plate_thickness + pos[0] + rod_hole_radius,
                pos[1] + rod_hole_radius + min_wall
        ]) {
            circle(r = rod_hole_radius);

            translate([-rod_hole_radius - filament_radius * 0.4, 0, 0])
                circle(r = filament_radius);
        }

    }
}


module filet(d, length = back_plate_thickness) {
    r = d/2;

    translate([r, r, -length]) {
        difference() {
            translate([-r, -r, 0])
                cube([r, r, length]);
            cylinder(h = length, d = d, center = false);

        }
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


// Arm
linear_extrude(height = arm_width, center = false, convexity = 10, twist = 0, slices = 20, scale = 1.0) {
    difference() {
        bracket_2d();
        rod_holes();
    }
}

// Arm
translate([0, 0, bracket_separation + arm_width]){
    linear_extrude(height = arm_width, center = false, convexity = 10, twist = 0, slices = 20, scale = 1.0) {
        difference() {
            bracket_2d();
            rod_holes();
        }
    }
}

// back plate
cube([
        back_plate_thickness,
        back_plate_height,
        bracket_separation + arm_width
]);

// Rod sleeves
linear_extrude(h=bracket_separation + arm_width) {
    difference() {
        offset(r=min_wall) {
            rod_holes();
        }
        rod_holes();
    }
}


// Extrude the bracket and add filets
intersection() {
    translate([0,0,0]) {

        rotate([90, 0, 0]) {
            translate([back_plate_thickness, arm_width, 0])
                filet(d = arm_width, length = back_plate_height);

            translate([back_plate_thickness, arm_width + bracket_separation, 0])
                rotate([0, 0, 270])
                filet(d = arm_width, length = back_plate_height);
        }
    }

    linear_extrude(
            height = (arm_width * 2) + bracket_separation,
            center = false,
            convexity = 10,
            twist = 0,
            slices = 20,
            scale = 1.0
            ) {
        bracket_2d();
    }
}
