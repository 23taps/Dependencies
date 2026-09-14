#!/bin/bash
#
# Shared machinery for building and verifying distribution XCFrameworks from
# pinned upstream sources. Sourced by build-xcframework.sh and
# verify-xcframework.sh; not meant to be run directly.
#

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$REPO_ROOT/Tools"

# This machine's `xcode-select` points at Xcode 26.4. Pin the toolchain so a
# build does not depend on the global selection.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode27RC.app/Contents/Developer}"

############################### Recipe loading #################################

# Defaults every recipe inherits. A recipe overrides what it needs.
recipe_defaults() {
    FOLDER="$NAME"                  # dependency folder in this repository
    SCHEME="$NAME"                  # scheme to archive (spm kind)
    PRODUCT="$NAME"                 # framework/library name in the xcframework
    KIND="spm"                      # spm | static-library
    DEPLOYMENT_TARGET="15.0"
    DEVICE_ARCHS="arm64"
    SIMULATOR_ARCHS="arm64 x86_64"
    BUNDLE_IDENTIFIER="com.emoji.$NAME"
    EXTRA_FRAMEWORK_FILES=()        # files in the dependency folder to copy in
    LINK_FRAMEWORKS=()              # Apple frameworks a consumer must link
    SOURCE_FILES=()                 # static-library kind: implementation files
    HEADER_FILES=()                 # static-library kind: public headers
    NOTES=""                        # loaded from <recipe>.notes.md
    VERIFY_DEPENDENCIES=()          # sibling products the harness links
    HARNESS_EXTRA_SOURCES=""         # extra sources compiled into the harness
    # Hooks are plain functions, so they survive into the next recipe loaded in
    # the same process unless cleared.
    unset -f recipe_prepare_source recipe_prepare_harness 2>/dev/null || true
}

load_recipe() {
    local name="$1"
    local path="$TOOLS_DIR/recipes/$name.sh"
    [ -f "$path" ] || {
        echo "error: no recipe for '$name'. Available:" >&2
        list_recipes | sed 's/^/  /' >&2
        return 1
    }
    NAME="$name"
    recipe_defaults
    # shellcheck source=/dev/null
    source "$path"

    # Prose lives beside the recipe as markdown: shell quoting mangles it, and
    # macOS bash 3.2 mis-parses a here-document inside a command substitution.
    if [ -f "$TOOLS_DIR/recipes/$name.notes.md" ]; then
        NOTES="$(cat "$TOOLS_DIR/recipes/$name.notes.md")"
    fi

    OUTPUT_DIR="$REPO_ROOT/$FOLDER/$OUTPUT_SUBDIR"
    MANIFEST_PATH="$REPO_ROOT/$FOLDER/$MANIFEST_NAME"
    ARCHIVE_NAME="$PRODUCT.xcframework.zip"
}

