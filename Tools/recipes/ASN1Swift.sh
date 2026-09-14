# ASN1Swift — DER/ASN.1 decoder. TPInAppReceipt's only dependency.
REPO="https://github.com/tikhop/ASN1Swift.git"
VERSION="1.2.3"
TAG="1.2.3"
COMMIT="0f3150de37d38190768caaff19c498d85efad715"

OUTPUT_SUBDIR="ASN1Swift-1.2.3-xcframework"
MANIFEST_NAME="ASN1Swift-xcframework.json"
# `-no-bitcode` is a distribution key, not an upstream tag. Bitcode no longer
# exists in modern Xcode, so the rebuild is inherently bitcode-free and the
# app's existing pin keeps resolving.
MANIFEST_KEYS=("1.2.3" "1.2.3-no-bitcode")

# The distributed framework has always carried an empty privacy manifest that
# upstream 1.2.3 predates. Reproduce it so Apple's third-party SDK rule stays
# satisfied.
EXTRA_FRAMEWORK_FILES=("PrivacyInfo.xcprivacy")

recipe_prepare_source() {
    force_dynamic_products "$1/Package.swift"
}

# The runtime harness decodes the upstream test fixture's real receipts.
recipe_prepare_harness() {
    local work="$1"
    curl -fsSL "https://raw.githubusercontent.com/tikhop/ASN1Swift/$COMMIT/Tests/ASN1SwiftTests/ReceiptData.swift" \
        -o "$work/ReceiptData.swift"
    HARNESS_EXTRA_SOURCES="$work/ReceiptData.swift"
}
