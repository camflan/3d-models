// Example: parametric rounded cube

size = [30, 20, 10];
corner_r = 2;

minkowski() {
    cube(size - [corner_r, corner_r, corner_r] * 2, center = true);
    sphere(r = corner_r, $fn = 32);
}
