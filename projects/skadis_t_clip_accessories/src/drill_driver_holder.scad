$fn = 128;

// User configuration

// Dimension calculation mode: "outer" or "inner". Calculates total dimensions based on if you want to specify the inner dimensions to fit your tool, or the outer dimensions to fit a spot on your SKADIS board. Outer dimensions need to be multiples of 40 to fit side by side without gaps
mode = "outer";

height = 80;
width = 80;
depth = 160;
wall_thickness = 4;

// Slot in the bottom to fit the grip
grip_slot_width = 40;
grip_slot_depth = depth - 50;

slant_angle = 65;
slant_start_depth = 175;

// Controls whether we calculate all internal clips that fit, or only the outer/corners
only_outer_clips = false;

assert(mode == "outer" || mode == "inner", "mode must be 'outer' or 'inner'");


// Internal calculations
double_wall_thickness = wall_thickness * 2;
outer_height = (mode == "outer") ? height : height + double_wall_thickness;
outer_width = (mode == "outer") ? width : width + double_wall_thickness;
inner_height = (mode == "inner") ? height : height - double_wall_thickness;
inner_width = (mode == "inner") ? width : width - double_wall_thickness;

echo("=================  Final dimensions  ==================");
echo("Outer height: ", outer_height, "width: ", outer_width);
echo("Inner height: ", inner_height, "width: ", inner_width);
echo("========================================================");


back_height = outer_height;  // must be more than clip_size and the height of the box, plus some extra space for lifting and pulling

// ================= SKADIS / T-CLIP ==============================
// t-clip from: https://www.printables.com/model/256896-skadis-t-clip-system/files plus https://www.formware.co/onlinestlrepair
clip_path = "./clip-seat_fixed.stl";
clip_size = 28.2;
clip_depth = 5.4;

// Horizontal clip layout (even rows)
skadis_hole_count = ceil((outer_width - clip_size) / 40) - 1;
skadis_hole_offset = (((outer_width - clip_size) % 40) / 2);

// Vertical row layout — 40mm Skadis grid spacing
skadis_row_count = max(0, ceil((back_height - clip_size) / 20) - 1);
skadis_row_offset_z = (((back_height - clip_size) % 20) / 2);

// Odd rows are offset 20mm horizontally per Skadis alternating pattern
skadis_hole_count_odd = max(-1, floor((outer_width - clip_size - skadis_hole_offset - 20) / 40));
skadis_hole_offset_odd = skadis_hole_offset + 20;

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


module hollow_rounded_rect(l, w, h, r, thickness) {
difference() {
  rounded_rect(w, h, l, r);
  
  double_thickness = thickness * 2;
  
  translate([thickness, thickness, -1])
    rounded_rect(w - double_thickness, h - double_thickness,l + 2,  r);
}
}



module draw_clip() {
    translate([-clip_depth, clip_size/2, clip_size/2]) rotate([0, 0, 90]) import(clip_path);
}

module half_rounded_cube(height, width, depth, curve=10) {
    hull() {
        // top left
        cube([1, 1, depth]);
        // top right
        translate([0, width - 1, 0]) cube([1, 1, depth]);
        // bottom left
        translate([height - curve/2, curve/2, 0]) cylinder(h=depth, d=curve);
        // bottom right
        translate([height - curve/2, width - curve/2, 0]) cylinder(h=depth, d=curve);
    }
}


difference() {
    difference() {
    // Main body
        rotate([90, 0, 90])
            hollow_rounded_rect(depth, outer_width, outer_height, 5, 5);

           // Slant slice
         translate([slant_start_depth, -10, 25])
            rotate([0, -slant_angle, 0])
            cube([outer_height, outer_width + 20, 200]);
    }
    
 
// Cut out the grip slot
translate([depth - grip_slot_depth, (outer_width - grip_slot_width) / 2, -2])
    cube([grip_slot_depth, grip_slot_width, 10], center=false); 
    
translate([depth - grip_slot_depth, outer_width / 2, wall_thickness])    
    cylinder(wall_thickness * 2, r=grip_slot_width / 2, center=true);
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
for (row = [0:skadis_row_count]) {
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
