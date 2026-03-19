# Tape Bracket

Truss-style wall bracket for holding tape rolls, with MultiConnect slot mounting.

![Tape bracket preview](exports/tape_bracket_preview.png)

## Models

### tape_bracket (OpenSCAD)

Two-rod bracket with a truss web profile for strength/weight. Mounts to MultiConnect-compatible surfaces via keyhole slots.

**Key parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `rod_diameter` | 15.875mm | Rod diameter (5/8") |
| `rod_clearance` | 0.3mm | Fit clearance for rod holes |
| `arm_width` | 30mm | Bracket arm width (Y axis) |
| `min_wall` | 5mm | Minimum wall around rod holes |
| `inner_rod_x` | 25mm | Inner rod distance from wall |
| `outer_rod_x` | 80mm | Outer rod distance from wall |
| `mc_num_slots` | 2 | Number of MultiConnect slots |
| `mc_grid` | 25mm | MultiConnect slot spacing |

**Features:**
- Set screw recesses on each rod boss
- Filleted transitions at the back plate
- Rounded truss cutouts for weight reduction
