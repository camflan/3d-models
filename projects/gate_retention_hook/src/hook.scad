$fn = 100;


hook_inner_radius = 15;
hook_width = 30;
edge_radius = 3;
hook_inset = hook_width * 0.7;
hook_depth = hook_width * 0.8;

part_width = hook_width - (edge_radius * 2);

dovetail_narrow_width = 10;
dovetail_wide_width = 15;
dovetail_depth = 5;

module dovetail(wide_width, narrow_width, depth, height) {
    dovetail_difference = (wide_width - narrow_width) / 2;
    echo(dovetail_difference);

    linear_extrude(height = height)
        polygon([
                [0, 0],
                [0, wide_width],
                [depth, dovetail_difference + narrow_width],
                [depth, dovetail_difference]
        ]);
}


module hook() {
    minkowski() {
        difference() {
            // Part profile
            hull() {
                translate([0,0,part_width/2])
                    cube([part_width * 2, part_width, part_width/2]);
                translate([part_width , 0, -part_width / 2])
                    cube([part_width, part_width, part_width]);
            }

            // Hook inner
            rotate([-90, 0, 0])
                translate([hook_inset, -hook_depth, -edge_radius])
                cylinder(h = hook_width, r = hook_inner_radius, center = false);
        }

        // Edge rounding
        rotate([-90, 0, 0])
            sphere(r = edge_radius);
    }
}


difference() {
    translate([0, edge_radius, 0])
    hook();

    
    dovetail_width = hook_width * 0.8;
    dovetail_inner = dovetail_width * 0.8;
    
    rotate([0, 0, 0])
    translate([(part_width * 2) - edge_radius / 2, (part_width - dovetail_inner)/2, - part_width * 3])
    dovetail(wide_width = dovetail_width, narrow_width = dovetail_inner, depth = edge_radius * 1.5, height=hook_width * 3);
}
