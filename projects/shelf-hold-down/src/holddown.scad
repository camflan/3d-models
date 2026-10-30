$fn = 50;

block_width = 15;
block_thickness = 5;

block_bottom_extra = 6;

hole_depth = 4;
hole_diameter = 5;
hole_spacing = 32;

hole_radius = hole_diameter / 2;

peg_base_height = 2;
peg_taper = 0.125;

module pin() {
    cylinder(h = peg_base_height, r = hole_radius, center = false);

    translate([0, 0, peg_base_height])
        cylinder(h = hole_depth - peg_base_height, r1 = hole_radius, r2 = hole_radius - peg_taper, center = false);
}

module main() {
    translate([-block_width / 2, -hole_diameter, 0])

        minkowski() {
            l = hole_spacing + (hole_diameter * 2) + block_bottom_extra;

            translate([0, 0, 0])
                cylinder(h = 0.1, r = block_width * 0.125);

            cube([block_width, l, block_thickness - 0.1]);
        }

    translate([0, 0, block_thickness])
        pin();

    translate([0, hole_spacing, block_thickness])
        pin();
}


main();
