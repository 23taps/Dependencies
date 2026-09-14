#!/bin/bash
#
# Builds a distribution XCFramework from a pinned upstream source revision.
#
#   ./Tools/build-xcframework.sh <product> [<product> ...]
#   ./Tools/build-xcframework.sh --all
#   ./Tools/build-xcframework.sh --list
#
# Each product is described by a recipe in Tools/recipes/. The build clones the
# recipe's pinned commit, builds iOS device and iOS Simulator separately,
# assembles an XCFramework, writes the archive and a BUILD-RECORD.md into the
# dependency's version folder, and adds the version keys to its manifest.
#
# A fat `.framework` cannot carry an arm64 simulator slice: arm64 device and
# arm64 simulator are the same CPU type and cannot coexist in one Mach-O. That
# is why these products are distributed as XCFrameworks.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^#//; s/^ //'
    echo "Products:"
    list_recipes | sed 's/^/  /'
}

build_product() {
    local name="$1"
    load_recipe "$name"

    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-xcframework.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$work'" RETURN

    echo
    echo "################ $PRODUCT $VERSION ################"
    echo "==> Toolchain: $(xcodebuild -version | tr '\n' ' ')"

    fetch_pinned_source "$work/src"
    if declare -F recipe_prepare_source > /dev/null; then
        recipe_prepare_source "$work/src"
    fi

    local platform
    for platform in "iOS" "iOS Simulator"; do
        case "$KIND" in
            spm)
                archive_spm "$platform" "$work"
                finish_framework "$work"
                ;;
            static-library)
                build_static_library "$platform" "$work"
                ;;
            *)
                echo "error: unknown recipe kind '$KIND'" >&2
                return 1
                ;;
        esac
    done

    local xcframework="$work/$PRODUCT.xcframework"
    case "$KIND" in
        spm)            create_framework_xcframework "$work" "$xcframework" ;;
        static-library) create_library_xcframework   "$work" "$xcframework" ;;
    esac

    mkdir -p "$OUTPUT_DIR"
    local archive="$OUTPUT_DIR/$ARCHIVE_NAME"
    rm -f "$archive"
    ( cd "$work" && zip -r -X --quiet "$archive" "$PRODUCT.xcframework" )

    write_build_record "$OUTPUT_DIR" "$xcframework" "$archive"
    update_manifest "$MANIFEST_PATH" "${MANIFEST_KEYS[@]}"

    echo "==> Built $PRODUCT $VERSION"
    echo "    $archive ($(du -h "$archive" | cut -f1 | tr -d ' '))"
    echo "    $OUTPUT_DIR/BUILD-RECORD.md"
}

main() {
    local products=()
    case "${1:-}" in
        ""|-h|--help) usage; exit 0 ;;
        --list)       list_recipes; exit 0 ;;
        --all)        while read -r r; do products+=("$r"); done < <(list_recipes) ;;
        *)            products=("$@") ;;
    esac

    local product
    for product in "${products[@]}"; do
        build_product "$product"
    done
}

main "$@"
