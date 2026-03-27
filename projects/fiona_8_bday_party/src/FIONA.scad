// Parameters
$fn = 128;

text = "FIONA";

border_width = 3;
height = 4;
size_mm = 130;

// Increased spacing to separate the letters
letter_spacing = 1.25; // Adjust this value as needed

module word(t) {
            text(t, 
                 size = size_mm - border_width * 2, 
                 font = "American Typewriter", 
                 halign = "center", 
                 valign = "center",
                 spacing = letter_spacing);
}

difference() {

color("red") {
    linear_extrude(height = height) {
        minkowski() {
            circle(r = border_width);
            word(text);
        }
    }
}

// Create the inner text with the same increased spacing

        linear_extrude(height = height) {
            word(text);

    }
}

    color("blue") {
        linear_extrude(height = height + 1) {
            word(text);
        }
    }