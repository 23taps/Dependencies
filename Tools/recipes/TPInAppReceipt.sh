# TPInAppReceipt — App Store receipt parsing and validation. Depends on
# ASN1Swift, which must resolve to exactly the version this repository
# distributes.
REPO="https://github.com/tikhop/TPInAppReceipt.git"
VERSION="3.3.0"
TAG="3.3.0"
COMMIT="14f707e28fc7e19aadac72c8d63eb8610fa9c3bf"

OUTPUT_SUBDIR="TPInAppReceipt-3.3.0-xcframework"
MANIFEST_NAME="TPInAppReceipt-xcframework.json"
MANIFEST_KEYS=("3.3.0" "3.3.0-no-bitcode")

# ASN1Swift is supplied as its own dynamic framework, exactly once. The harness
# needs it on the link line and next to the executable at run time.
VERIFY_DEPENDENCIES=("ASN1Swift")

EXTRA_FRAMEWORK_FILES=("PrivacyInfo.xcprivacy")

ASN1SWIFT_VERSION="1.2.3"
ASN1SWIFT_COMMIT="0f3150de37d38190768caaff19c498d85efad715"

recipe_prepare_source() {
    local src="$1"
    local deps="$(dirname "$src")/deps"

    # Upstream allows any ASN1Swift up to the next major, and resolving it
    # normally would also keep upstream's static product type, absorbing its
    # implementation into TPInAppReceipt while this repository distributes the
    # same code again as its own framework. Vendor the exact commit instead and
    # force it dynamic, so TPInAppReceipt links @rpath/ASN1Swift.framework —
    # which is how the currently shipped binary is built.
    mkdir -p "$deps"
    fetch_source "$deps/ASN1Swift" "https://github.com/tikhop/ASN1Swift.git" \
        "$ASN1SWIFT_COMMIT" "$ASN1SWIFT_VERSION"
    force_dynamic_products "$deps/ASN1Swift/Package.swift"
    vendor_package_dependency "$src/Package.swift" "tikhop/ASN1Swift" "../deps/ASN1Swift"

    force_dynamic_products "$src/Package.swift"
}

recipe_prepare_harness() {
    local work="$1"
    curl -fsSL "https://raw.githubusercontent.com/tikhop/TPInAppReceipt/$COMMIT/Tests/TPInAppReceiptTests/ReceiptData.swift" \
        -o "$work/ReceiptData.swift" || true
    [ -s "$work/ReceiptData.swift" ] && HARNESS_EXTRA_SOURCES="$work/ReceiptData.swift"
}
