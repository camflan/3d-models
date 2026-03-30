// Parameters
$fn = 50;

names = [
    "Meghan",
    "Lili",
    // "Ara",
    // "Fiona",
    // "Elise",
    // "Khady",
    // "Mira",
    // "Rowynne",
    // "Ruby",
    // "Sienna",
];

//font = "0xProto:style=Italic";
//font = "Apple Chancery";
//font = "Bodoni 72 Oldstyle:style=Book Italic";
//font = "Charter:style=Black Italic";
 font = "Georgia:style=Bold Italic";
//font = "IBM Plex Sans:style=Bold Italic";
//font = "IBM Plex Serif:style=Bold Italic";
//font = "Inter:style=Bold Italic";
//font = "New York Extra Large:style=Bold Italic";
// font = "Phosphate:style=Solid";
// font = "Rockwell:style=Bold Italic";
//font = "SignPainter";
//font = "Faster One";

bg_color = "black";
fg_color = "pink";

bg_height = 4;
fg_height = 2;
border_width = 4;
line_spacing = 1.8;
size_mm = 20;

ring_offset = -10;
ring_inner_radius = 7;
ring_thickness = 4;
ring_cylinder_spacing = 15;

// Increased spacing to separate the letters
letter_spacing = 1; // Adjust this value as needed

module render_word(t) {
    text(t,
            size = size_mm, // - border_width * 2,
            font = font,
            halign = "left",
            valign = "center",
            spacing = letter_spacing,
        );
}

module pill(r, spacing) {
    hull() {
        circle(r = r);

        translate([spacing, 0, 0])
            circle(r = r);
    }
}

module keyring(
        inner = ring_inner_radius,
        spacing = ring_cylinder_spacing,
        thickness = ring_thickness,
        height = height
        ) {
    linear_extrude(height = height) {
        difference() {
            pill(r = inner, spacing = spacing);

            offset(r = -thickness) {
                pill(r = inner, spacing = spacing);
            }
        }
    }
}

module render_outlined_word(text) {
    color(bg_color) {
        linear_extrude(height = bg_height) {
            minkowski() {
                circle(r = border_width);
                render_word(text);
            }
        }
    }

    translate([0, 0, bg_height - 0.5])
        color(fg_color) {
            linear_extrude(height = fg_height + 0.5) {
                render_word(text);
            }
        }

    color(bg_color)
        translate([ring_offset, 0, 0])
        keyring(height = bg_height);
}

translate([25, 0, 0])
    for(i = [0:len(names)-1]) {
        translate([0, -i * size_mm * line_spacing, 0])
            render_outlined_word(names[i]);
    }
