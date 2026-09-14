#!/bin/bash
#
# Verifies a built distribution XCFramework.
#
#   ./Tools/verify-xcframework.sh <product> [<product> ...]
#   ./Tools/verify-xcframework.sh --all
#
# Three checks, in order of strength:
#
#   1. Every declared slice's Mach-O load commands really say what the slice
#      identifier claims, and an arm64 iOS Simulator slice exists.
#   2. The device slice links into an executable built for arm64 iOS.
#   3. The simulator slice links into an executable built for arm64 iOS
#      Simulator, which then runs on a booted simulator and exercises the
#      product's API (Tools/verification/<product>.swift or .m).
#
# Loading is not the same as working, so the per-product harnesses assert real
# decoded/logged/played results rather than only that dyld found the binary.
#
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Stages a product's xcframework slices into $1 so a harness can link them:
# frameworks by -F, static libraries by -l plus a headers directory.
stage_slices() {
    local name="$1" staging="$2"
    # The subshell keeps the sibling recipe's variables and hooks out of the
    # product under test.
    ( load_recipe "$name"
      local archive="$OUTPUT_DIR/$ARCHIVE_NAME"
      [ -f "$archive" ] || { echo "error: $name not built — run build-xcframework.sh $name" >&2; exit 1; }
      unzip -q "$archive" -d "$staging/$name" )
}

slice_dir() {
    local root="$1" variant="$2"   # variant: device | simulator
    local dir
    for dir in "$root"/*/; do
        case "$(basename "$dir")" in
            *-simulator) [ "$variant" = "simulator" ] && { echo "${dir%/}"; return; } ;;
            ios-*)       [ "$variant" = "device" ]    && { echo "${dir%/}"; return; } ;;
        esac
    done
}

################################ Slice checks ##################################

check_slices() {
    local xcframework="$1"
    echo "==> Declared slices"
    local found_sim_arm64=0 slice id binary arch platform label
    for slice in "$xcframework"/*/; do
        id="$(basename "$slice")"
        binary="$(find "$slice" -maxdepth 2 -type f \( -name "$PRODUCT" -o -name "lib$PRODUCT.a" \) | head -1)"
        [ -n "$binary" ] || { echo "error: no binary in slice $id" >&2; return 1; }
        for arch in $(lipo -archs "$binary"); do
            platform="$(mach_o_platform "$binary" "$arch")"
            case "$platform" in
                2) label="iOS device" ;;
                7) label="iOS Simulator" ;;
                *) label="platform ${platform:-unknown}" ;;
            esac
            printf '    %-34s %-8s -> %s\n' "$id" "$arch" "$label"

            # The identifier must not disagree with the load commands: a device
            # binary renamed into a simulator slice is exactly the failure this
            # whole exercise exists to prevent.
            case "$id" in
                *-simulator) [ "$platform" = "7" ] || { echo "error: $id/$arch is not a simulator binary" >&2; return 1; } ;;
                *)           [ "$platform" = "2" ] || { echo "error: $id/$arch is not a device binary" >&2; return 1; } ;;
            esac
            [ "$arch:$platform" = "arm64:7" ] && found_sim_arm64=1
        done
    done
    [ "$found_sim_arm64" -eq 1 ] || { echo "error: no arm64 iOS Simulator slice" >&2; return 1; }
}

############################### Harness builds #################################

# Assembles the swiftc/clang flags needed to link the product and anything it
# depends on, for one platform variant.
link_flags() {
    local staging="$1" variant="$2"
    local flags=() dep dir
    for dep in "$PRODUCT" ${VERIFY_DEPENDENCIES[@]+"${VERIFY_DEPENDENCIES[@]}"}; do
        dir="$(slice_dir "$staging/$dep/$dep.xcframework" "$variant")"
        if [ -d "$dir/$dep.framework" ]; then
            flags+=(-F "$dir" -framework "$dep")
        else
            flags+=(-I "$dir/Headers" -L "$dir" -l"$dep")
        fi
    done
    local fw
    for fw in ${LINK_FRAMEWORKS[@]+"${LINK_FRAMEWORKS[@]}"}; do
        flags+=(-framework "$fw")
    done
    printf '%s\n' "${flags[@]}"
}

