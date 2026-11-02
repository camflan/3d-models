# Client Logos

Small two-color logo plaques for the companies I helped build at [Uplift](https://www.uplift.ltd).

![Client logos preview](exports/client_logos_preview.png)

## Models

One `.scad` file per client in `src/`. Each one calls `logo_plaque()` from `src/lib/logo_plaque.scad`, which puts the raised logo on a base.

| Client | Width | Logo source |
|--------|-------|-------------|
| CES Utility Solutions | 80mm | `uplift-ltd/CES-Utility-Solutions` repo (PNG, traced) |
| Edwin | 70mm | edwingov.com (SVG) |
| Interflexion | 70mm | interflexion.com (PNG, traced) |
| Issue Voter | 70mm | issuevoter.org (PNG, traced) |
| Keel | 70mm | `uplift-ltd/old-keel` repo (SVG) |
| Lula | 70mm | lula.life (SVG) |
| OpenField | 100mm | openfield.ai, 2024 logo (PNG, traced as line art) |
| Pine Park Health | 100mm | pineparkhealth.com mark + wordmark (SVG), stacked |
| Sugar Living | 70mm | sugarliving.com (SVG) |
| Syncari | 70mm | syncari.com (SVG) |
| Zur Institute | 100mm | zurinstitute.com (JPG, traced) |

OpenField, Pine Park Health and Zur Institute are wider so that their small text stays at least 0.4mm thick. CES is wider for its "UTILITY SOLUTIONS" line.

**Key parameters (`logo_plaque()`):**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `width` | 70mm | Logo width |
| `base_style` | `outline` | `outline`, `hull` or `rect` (all clients use `rect`) |
| `base_height` | 2mm | Base thickness |
| `logo_height` | 1.2mm | Raised logo thickness |
| `border` | 3mm | Base margin around the logo |
| `corner_radius` | 4mm | Corner radius for `rect` |

## Logo pipeline

OpenSCAD's SVG import ignores fill colors, so white details inside a logo would merge into the shape. Every logo is traced into a one-color SVG first:

```
src/logos/original/<slug>.*  ──build_logos.sh──►  src/logos/<slug>.svg
```

- `src/logos/original/` holds the downloaded logos, as found.
- `src/build_logos.sh [slug]` traces all logos, or one. Each logo's trace mode (`ink`, `alpha` or `dark`) is set there; `src/trace_logo.sh` explains the modes.
- Needs `potrace`, `imagemagick` and `librsvg` (`brew install potrace imagemagick librsvg`).

To add a client: save the logo in `src/logos/original/`, add a line to `LOGOS` in `build_logos.sh`, run it, and copy any client `.scad` file.

## Printing

- Swap filament at the first layer above 2mm (the top of the base)
- No supports needed
