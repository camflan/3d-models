# Client Logos

Small multi-color logo models for the companies I helped build at [Uplift](https://www.uplift.ltd). Each client has a plaque and a standalone mark. Each model uses at most 4 filaments.

![Client logos preview](exports/client_logos_preview.png)

## Plaques

`exports/<slug>.3mf` opens in Bambu Studio with one part per filament, already assigned. `exports/<slug>.stl` is the whole plaque as one mesh, for single-color prints.

| Client | Width | Base | Logo filaments | Logo source |
|--------|-------|------|----------------|-------------|
| CES Utility Solutions | 80mm | white | blue, black | `uplift-ltd/CES-Utility-Solutions` repo (PNG) |
| Edwin | 70mm | navy | beige | edwingov.com (SVG) |
| Interflexion | 70mm | white | blue, purple, green | interflexion.com (PNG) |
| Issue Voter | 70mm | white | teal, red | issuevoter.org (PNG) |
| Keel | 70mm | white | blue | `uplift-ltd/old-keel` repo (SVG) |
| Lula | 70mm | white | green | lula.life (SVG) |
| OpenField | 100mm | black | green, blue, yellow | openfield.ai, 2024 logo (PNG) |
| Pine Park Health | 100mm | white | green | pineparkhealth.com mark + wordmark (SVG), stacked |
| Sugar Living | 70mm | white | navy, blue | sugarliving.com (SVG) |
| Syncari | 70mm | near-black | blue, white | syncari.com (SVG) |
| Zur Institute | 100mm | white | yellow, orange, black | zurinstitute.com (JPG) |

Some logos change to fit the filament limit or to print well:

- **OpenField:** the original needs 5 colors. The black base becomes the badge's outlines, and the black wordmark prints yellow so that it shows on the base.
- **Zur Institute:** the five petal colors reduce to yellow and orange.
- **Sugar Living:** the icon's gradient reduces to one blue.
- **Edwin, Syncari:** these logos are light colored for dark backgrounds, so they get a dark base.
- **Keel:** the source file is black. It prints in the blue from Keel's site.

OpenField, Pine Park Health and Zur Institute are wider so that their small text stays at least 0.4mm thick. CES is wider for its "UTILITY SOLUTIONS" line.

**Key parameters (`src/lib/logo_plaque.scad`):**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `base_height` | 2mm | Base thickness |
| `logo_height` | 1.2mm | Raised logo thickness |
| `border` | 3mm | Base margin around the logo |
| `corner_radius` | 4mm | Base corner radius |

## Marks

The logo extruded 4mm with no base. A logo with a symbol keeps only the symbol.

![Client marks preview](exports/client_marks_preview.png)

`exports/<slug>_mark.3mf` has one part per filament. `exports/<slug>_mark.stl` is one mesh, for single-color prints.

| Client | Size | Filaments | Keeps |
|--------|------|-----------|-------|
| CES Utility Solutions | 70 x 42mm | blue | swoosh and "CES" |
| Edwin | 50 x 66mm | beige | building |
| Interflexion | 50 x 56mm | blue, purple, green | symbol |
| Issue Voter | 100 x 12mm | teal, red | wordmark |
| Keel | 70 x 35mm | blue | wordmark |
| Lula | 70 x 33mm | green | wordmark |
| OpenField | 50 x 50mm | black, green, blue, yellow | badge |
| Pine Park Health | 50 x 42mm | green | symbol |
| Sugar Living | 50 x 50mm | blue, white | icon |
| Syncari | 50 x 35mm | blue | cloud |
| Zur Institute | 50 x 59mm | yellow, orange | sun |

- **Ties:** where a logo has loose pieces, 2mm wide bars join them in the lowest 1.2mm. The bars sit 2.8mm below the logo's face. Set `tie_height` in `logo_mark` to change their height.
- **Interflexion:** the symbol comes from the site's 120px icon (`interflexion_mark.png`), which is sharper than the symbol in its full logo.
- **Sugar Living:** the icon's white parts print in white filament. As holes, they would leave the center loose.
- **OpenField:** the black outlines print in black filament, because there is no base to form them.

### Tie color

By default, ties print in the logo's colors. To print them in another color, set `tie_color` on the entry in `MARKS`, then run `src/build_logos.py <slug>_mark`:

```python
Logo("keel_mark", "keel.svg", WORDMARK_WIDTH, None, (...), tie_color=BLACK)
```

This adds a 1.2mm back layer: the logo's outline plus the ties, in that color. The logo sits on top of it, and the model stays 4mm thick. The back layer takes one filament, and a model can use at most 4.

![Tie options](exports/tie_options_preview.png)

## Avatars

`exports/<slug>_avatar.3mf` and `.stl` are the mark raised 1.2mm on a 60mm round base, 2mm thick. The logo scales to fit inside the circle with a 3mm margin, so it needs no ties.

To add or remove an avatar, edit `AVATAR_BASES` in `src/build_logos.py`, which sets the base color for each client. `AVATAR_DIAMETER_MM` sets the size.

| Client | Base | Logo size |
|--------|------|-----------|
| CES Utility Solutions | white | 54 x 33mm |
| Edwin | navy | 33 x 43mm |
| Interflexion | white | 48 x 54mm |
| Issue Voter | white | 54 x 7mm |
| Keel | white | 48 x 24mm |
| Pine Park Health | white | 47 x 39mm |

## Build pipeline

OpenSCAD's SVG import ignores fill colors, so each filament gets its own traced SVG:

```
src/logos/original/*  ──build_logos.py──►  src/logos/<slug>/<layer>.svg
                                           src/<slug>.scad
                                           exports/<slug>.3mf, exports/<slug>.stl
```

- `src/build_logos.py [slug ...]` builds all logos, or the ones named. Run it directly; `uv` installs its Python dependencies.
- Filament colors and widths live in the `LOGOS`, `MARKS` and `AVATAR_BASES` tables in that script. The `.scad` files are generated, so edit the table instead.
- `src/bambu_project_settings.json` is the settings template for the 3MF files (P1S, 0.4mm nozzle, 0.2mm layers).
- Needs `uv`, `potrace`, `librsvg` (`brew install potrace librsvg`) and OpenSCAD.

To add a client: save the logo in `src/logos/original/`, add an entry to `LOGOS` or `MARKS`, and run the script.

## Printing

- Open the `.3mf` in Bambu Studio and match each filament slot to the filament you loaded
- All slots start with one PETG profile. Change it to suit your filament
- No supports needed
- Marks with more than one color are slow because of filament changes on every layer. OpenField takes about 2.5 hours. The `.stl` prints a mark in one color