list_recipes() {
    for f in "$TOOLS_DIR"/recipes/*.sh; do
        [ -e "$f" ] && basename "$f" .sh
    done
}

################################ Source fetch ##################################

# Clones REPO at COMMIT into $1 and asserts the commit really is tag VERSION.
# A tag can be moved upstream; the commit cannot.
fetch_source() {
    local dest="$1" repo="$2" commit="$3" tag="$4"
    git clone --quiet --no-checkout "$repo" "$dest"
    git -C "$dest" checkout --quiet "$commit"
    git -C "$dest" tag --points-at "$commit" | grep -qx "$tag" || {
        echo "error: commit $commit is not tag $tag in $repo" >&2
        return 1
    }
    rm -rf "$dest/.git"
}

fetch_pinned_source() {
    echo "==> Fetching $NAME $VERSION ($COMMIT)"
    fetch_source "$1" "$REPO" "$COMMIT" "$TAG"
}

# SwiftPM resolves library products without an explicit type as static.
# `xcodebuild archive` only installs a framework for a dynamic product, and
# these dependencies are embedded as dynamic frameworks, so force the type.
# Packaging only — no implementation source is touched.
force_dynamic_products() {
    local manifest="$1"
    perl -i -p0e 's/type: \.static,//g'                     "$manifest"
    perl -i -p0e 's/type: \.dynamic,//g'                    "$manifest"
    # `[^,]*` spans newlines under -0, so this covers both the one-line and the
    # wrapped `.library(` spellings these packages use.
    perl -i -p0e 's/(library\([^,]*,)/$1 type: .dynamic,/g' "$manifest"
}

# Rewrites one SwiftPM dependency declaration in place.
#   rewrite_package_dependency <Package.swift> <repo url fragment> <replacement>
#
# A regex alone cannot find the end of the declaration: the requirement is
# itself a nested call such as `.upToNextMajor(from: "1.0.0")`, so the closing
# parenthesis has to be found by balancing.
rewrite_package_dependency() {
    DEP_MANIFEST="$1" DEP_MATCH="$2" DEP_REPLACEMENT="$3" python3 - <<'PYTHON'
import os, pathlib, re, sys

manifest = pathlib.Path(os.environ["DEP_MANIFEST"])
match = os.environ["DEP_MATCH"]
replacement = os.environ["DEP_REPLACEMENT"]
text = manifest.read_text()

opener = re.compile(r'\.package\(\s*url:\s*"([^"]*' + re.escape(match) + r'[^"]*)"')
found = list(opener.finditer(text))
if len(found) != 1:
    sys.exit(f"error: expected exactly one {match} dependency, found {len(found)}")

m = found[0]
depth, i = 0, text.index("(", m.start())
while i < len(text):
    if text[i] == "(":
        depth += 1
    elif text[i] == ")":
        depth -= 1
        if depth == 0:
            break
    i += 1
else:
    sys.exit(f"error: unbalanced .package( for {match}")

manifest.write_text(
    text[: m.start()] + replacement.replace("@URL@", m.group(1)) + text[i + 1 :]
)
PYTHON
}

# Narrows a dependency to an exact version, so a build cannot resolve an
# implementation other than the one this repository distributes.
pin_package_dependency() {
    rewrite_package_dependency "$1" "$2" '.package(url: "@URL@", .exact("'"$3"'"))'
    echo "    pinned $2 to exactly $3"
}

# Repoints a dependency at a local checkout.
#
# Pinning a version is not enough on its own: a dependency resolved from its own
# manifest keeps that manifest's product type, so a static upstream product is
# absorbed into the consumer's binary. The application expects such a dependency
# to be supplied once, as its own dynamic framework. Vendoring it lets the build
# force its product type the same way it forces the consumer's.
vendor_package_dependency() {
    rewrite_package_dependency "$1" "$2" '.package(path: "'"$3"'")'
    echo "    vendored $2 from $3"
}

################################## Building ####################################

platform_archs() {
    case "$1" in
        "iOS")           echo "$DEVICE_ARCHS" ;;
        "iOS Simulator") echo "$SIMULATOR_ARCHS" ;;
    esac
}

platform_release_folder() {
    case "$1" in
        "iOS")           echo "Release-iphoneos" ;;
        "iOS Simulator") echo "Release-iphonesimulator" ;;
    esac
}

platform_sdk() {
    case "$1" in
        "iOS")           echo "iphoneos" ;;
        "iOS Simulator") echo "iphonesimulator" ;;
    esac
}

# Target triple suffix for a simulator vs device build.
platform_triple_suffix() {
    case "$1" in
        "iOS")           echo "" ;;
        "iOS Simulator") echo "-simulator" ;;
    esac
}

# Archives the SwiftPM scheme for one platform and leaves an installed
# framework at $FRAMEWORK_PATH.
archive_spm() {
    local platform="$1" work="$2"
    local release_folder archive_path derived_data
    release_folder="$(platform_release_folder "$platform")"
    archive_path="$work/$release_folder.xcarchive"
    # One derived data path per platform: sharing one lets the second archive
    # clean the first one's build products before they can be collected.
    derived_data="$work/dd-$release_folder"

    echo "==> Archiving $PRODUCT for $platform ($(platform_archs "$platform"))"
    ( cd "$work/src" && xcodebuild archive \
        -scheme "$SCHEME" \
        -destination "generic/platform=$platform" \
        -configuration Release \
        -archivePath "$archive_path" \
        -derivedDataPath "$derived_data" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_IDENTIFIER" \
        ARCHS="$(platform_archs "$platform")" \
        ONLY_ACTIVE_ARCH=NO \
        EXCLUDED_ARCHS="" \
        "EXCLUDED_ARCHS[sdk=iphonesimulator*]=" \
        IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        > "$work/$release_folder.log" 2>&1 ) || {
            echo "error: archive failed — see $work/$release_folder.log" >&2
            tail -40 "$work/$release_folder.log" >&2
            return 1
        }

    # Where the framework installs depends on the package: a bare SwiftPM
    # product lands in `usr/local/lib`, while a target with its own framework
    # settings lands in `Library/Frameworks`. Find it rather than assume.
    FRAMEWORK_PATH="$(find "$archive_path/Products" -type d -name "$PRODUCT.framework" | head -1)"
    DSYM_PATH="$archive_path/dSYMs/$PRODUCT.framework.dSYM"
    BUILD_PRODUCTS="$derived_data/Build/Intermediates.noindex/ArchiveIntermediates/$SCHEME/BuildProductsPath/$release_folder"

    [ -n "$FRAMEWORK_PATH" ] && [ -d "$FRAMEWORK_PATH" ] || {
        echo "error: no $PRODUCT.framework installed in $archive_path/Products" >&2
        find "$archive_path/Products" -maxdepth 4 >&2
        return 1
    }
}

# Completes an archived SwiftPM framework: Swift modules, resource bundles,
# extra bundle files, version stamp, signature.
finish_framework() {
    local work="$1"
    local modules="$FRAMEWORK_PATH/Modules"
    mkdir -p "$modules"

    # SwiftPM does not install Swift modules into the archived framework.
    # These build-products entries are symlinks into the installation location,
    # so every copy here dereferences (-L); a plain -R would copy the link and
    # leave a dangling reference that xcframework assembly silently drops.
    if [ -d "$BUILD_PRODUCTS/$PRODUCT.swiftmodule" ]; then
        cp -RL "$BUILD_PRODUCTS/$PRODUCT.swiftmodule" "$modules/"
    fi
    # Pure Objective-C products need a module map instead.
    if [ ! -d "$modules/$PRODUCT.swiftmodule" ] && [ ! -f "$modules/module.modulemap" ]; then
        if [ -d "$FRAMEWORK_PATH/Headers" ]; then
            write_umbrella_modulemap "$FRAMEWORK_PATH"
        else
            echo "module $PRODUCT { export * }" > "$modules/module.modulemap"
        fi
    fi

    # Resource bundles produced by the package (privacy manifests, certificates).
    local bundle
    for bundle in "$BUILD_PRODUCTS"/*.bundle; do
        [ -e "$bundle" ] || continue
        cp -RL "$bundle" "$FRAMEWORK_PATH/"
        [ -d "$FRAMEWORK_PATH/$(basename "$bundle")" ] || {
            echo "error: $(basename "$bundle") did not land in the framework" >&2
            return 1
        }
        echo "    bundled $(basename "$bundle")"
    done

    # Files kept alongside the recipe, e.g. a privacy manifest the pinned
    # source predates but the distributed binary has always carried.
    local extra
    for extra in ${EXTRA_FRAMEWORK_FILES[@]+"${EXTRA_FRAMEWORK_FILES[@]}"}; do
        cp "$REPO_ROOT/$FOLDER/$extra" "$FRAMEWORK_PATH/"
        echo "    added $extra"
    done

    # SwiftPM stamps a generic 1.0; restore the real library version.
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
        "$FRAMEWORK_PATH/Info.plist" > /dev/null

    # A simulator archive arrives ad-hoc signed and the edits above invalidate
    # that signature. Drop it: the app re-signs embedded frameworks on copy, and
    # the frameworks this repository distributes today carry no signature.
    rm -rf "$FRAMEWORK_PATH/_CodeSignature"

    echo "    $(lipo -archs "$FRAMEWORK_PATH/$PRODUCT")"
}

write_umbrella_modulemap() {
    local framework="$1"
    local umbrella="$framework/Headers/$PRODUCT.h"
    if [ -f "$umbrella" ]; then
        cat > "$framework/Modules/module.modulemap" <<MODULEMAP
framework module $PRODUCT {
  umbrella header "$PRODUCT.h"

  export *
  module * { export * }
}
MODULEMAP
    else
        cat > "$framework/Modules/module.modulemap" <<MODULEMAP
framework module $PRODUCT {
  umbrella "Headers"

  export *
  module * { export * }
}
MODULEMAP
    fi
}

# Compiles the recipe's Objective-C sources into a static library for one
# platform. Used by products with no package manifest or usable Xcode project.
build_static_library() {
    local platform="$1" work="$2"
    local release_folder sdk_path triple archs
    release_folder="$(platform_release_folder "$platform")"
    sdk_path="$(xcrun --sdk "$(platform_sdk "$platform")" --show-sdk-path)"
    archs="$(platform_archs "$platform")"

    echo "==> Compiling $PRODUCT for $platform ($archs)"
    local objects=() arch_libs=()
    local arch src obj
    for arch in $archs; do
        triple="$arch-apple-ios$DEPLOYMENT_TARGET$(platform_triple_suffix "$platform")"
        objects=()
        mkdir -p "$work/obj/$release_folder/$arch"
        for src in "${SOURCE_FILES[@]}"; do
            obj="$work/obj/$release_folder/$arch/$(basename "${src%.m}").o"
            xcrun clang -c "$work/src/$src" -o "$obj" \
                -target "$triple" -isysroot "$sdk_path" \
                -fobjc-arc -fmodules -Os -g \
                -I "$work/src/$(dirname "${SOURCE_FILES[0]}")" \
                2> "$work/compile-$arch.log" || {
                    echo "error: compiling $src failed" >&2
                    cat "$work/compile-$arch.log" >&2
                    return 1
                }
            objects+=("$obj")
        done
        xcrun libtool -static -o "$work/obj/$release_folder/lib$PRODUCT-$arch.a" "${objects[@]}" 2>/dev/null
        arch_libs+=("$work/obj/$release_folder/lib$PRODUCT-$arch.a")
    done

    mkdir -p "$work/$release_folder"
    LIBRARY_PATH="$work/$release_folder/lib$PRODUCT.a"
    if [ "${#arch_libs[@]}" -gt 1 ]; then
        lipo -create "${arch_libs[@]}" -output "$LIBRARY_PATH"
    else
        cp "${arch_libs[0]}" "$LIBRARY_PATH"
    fi

    # Public headers, plus a module map so the library can be imported as a
    # module rather than only through #import.
    HEADERS_PATH="$work/$release_folder/Headers"
    mkdir -p "$HEADERS_PATH"
    local header
    for header in "${HEADER_FILES[@]}"; do
        cp "$work/src/$header" "$HEADERS_PATH/"
    done
    echo "    $(lipo -archs "$LIBRARY_PATH")"
}

############################### Packaging ######################################

create_framework_xcframework() {
    local work="$1" output="$2" folder args=()
    for folder in Release-iphoneos Release-iphonesimulator; do
        args+=(-framework "$(find "$work/$folder.xcarchive/Products" -type d -name "$PRODUCT.framework" | head -1)")
        args+=(-debug-symbols "$work/$folder.xcarchive/dSYMs/$PRODUCT.framework.dSYM")
    done
    echo "==> Creating $PRODUCT.xcframework"
    xcodebuild -create-xcframework "${args[@]}" -output "$output" > /dev/null
}

create_library_xcframework() {
    local work="$1" output="$2"
    echo "==> Creating $PRODUCT.xcframework"
    xcodebuild -create-xcframework \
        -library "$work/Release-iphoneos/lib$PRODUCT.a" \
        -headers "$work/Release-iphoneos/Headers" \
        -library "$work/Release-iphonesimulator/lib$PRODUCT.a" \
        -headers "$work/Release-iphonesimulator/Headers" \
        -output "$output" > /dev/null
}

# "| `ios-arm64` | arm64 | 2 (iOS) |" rows for the build record, and the
# platform assertions the verifier reuses.
slice_table() {
    local xcframework="$1" slice binary id archs first platform label
    for slice in "$xcframework"/*/; do
        id="$(basename "$slice")"
        binary="$(find "$slice" -maxdepth 2 -type f \( -name "$PRODUCT" -o -name "lib$PRODUCT.a" \) | head -1)"
        [ -n "$binary" ] || continue
        archs="$(lipo -archs "$binary" | sed 's/ /, /g')"
        first="$(lipo -archs "$binary" | awk '{print $1}')"
        platform="$(mach_o_platform "$binary" "$first")"
        case "$platform" in
            2) label="2 (iOS)" ;;
            7) label="7 (iOS Simulator)" ;;
            *) label="$platform" ;;
        esac
        echo "| \`$id\` | $archs | $label |"
    done
}

