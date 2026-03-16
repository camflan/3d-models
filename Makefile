# ──────────────────────────────────────────────────────────
# 3d-models — OpenSCAD build & preview tooling
# ──────────────────────────────────────────────────────────
#
# Dependencies: openscad (brew --cask), entr (brew)
#
# Directory layout per project:
#
#   projects/<name>/
#   ├── src/          ← .scad source files
#   ├── exports/      ← committed STL/3MF/STEP outputs
#   └── README.md     ← notes, photos, print settings
#
# ──────────────────────────────────────────────────────────

OPENSCAD := openscad
SCAD_SRC := $(shell find projects -name '*.scad' 2>/dev/null)
STL_OUT  := $(SCAD_SRC:%.scad=%.stl)

# Default: build all .scad → .stl alongside source
.PHONY: build
build: $(STL_OUT)

%.stl: %.scad
	$(OPENSCAD) -o $@ $<

# Build a single project: make project P=<name>
.PHONY: project
project:
	@test -n "$(P)" || (echo "usage: make project P=<name>" && exit 1)
	$(MAKE) $(shell find projects/$(P) -name '*.scad' | sed 's/\.scad$$/.stl/')

# ──────────────────────────────────────────────────────────
# Watch/preview workflows
# ──────────────────────────────────────────────────────────

# Rebuild STLs on save (all projects)
.PHONY: watch
watch:
	find projects -name '*.scad' | entr -r $(MAKE) build

# Rebuild STLs for a single project on save
.PHONY: watch-project
watch-project:
	@test -n "$(P)" || (echo "usage: make watch-project P=<name>" && exit 1)
	find projects/$(P) -name '*.scad' | entr -r $(MAKE) project P=$(P)

# Launch OpenSCAD GUI with auto-reload on a specific file
# Usage: make preview F=projects/widget/src/widget.scad
.PHONY: preview
preview:
	@test -n "$(F)" || (echo "usage: make preview F=<path/to/file.scad>" && exit 1)
	$(OPENSCAD) $(F) &

# ──────────────────────────────────────────────────────────
# Export helpers
# ──────────────────────────────────────────────────────────

# Copy built STLs into exports/ dir for a project
.PHONY: export
export:
	@test -n "$(P)" || (echo "usage: make export P=<name>" && exit 1)
	@mkdir -p projects/$(P)/exports
	find projects/$(P)/src -name '*.stl' -exec cp {} projects/$(P)/exports/ \;
	@echo "Exported to projects/$(P)/exports/"

# ──────────────────────────────────────────────────────────
# Scaffold
# ──────────────────────────────────────────────────────────

# Create a new project: make new P=<name>
.PHONY: new
new:
	@test -n "$(P)" || (echo "usage: make new P=<name>" && exit 1)
	@test ! -d "projects/$(P)" || (echo "projects/$(P) already exists" && exit 1)
	mkdir -p projects/$(P)/src projects/$(P)/exports
	@echo "# $(P)\n" > projects/$(P)/README.md
	@echo "Created projects/$(P)/"

.PHONY: clean
clean:
	find projects -name '*.stl' -path '*/src/*' -delete

.PHONY: help
help:
	@echo "Targets:"
	@echo "  build              Build all .scad → .stl"
	@echo "  project P=<name>   Build one project"
	@echo "  watch              Rebuild all on .scad save"
	@echo "  watch-project P=   Rebuild one project on save"
	@echo "  preview F=<file>   Open file in OpenSCAD GUI"
	@echo "  export P=<name>    Copy STLs to exports/"
	@echo "  new P=<name>       Scaffold a new project"
	@echo "  clean              Remove built STLs from src/"
