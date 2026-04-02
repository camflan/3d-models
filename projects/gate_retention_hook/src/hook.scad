$fn = 128;

// gate bar width ~0.5"
// gate bar sits ~1.5" from the wall at the furthest point
gate_bar = 0.5 * 25.4;
gate_bar_from_wall = 1.5 * 25.4;

edge_radius = 3;
edge_diameter = edge_radius * 2;

part_depth = 50;
hook_inner_radius = (gate_bar / 2) + edge_diameter;
hook_total_width = 30;
hook_inset = (part_depth - gate_bar_from_wall) + hook_inner_radius - edge_diameter;

hook_depth_offset = 7.5;

hook_part_depth = part_depth;
hook_inner_width = hook_total_width - edge_diameter;
hook_mount_height = 30;
hook_bottom_depth = 25;

dovetail_width = hook_total_width * 0.8;
dovetail_inner = dovetail_width * 0.8;
dovetail_slot_depth = edge_diameter;
dovetail_slot_height = hook_mount_height * 0.85;
dovetail_clearance = 0.2;

command_strip_width = 16;
command_strip_thickness = 0.5;


module dovetail(wide_width, narrow_width, depth, height) {
    dovetail_difference = (wide_width - narrow_width) / 2;

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
                translate([0,0,0])
                    cube([hook_part_depth - edge_diameter, hook_inner_width, hook_mount_height/2]);
                translate([hook_part_depth - edge_diameter - hook_bottom_depth , 0, -hook_mount_height/2])
                    cube([hook_bottom_depth, hook_inner_width, hook_mount_height/2]);
            }

            // Hook inner
            rotate([-90, 0, 0])
                translate([
                        hook_inset,
                        (-hook_mount_height/2),
                        (hook_inner_width / 2)
                ])
                hull() {
                    cylinder(h = hook_total_width, r = hook_inner_radius, center = true);
                    translate([0, hook_depth_offset, 0])
                        cylinder(h = hook_total_width, r = hook_inner_radius, center = true);
                }
        }

        // Edge rounding
        rotate([-90, 0, 0])
            sphere(r = edge_radius);
    }
}


difference() {
    translate([edge_radius, edge_radius, 0])
        hook();

    // Dovetail slot in part
    translate([
            hook_part_depth - edge_diameter,
            edge_radius,
            -(hook_mount_height/2) - edge_radius,
    ])
        dovetail(
                wide_width = dovetail_width,
                narrow_width = dovetail_inner,
                depth = dovetail_slot_depth,
                height = dovetail_slot_height
                );
}

// just to get the part out of the way
dovetail_insert_offset = 60;
font_size = 7;
text_depth = 1;

// Dovetail insert/wall mount
difference(){
    translate([0, dovetail_insert_offset, 0])
        dovetail(
                wide_width = dovetail_width - dovetail_clearance,
                narrow_width = dovetail_inner - dovetail_clearance,
                depth = dovetail_slot_depth - dovetail_clearance,
                height = dovetail_slot_height - dovetail_clearance
                );

    // Command strip indent
    indent_difference = dovetail_width - command_strip_width;
    translate([
            edge_diameter - command_strip_thickness,
            dovetail_insert_offset + indent_difference / 2,
            0
    ])
        cube([command_strip_thickness, command_strip_width, dovetail_slot_height]);

    rotate([90, 90, 90])
        translate([
                -dovetail_slot_height / 2,
                dovetail_insert_offset + (dovetail_width/2) - (font_size / 2),
                dovetail_slot_depth - command_strip_thickness - text_depth
        ])
        linear_extrude(height=text_depth)
        text("Wall", size = font_size, font = "IBM Plex Mono", halign="center");
}
