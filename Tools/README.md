# Building distribution XCFrameworks

`Tools/` builds the binary dependencies this repository distributes from pinned
upstream sources, and verifies the results by running them on a simulator.

```bash
./Tools/build-xcframework.sh --all          # or: <product> [<product> ...]
./Tools/verify-xcframework.sh --all
./Tools/build-xcframework.sh --list
```

Products: `ASN1Swift`, `CocoaLumberjack`, `CocoaLumberjackSwift`, `Finch`,
`TPInAppReceipt`.

## Why XCFrameworks

A fat `.framework` cannot carry an arm64 iOS Simulator slice. arm64 device and
arm64 simulator are the same CPU type and cannot coexist in one Mach-O, so the
legacy archives in this repository top out at `armv7 + arm64 device + x86_64
simulator` — unusable on an Apple silicon Mac. An XCFramework separates slices
by platform, which is the only way to ship both.

No amount of repackaging fixes an existing archive: you cannot derive an arm64
simulator binary from an arm64 device binary. Each platform has to be compiled.

## What a build does

1. Clones the recipe's pinned commit and asserts that commit really is the named
   tag upstream (a tag can be moved; a commit cannot).
2. Applies the recipe's packaging changes — never implementation changes.
3. Archives iOS device and iOS Simulator separately, with Release configuration,
   `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, simulator architecture exclusions
   cleared, and an iOS 15 deployment target.
4. Completes each framework: Swift modules, resource bundles, privacy manifest,
   version stamp, and removal of the now-stale ad-hoc signature.
5. Assembles the XCFramework with dSYMs, writes the zip into
   `<Folder>/<Folder>-<version>-xcframework/`, and records provenance in
   `BUILD-RECORD.md` — source commit, toolchain, slices, archive SHA-256.
6. Adds the version keys to that product's `*-xcframework.json` manifest. The
   legacy `.json` feeds are never touched.

The toolchain is pinned to Xcode 27 via `DEVELOPER_DIR`, because this machine's
`xcode-select` still points at Xcode 26.4. Override the environment variable to
build with something else.

## What a verification does

Loading is not the same as working, so each product has a harness that asserts
real results — decoded receipt fields, captured log messages, decoded audio
frames — against values derived independently (OpenSSL, a separate DER reader,
or a synthesised fixture with known properties).

1. Every declared slice's Mach-O load commands are checked against the slice
   identifier, so a device binary sitting in a simulator slice fails loudly.
   An arm64 simulator slice must exist.
2. The device slice must link into an executable built for arm64 iOS.
3. The simulator slice must link into an executable built for arm64 iOS
   Simulator, which then runs on a booted simulator and exercises the API.

## Adding a product

A recipe is `Tools/recipes/<Name>.sh` — configuration and optional hooks, with
prose in `Tools/recipes/<Name>.notes.md` (it lands in the build record; keeping
it out of the shell file avoids quoting traps, and macOS bash 3.2 mis-parses a
here-document inside a command substitution).

```sh
REPO="https://github.com/owner/project.git"
VERSION="1.2.3"
TAG="1.2.3"
COMMIT="<full sha>"

OUTPUT_SUBDIR="Name-1.2.3-xcframework"
MANIFEST_NAME="Name-xcframework.json"
MANIFEST_KEYS=("1.2.3")

# Optional
KIND="spm"                              # or static-library
FOLDER="Name"                           # dependency folder; defaults to the recipe name
SCHEME="Name"                           # defaults to the recipe name
PRODUCT="Name"                          # framework/library name; defaults to the recipe name
DEPLOYMENT_TARGET="15.0"
DEVICE_ARCHS="arm64"
SIMULATOR_ARCHS="arm64 x86_64"
VERIFY_DEPENDENCIES=("Other")           # sibling products the harness links
EXTRA_FRAMEWORK_FILES=("PrivacyInfo.xcprivacy")
LINK_FRAMEWORKS=("OpenAL")              # Apple frameworks a consumer must link
SOURCE_FILES=(...) HEADER_FILES=(...)   # static-library kind

recipe_prepare_source() { ... }         # patch the checkout before building
recipe_prepare_harness() { ... }        # fetch fixtures for verification
```

Add a harness at `Tools/verification/<Name>.swift` or `<Name>.m`. Without one,
verification does the slice checks and stops.

Helpers available to `recipe_prepare_source`:

| Helper | Use |
| --- | --- |
| `force_dynamic_products <Package.swift>` | SwiftPM resolves an untyped library product as static; `xcodebuild archive` only installs a framework for a dynamic one |
| `pin_package_dependency <manifest> <url fragment> <version>` | Narrow a dependency to an exact version |
| `vendor_package_dependency <manifest> <url fragment> <path>` | Repoint a dependency at a local checkout, so its product type is ours to control |
| `fetch_source <dest> <repo> <commit> <tag>` | Clone a pinned revision, asserting commit-to-tag |

### Dependencies between products

Pinning a dependency's version is not enough when that dependency must stay a
separate framework. A resolved package keeps the product type its own manifest
declares, so a static upstream product is absorbed into the consumer's binary —
and then the application ships that implementation twice, once inside the
consumer and once as the framework this repository distributes separately.

`TPInAppReceipt` shows the shape of the fix: it vendors ASN1Swift at an exact
commit and forces the product dynamic, so the receipt binary links
`@rpath/ASN1Swift.framework/ASN1Swift`, exactly as the previously shipped binary
did. `otool -L` on the result is the check that matters.
