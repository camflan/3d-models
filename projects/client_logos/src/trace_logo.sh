#!/usr/bin/env bash
# Turn any logo image (SVG/PNG/JPG) into a one-color SVG that OpenSCAD can extrude.
#
#   original ──► large raster ──► ink mask (1-bit) ──► potrace ──► logos/<name>.svg
#
# OpenSCAD's SVG import ignores fill colors, so white details inside a logo
# would merge into the shape. Tracing a 1-bit mask keeps them as holes.
#
# Modes pick which pixels count as ink:
#   ink    any pixel that is not near-white (logos drawn on white or transparent)
#   alpha  any opaque pixel, whatever its color (light/white logos on transparent)
#   dark   only near-black pixels (multi-color art whose dark outlines carry the shape)

set -Eeuo pipefail

RASTER_WIDTH=3000
WHITE_FUZZ="15%"
TURD_SIZE=20
DARK_THRESHOLD="25%"

tmp=""

usage() {
    msg "usage: $(basename "$0") [-m ink|alpha|dark] <input> <output.svg>"
}

msg() {
    echo >&2 -e "${1-}"
}

die() {
    msg "$1"
    exit "${2-1}"
}

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    if [[ -n $tmp ]]; then
        rm -rf "$tmp"
    fi
}

parse_params() {
    mode=ink

    while :; do
        case "${1-}" in
            -h | --help)
                usage
                exit 0
                ;;
            -m | --mode)
                mode="${2-}"
                shift
                ;;
            -?*) die "unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done

    if [[ $# -ne 2 ]]; then
        usage
        exit 1
    fi

    input=$1
    output=$2
}

rasterize() {
    if [[ $input == *.svg ]]; then
        rsvg-convert -w "$RASTER_WIDTH" "$input" -o "$tmp/raster.png"
        return
    fi

    magick "$input" -resize "${RASTER_WIDTH}x" "$tmp/raster.png"
}

make_mask() {
    case "$mode" in
        ink)
            magick "$tmp/raster.png" -background white -alpha remove -alpha off \
                -fuzz "$WHITE_FUZZ" -fill black +opaque white \
                -threshold 50% -trim +repage "$tmp/mask.pbm"
            ;;
        alpha)
            magick "$tmp/raster.png" -alpha extract -threshold 50% -negate \
                -trim +repage "$tmp/mask.pbm"
            ;;
        dark)
            magick "$tmp/raster.png" -background white -alpha remove -alpha off \
                -colorspace gray -threshold "$DARK_THRESHOLD" -trim +repage "$tmp/mask.pbm"
            ;;
        *) die "unknown mode: $mode" ;;
    esac
}

main() {
    parse_params "$@"

    tmp=$(mktemp -d)
    trap cleanup SIGINT SIGTERM ERR EXIT

    rasterize
    make_mask
    potrace --svg --turdsize "$TURD_SIZE" --output "$output" "$tmp/mask.pbm"
}

main "$@"
