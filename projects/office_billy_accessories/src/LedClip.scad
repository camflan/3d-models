// LED Strip Clip for OpenSCAD

// Parameters
led_width = 10;        // Width of the LED strip (mm)
led_thickness = 2;      // Thickness of the LED strip (mm)
clip_height = 2;        // Height of the clip above the surface (mm)
clip_grip_depth = 1.5;  // How much the clip grips the LED strip (mm)
wall_thickness = 1.5;   // Wall thickness of the clip (mm)

// Base platform (surface mounting)
module base() {
    cube([led_width, led_width + (2 * wall_thickness), wall_thickness], center=false);
}

// Clip arm that holds the LED strip
module clip_arm() {
    // translate([wall_thickness, 0, wall_thickness])
    cube([led_width, clip_height, led_thickness + clip_grip_depth]);
}

// Full assembly
union() {
    base();
    
    translate([wall_thickness, 0, wall_thickness])
    clip_arm();

    translate([wall_thickness, led_width + (wall_thickness * 2), wall_thickness])
    clip_arm();


    // Optional: Add a mounting hole
    //translate([led_width/2 + wall_thickness, 10, wall_thickness/2])
    //rotate([90, 0, 0])
    //cylinder(h = wall_thickness, r = 1.5, center=false); // Mounting hole
}