# Reads LC_BUILD_VERSION's platform for one architecture. Works for both a
# Mach-O binary and a static archive (whose members carry the load command).
mach_o_platform() {
    local binary="$1" arch="$2"
    otool -l -arch "$arch" "$binary" 2>/dev/null \
        | awk '/LC_BUILD_VERSION/{found=1; next} found && /platform/{print $2; exit}'
}

write_build_record() {
    local output_dir="$1" xcframework="$2" archive="$3"
    local notes_section=""
    [ -n "$NOTES" ] && notes_section=$'\n'"$NOTES"$'\n'

    local keys bundle_row=""
    keys="$(printf '`%s` ' "${MANIFEST_KEYS[@]}")"
    keys="${keys% }"
    # A static library has no bundle, so the identifier is meaningless there.
    [ "$KIND" = "spm" ] && bundle_row=$'\n'"| Bundle identifier | \`$BUNDLE_IDENTIFIER\` |"

    cat > "$output_dir/BUILD-RECORD.md" <<RECORD
# $PRODUCT $VERSION — XCFramework build record

Generated by \`Tools/build-xcframework.sh $NAME\`. Do not edit by hand.

| | |
| --- | --- |
| Upstream | $REPO |
| Source tag | \`$TAG\` |
| Resolved commit | \`$COMMIT\` |
| Distribution keys | $keys |
| Manifest | \`$FOLDER/$MANIFEST_NAME\` |
| Toolchain | $(xcodebuild -version | head -1) ($(xcodebuild -version | tail -1)) |
| Swift | $(xcrun swift --version 2>/dev/null | head -1) |
| Deployment target | iOS $DEPLOYMENT_TARGET |$bundle_row
| Built | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |
| Archive SHA-256 | \`$(shasum -a 256 "$archive" | cut -d' ' -f1)\` |

Slices:

| Library identifier | Architectures | Mach-O platform |
| --- | --- | --- |
$(slice_table "$xcframework")

Device \`armv7\` and simulator \`i386\` are intentionally absent: neither is
supported by current Xcode, and the app's iOS 15 minimum does not need them.
$notes_section
RECORD
}

# Adds or updates this product's keys in its JSON manifest, leaving every other
# key and every other manifest untouched.
update_manifest() {
    local manifest="$1"
    shift
    MANIFEST_PATH="$manifest" \
    MANIFEST_URL_BASE="https://github.com/23taps/Dependencies/raw/master/$FOLDER/$OUTPUT_SUBDIR/$ARCHIVE_NAME" \
    MANIFEST_NEW_KEYS="$*" \
    python3 - <<'PYTHON'
import json, os, pathlib

path = pathlib.Path(os.environ["MANIFEST_PATH"])
url = os.environ["MANIFEST_URL_BASE"]
keys = os.environ["MANIFEST_NEW_KEYS"].split()

entries = json.loads(path.read_text()) if path.exists() else {}
changed = [k for k in keys if entries.get(k) != url]
entries.update({k: url for k in keys})

# Match the formatting of the manifests already in this repository: tabs, and
# keys in the order they were added.
body = ",\n".join(f'\t"{k}": "{v}"' for k, v in entries.items())
path.write_text("{\n" + body + "\n}\n")
print(f"    {'updated' if changed else 'unchanged'}: {path.name} ({', '.join(keys)})")
PYTHON
}
