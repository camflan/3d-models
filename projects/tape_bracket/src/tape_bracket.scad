// ============================================================
// Tape Roll Bracket - Truss Style with MultiConnect
// ============================================================
// V2 truss with filleted edges throughout.
//
// Wall at X=0, +X away from wall, Y along rod, Z vertical
// ============================================================

$fn = 128;

// === ROD PARAMETERS ===
rod_diameter    = 15.875;
rod_clearance   = 0.3;
rod_hole_dia    = rod_diameter + rod_clearance;

// === SET SCREW ===
//set_screw_dia       = 4.2;
//set_screw_recess    = 7.5;
//set_screw_recess_d  = 4.0;

// === BRACKET DIMENSIONS ===
arm_width       = 30;
min_wall        = 5;
arm_h           = rod_hole_dia + min_wall * 2;

// === ROD POSITIONS ===
inner_rod_x     = 25;
inner_rod_z     = -12;
outer_rod_x     = 100;
outer_rod_z     = 12;

// === BACK PLATE ===
back_plate_t    = 8.6;

// === FILLET ===
fillet_r_top    = 8;
fillet_r_bot    = 5;

// === TRUSS PARAMETERS ===
chord_t         = 5;
web_t           = 5;
boss_r_extra    = 4;
cutout_r        = 4;      // corner rounding on cutouts
edge_r          = 2;      // rounding on outer profile corners


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
inner_top = inner_rod_z + arm_h/2;
inner_bot = inner_rod_z - arm_h/2;
outer_top = outer_rod_z + arm_h/2;
outer_bot = outer_rod_z - arm_h/2;

plate_bottom = inner_bot - fillet_r_bot;
plate_top    = outer_top + fillet_r_top;

boss_r = arm_h/2 + boss_r_extra;

// Bottom diagonal slope
bot_x0 = inner_rod_x + arm_h/2;
bot_z0 = inner_bot;
bot_x1 = outer_rod_x + arm_h/2;
bot_z1 = outer_bot;
bot_slope = (bot_z1 - bot_z0) / (bot_x1 - bot_x0);
function bot_z_at(x) = bot_z0 + (x - bot_x0) * bot_slope;

// ============================================================
// MODULES
// ============================================================


module rod_cuts(rx, rz) {
    translate([rx, 0, rz])
        rotate([90, 0, 0])
        translate([0, 0, -arm_width - 1])
        cylinder(h = arm_width * 2 + 2, d = rod_hole_dia);
}

// Solid outer profile - original V2 flat silhouette
module solid_profile_2d() {
    polygon([
        [0, plate_bottom],
        [0, plate_top],
        [back_plate_t, plate_top],
        [back_plate_t, outer_top],
        [outer_rod_x + arm_h/2, outer_top],
        [outer_rod_x + arm_h/2, outer_bot],
        [inner_rod_x + arm_h/2, inner_bot],
        [back_plate_t, inner_bot],
        [back_plate_t, plate_bottom],
    ]);
    translate([back_plate_t, outer_top])
    difference() {
        square([fillet_r_top, fillet_r_top]);
        translate([fillet_r_top, fillet_r_top]) circle(r=fillet_r_top);
    }
    translate([back_plate_t, inner_bot - fillet_r_bot])
    difference() {
        square([fillet_r_bot, fillet_r_bot]);
        translate([fillet_r_bot, 0]) circle(r=fillet_r_bot);
    }
}

// Rounded polygon cutout
module rounded_cutout(pts) {
    offset(r=cutout_r) offset(r=-cutout_r)
        polygon(pts);
}

// Truss profile with cutouts
module truss_profile_2d() {
    mid_x = (inner_rod_x + outer_rod_x) / 2;

    top_inner_z = outer_top - chord_t;
    bp_inner_x  = back_plate_t + chord_t;

    bot_angle = atan2(bot_z1 - bot_z0, bot_x1 - bot_x0);
    perp_shift = chord_t / cos(bot_angle);

    web1_angle = atan2(outer_top - inner_rod_z, mid_x - inner_rod_x);
    web1_dx = web_t/2 * sin(web1_angle);
    web1_dz = web_t/2 * cos(web1_angle);

    difference() {
        solid_profile_2d();

        // === CUTOUT A: Upper-left triangle ===
        difference() {
            rounded_cutout([
                [bp_inner_x + 2, top_inner_z - 1],
                [mid_x - web1_dx - 2, top_inner_z - 1],
                [inner_rod_x + web1_dx + 2, inner_rod_z + web1_dz + 6],
                [bp_inner_x + 2, inner_rod_z + 8],
            ]);
            translate([inner_rod_x, inner_rod_z]) circle(r=boss_r);
        }

        // === CUTOUT B: Right triangle ===
        difference() {
            rounded_cutout([
                [mid_x + web1_dx + 2, top_inner_z - 1],
                [outer_rod_x - boss_r + 2, top_inner_z - 1],
                [outer_rod_x - boss_r + 2, bot_z_at(outer_rod_x - boss_r + 2) + perp_shift + 3],
                [inner_rod_x + arm_h/2 + 3, bot_z_at(inner_rod_x + arm_h/2 + 3) + perp_shift + 3],
            ]);
            translate([inner_rod_x, inner_rod_z]) circle(r=boss_r);
            translate([outer_rod_x, outer_rod_z]) circle(r=boss_r);
        }
    }
}

module bracket_body() {
    // Extrude with edge rounding on the 2D profile
    translate([0, arm_width/2, 0])
    rotate([90, 0, 0])
    linear_extrude(arm_width)
        offset(r=edge_r) offset(r=-edge_r)
        solid_profile_2d();

    // Cylindrical rod bosses
//    for (pos = [[inner_rod_x, inner_rod_z], [outer_rod_x, outer_rod_z]])
//        translate([pos[0], 0, pos[1]])
//            rotate([90, 0, 0])
//            translate([0, 0, -arm_width/2])
//            cylinder(h=arm_width, d=arm_h);
}

// ============================================================
// ASSEMBLY
// ============================================================
module rod_slots() {
    rod_cuts(inner_rod_x, inner_rod_z);
    rod_cuts(outer_rod_x, outer_rod_z);
}

module tape_bracket() {
    difference() {
        bracket_body();
        rod_slots();
    }
}

difference() {
    hull() {
        tape_bracket();
        translate([0, -arm_width, plate_bottom])
            cube([10, arm_width, plate_top - plate_bottom]);
    }

    rod_slots();
}


module tape_roll(spool_diameter, outer_diameter, width) {
    translate([0,0,0])
    rotate([90, 0, 0])
    difference() {
    cylinder(h = width, r=outer_diameter/2, center=true);
    cylinder(h=width, r = spool_diameter/2, center=true);
    }
}

module rod(x, z, length = 300) {
    translate([x, 0, z])
    rotate([90, 0, 0])
    cylinder(h = length, r = rod_diameter/2);
}

module inner_rod() {
rod(inner_rod_x, inner_rod_z);
}

module outer_rod() {
rod(outer_rod_x, outer_rod_z);
}

function cumulative_y(i, sum = 0) = 
    i + 1 >= len(rolls)
        ? sum
        : cumulative_y(i + 1, sum + rolls[i][2]);

for (roll_idx = [0:2]) {
    roll = rolls[roll_idx];
    id = roll[0];
    od = roll[1];
    w = roll[2];
    
    offset = cumulative_y(roll_idx);
    echo(offset);
    
    translate([od/2, cumulative_y(roll_idx), 10])
  tape_roll(id, od, w);
  }

inner_rod();
outer_rod();