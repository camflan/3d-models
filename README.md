# 3d-models

Personal CAD models — FreeCAD, Fusion 360, and OpenSCAD.

## Layout

```
projects/<name>/
├── src/          ← source files (.scad, .FCStd, .f3d)
├── exports/      ← committed mesh outputs (STL, 3MF, STEP)
└── README.md     ← notes, photos, print settings
```

## Setup

```sh
brew install --cask openscad
brew install entr
```

## Usage

```sh
make new P=widget        # scaffold a new project
make build               # build all .scad → .stl
make project P=widget    # build one project
make watch               # rebuild on save (for nvim workflow)
make watch-project P=widget
make preview F=projects/widget/src/widget.scad  # open OpenSCAD GUI
make export P=widget     # copy STLs to exports/
```

### Workflows

**OpenSCAD IDE** — open `.scad` files directly, or use `make preview F=…` to launch. The IDE auto-reloads on file save.

**nvim + watcher** — edit `.scad` in nvim, run `make watch` (or `make watch-project P=…`) in a split/terminal. Each save triggers a rebuild. Pair with OpenSCAD's GUI (`make preview`) for live visual feedback — it watches the file for changes too.

## Non-OpenSCAD projects

FreeCAD and Fusion projects follow the same directory layout. Place source files (`.FCStd`, `.f3d`) in `src/` and committed exports in `exports/`.
