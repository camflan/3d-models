// Raised logo on a base, for two-color prints.
//
//   side view
//
//        ▄▄▄  ▄▄▄▄   ▄▄    ← logo  (color 2, starts at base_height)
//   ▐████████████████████▌ ← base  (color 1)
//
// Swap filament at the first layer above base_height.

$fn = 64;

LOGO_WIDTH = 70;
BASE_HEIGHT = 2;
LOGO_HEIGHT = 1.2;
BORDER = 3;
CORNER_RADIUS = 4;

BAND_LENGTH = 1000;
BAND_THIN = 0.01;

BASE_COLOR = "white";
LOGO_COLOR = "black";

// "outline": base follows the logo shape, grown by `border`
// "hull":    base is the convex hull of the logo, grown by `border`
// "rect":    base is a rounded rectangle around the logo
BASE_STYLES = ["outline", "hull", "rect"];

module logo_2d(file, width) {
    resize([width, 0], auto = true)
        import(file, center = true);
}

// Bounding box of a 2D child: the overlap of its full-width and full-height bands.
module bounding_box() {
    intersection() {
        minkowski() {
            hull() children();
            square([BAND_LENGTH, BAND_THIN], center = true);
        }

        minkowski() {
            hull() children();
            square([BAND_THIN, BAND_LENGTH], center = true);
        }
    }
}

module base_2d(file, width, style, border, corner_radius) {
    assert(search([style], BASE_STYLES) != [[]], str("unknown base style: ", style));

    if (style == "rect") {
        offset(r = corner_radius)
            offset(delta = border - corner_radius)
                bounding_box()
                    logo_2d(file, width);
    } else if (style == "hull") {
        offset(r = border)
            hull()
                logo_2d(file, width);
    } else {
        offset(r = border)
            logo_2d(file, width);
    }
}

module logo_plaque(
    file,
    width = LOGO_WIDTH,
    base_style = "outline",
    base_height = BASE_HEIGHT,
    logo_height = LOGO_HEIGHT,
    border = BORDER,
    corner_radius = CORNER_RADIUS
) {
    color(BASE_COLOR)
        linear_extrude(height = base_height)
            base_2d(file, width, base_style, border, corner_radius);

    color(LOGO_COLOR)
        translate([0, 0, base_height])
            linear_extrude(height = logo_height)
                logo_2d(file, width);
}
