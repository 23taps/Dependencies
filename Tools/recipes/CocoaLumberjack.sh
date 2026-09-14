# CocoaLumberjack — the Objective-C logging core. The Swift API is a separate
# product built from this same source; see CocoaLumberjackSwift.
REPO="https://github.com/CocoaLumberjack/CocoaLumberjack.git"
VERSION="3.8.5"
TAG="3.8.5"
COMMIT="4b8714a7fb84d42393314ce897127b3939885ec3"

OUTPUT_SUBDIR="CocoaLumberjack-3.8.5-xcframework"
MANIFEST_NAME="CocoaLumberjack-xcframework.json"
MANIFEST_KEYS=("3.8.5")

recipe_prepare_source() {
    force_dynamic_products "$1/Package.swift"
}
