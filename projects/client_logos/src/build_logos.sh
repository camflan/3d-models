#!/usr/bin/env bash
# Trace every original logo into logos/<slug>.svg. See trace_logo.sh for modes.

set -Eeuo pipefail

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
ORIGINAL_DIR="$SRC_DIR/logos/original"
TRACED_DIR="$SRC_DIR/logos"

# slug  original file  mode
LOGOS=(
    "ces_utility_solutions ces_utility_solutions.png ink"
    "edwin edwin.svg alpha"
    "interflexion interflexion.png ink"
    "issue_voter issue_voter.png ink"
    "keel keel.svg alpha"
    "lula lula.svg alpha"
    "openfield openfield.png dark"
    "pine_park_health pine_park_health.svg alpha"
    "sugar_living sugar_living.svg ink"
    "syncari syncari.svg alpha"
    "zur_institute zur_institute.jpg ink"
)

msg() {
    echo >&2 -e "${1-}"
}

main() {
    local only=${1-}

    for entry in "${LOGOS[@]}"; do
        read -r slug original mode <<<"$entry"

        if [[ -n $only && $only != "$slug" ]]; then
            continue
        fi

        msg "tracing $slug ($mode)"
        "$SRC_DIR/trace_logo.sh" --mode "$mode" "$ORIGINAL_DIR/$original" "$TRACED_DIR/$slug.svg"
    done
}

main "$@"
