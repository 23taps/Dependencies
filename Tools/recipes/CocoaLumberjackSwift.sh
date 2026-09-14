# CocoaLumberjackSwift — the Swift logging API. Built from the same
# CocoaLumberjack tag as the core, and depends on it at run time.
REPO="https://github.com/CocoaLumberjack/CocoaLumberjack.git"
VERSION="3.8.5"
TAG="3.8.5"
COMMIT="4b8714a7fb84d42393314ce897127b3939885ec3"

FOLDER="CocoaLumberjackSwift"
SCHEME="CocoaLumberjackSwift"
PRODUCT="CocoaLumberjackSwift"

OUTPUT_SUBDIR="CocoaLumberjackSwift-3.8.5-xcframework"
MANIFEST_NAME="CocoaLumberjackSwift-xcframework.json"
MANIFEST_KEYS=("3.8.5")

VERIFY_DEPENDENCIES=("CocoaLumberjack")

recipe_prepare_source() {
    force_dynamic_products "$1/Package.swift"
}
