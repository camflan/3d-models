# Client Logos

Small multi-color logo plaques for the companies I helped build at [Uplift](https://www.uplift.ltd). Each one uses at most 4 filaments, counting the base.

![Client logos preview](exports/client_logos_preview.png)

## Models

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

## Build pipeline

OpenSCAD's SVG import ignores fill colors, so each filament gets its own traced SVG:

```
src/logos/original/*  ──build_logos.py──►  src/logos/<slug>/<layer>.svg
                                           src/<slug>.scad
                                           exports/<slug>.3mf, exports/<slug>.stl
```

- `src/build_logos.py [slug ...]` builds all logos, or the ones named. Run it directly; `uv` installs its Python dependencies.
- Filament colors and widths live in the `LOGOS` table in that script. The `.scad` files are generated, so edit the table instead.
- `src/bambu_project_settings.json` is the settings template for the 3MF files (P1S, 0.4mm nozzle, 0.2mm layers).
- Needs `uv`, `potrace`, `librsvg` (`brew install potrace librsvg`) and OpenSCAD.

To add a client: save the logo in `src/logos/original/`, add an entry to `LOGOS`, and run the script.

## Printing

- Open the `.3mf` in Bambu Studio and match each filament slot to the filament you loaded
- All slots start with one PETG profile. Change it to suit your filament
- No supports needed
