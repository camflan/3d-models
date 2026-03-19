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
PNG_OUT  := $(foreach s,$(SCAD_SRC),$(dir $(s))../exports/$(notdir $(s:.scad=_preview.png)))

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

# ──────────────────────────────────────────────────────────
# Preview image generation
# ──────────────────────────────────────────────────────────

.PHONY: previews
previews: $(PNG_OUT)

projects/%/exports/%_preview.png: projects/%/src/%.scad
	@mkdir -p $(dir $@)
	$(OPENSCAD) --render -o $@ --imgsize=800,600 $<

# Generate previews for a single project: make preview-images P=<name>
.PHONY: preview-images
preview-images:
	@test -n "$(P)" || (echo "usage: make preview-images P=<name>" && exit 1)
	@for f in projects/$(P)/src/*.scad; do \
		[ -f "$$f" ] || continue; \
		base=$$(basename "$$f" .scad); \
		mkdir -p projects/$(P)/exports; \
		$(OPENSCAD) --render -o "projects/$(P)/exports/$${base}_preview.png" --imgsize=800,600 "$$f"; \
	done

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
	@echo "  previews           Render all .scad → preview PNG"
	@echo "  preview-images P=  Render PNGs for one project"
	@echo "  clean              Remove built STLs from src/"
