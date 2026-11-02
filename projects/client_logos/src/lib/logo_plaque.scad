// Raised multi-color logo on a rounded base.
//
//   side view
//
//        ▄▄▄  ▒▒▒▒   ░░    ← logo layers, one per filament
//   ▐████████████████████▌ ← base
//
// Every layer SVG shares one pixel frame, so the layers line up without
// centering each one (centering would use each layer's own outline).

$fn = 64;

BASE_HEIGHT = 2;
LOGO_HEIGHT = 1.2;
BORDER = 3;
CORNER_RADIUS = 4;

// potrace writes one point per pixel, and OpenSCAD reads points as 1/72 inch
MM_PER_FRAME_PX = 25.4 / 72;

module layer_2d(dir, name, frame, width) {
    scale(width / (frame.x * MM_PER_FRAME_PX))
        translate([-frame.x / 2, -frame.y / 2] * MM_PER_FRAME_PX)
            import(str(dir, "/", name, ".svg"));
}

// Earlier layers win where traced outlines overlap, so no two parts share volume.
module clipped_layer_2d(dir, layers, index, frame, width) {
    difference() {
        layer_2d(dir, layers[index][0], frame, width);

        for (earlier = [0:1:index - 1]) {
            layer_2d(dir, layers[earlier][0], frame, width);
        }
    }
}

module base_2d(frame, width, border, corner_radius) {
    height = width * frame.y / frame.x;

    offset(r = corner_radius)
        square(
            [
                width + (border - corner_radius) * 2,
                height + (border - corner_radius) * 2,
            ],
            center = true
        );
}

// `part` selects one filament for export: "base", a layer name, or "all".
module logo_plaque(
    dir,
    frame,
    width,
    base_color,
    layers,
    part = "all",
    base_height = BASE_HEIGHT,
    logo_height = LOGO_HEIGHT,
    border = BORDER,
    corner_radius = CORNER_RADIUS
) {
    if (part == "all" || part == "base") {
        color(base_color)
            linear_extrude(height = base_height)
                base_2d(frame, width, border, corner_radius);
    }

    for (index = [0:1:len(layers) - 1]) {
        if (part == "all" || part == layers[index][0]) {
            color(layers[index][1])
                translate([0, 0, base_height])
                    linear_extrude(height = logo_height)
                        clipped_layer_2d(dir, layers, index, frame, width);
        }
    }
}