build_harness() {
    local staging="$1" variant="$2" output="$3"
    local sdk triple flags=()
    case "$variant" in
        device)    sdk="iphoneos";       triple="arm64-apple-ios$DEPLOYMENT_TARGET" ;;
        simulator) sdk="iphonesimulator"; triple="arm64-apple-ios$DEPLOYMENT_TARGET-simulator" ;;
    esac
    while IFS= read -r flag; do flags+=("$flag"); done < <(link_flags "$staging" "$variant")

    if [ -f "$HARNESS_SWIFT" ]; then
        # Swift permits top-level statements only in a file called main.swift,
        # so the per-product harness is copied under that name to compile.
        cp "$HARNESS_SWIFT" "$(dirname "$output")/main.swift"
        xcrun swiftc -target "$triple" -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" \
            "${flags[@]}" -Xlinker -rpath -Xlinker @executable_path \
            $HARNESS_EXTRA_SOURCES "$(dirname "$output")/main.swift" -o "$output" 2>&1 \
            | grep -v 'incompatible-sysroot' || true
    else
        xcrun clang -target "$triple" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
            -fobjc-arc -fmodules "${flags[@]}" \
            -Xlinker -rpath -Xlinker @executable_path \
            "$HARNESS_OBJC" -o "$output" 2>&1 \
            | grep -v 'incompatible-sysroot' || true
    fi
    [ -f "$output" ]
}

################################### Driver #####################################

verify_product() {
    local name="$1"
    load_recipe "$name"

    local archive="$OUTPUT_DIR/$ARCHIVE_NAME"
    [ -f "$archive" ] || { echo "error: $name not built — run build-xcframework.sh $name" >&2; return 1; }

    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/$NAME-verify.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$work'" RETURN

    echo
    echo "################ Verifying $PRODUCT $VERSION ################"

    local staging="$work/staging"
    mkdir -p "$staging/$PRODUCT"
    unzip -q "$archive" -d "$staging/$PRODUCT"
    check_slices "$staging/$PRODUCT/$PRODUCT.xcframework"

    local dep
    for dep in ${VERIFY_DEPENDENCIES[@]+"${VERIFY_DEPENDENCIES[@]}"}; do
        stage_slices "$dep" "$staging"
    done

    HARNESS_SWIFT="$TOOLS_DIR/verification/$NAME.swift"
    HARNESS_OBJC="$TOOLS_DIR/verification/$NAME.m"
    if [ ! -f "$HARNESS_SWIFT" ] && [ ! -f "$HARNESS_OBJC" ]; then
        echo "==> No runtime harness for $NAME; slice checks only"
        return 0
    fi

    # Some harnesses need a fixture from the pinned upstream source.
    HARNESS_EXTRA_SOURCES=""
    if declare -F recipe_prepare_harness > /dev/null; then
        recipe_prepare_harness "$work"
    fi

    echo "==> Linking the device slice (arm64 iOS)"
    build_harness "$staging" device "$work/harness-device" \
        || { echo "error: device slice failed to link" >&2; return 1; }
    echo "    linked ($(lipo -archs "$work/harness-device"))"

    echo "==> Linking the simulator slice (arm64 iOS Simulator)"
    build_harness "$staging" simulator "$work/harness" \
        || { echo "error: simulator slice failed to link" >&2; return 1; }

    # dyld resolves @rpath/<name>.framework/<name> next to the executable.
    for dep in "$PRODUCT" ${VERIFY_DEPENDENCIES[@]+"${VERIFY_DEPENDENCIES[@]}"}; do
        local dir
        dir="$(slice_dir "$staging/$dep/$dep.xcframework" simulator)"
        [ -d "$dir/$dep.framework" ] && cp -R "$dir/$dep.framework" "$work/"
    done

    local udid
    udid="$(xcrun simctl list devices booted | awk -F'[()]' '/Booted/{print $2; exit}')"
    if [ -z "$udid" ]; then
        udid="$(xcrun simctl list devices available | awk -F'[()]' '/iPhone/{print $2; exit}')"
        echo "==> Booting simulator $udid"
        xcrun simctl boot "$udid"
        xcrun simctl bootstatus "$udid" -b > /dev/null
    fi

    echo "==> Running on simulator $udid"
    xcrun simctl spawn "$udid" "$work/harness"
    echo "==> $PRODUCT verified"
}

main() {
    local products=()
    case "${1:-}" in
        ""|-h|--help) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^#//; s/^ //'
                      echo "Products:"; list_recipes | sed 's/^/  /'; exit 0 ;;
        --all)        while read -r r; do products+=("$r"); done < <(list_recipes) ;;
        *)            products=("$@") ;;
    esac
    local product
    for product in "${products[@]}"; do
        verify_product "$product"
    done
}

main "$@"
