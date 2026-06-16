# Dependencies

Prebuilt iOS frameworks and xcframeworks for use in Unity and other projects. Each dependency lives in its own top-level folder and exposes a version manifest as JSON.

Consumers resolve a version from the manifest and download the matching archive from GitHub.

## Repository layout

```
Dependencies/
├── Purchases/                  # RevenueCat SDK
│   ├── Purchases.json          # version → download URL
│   ├── Purchases-5.78.0/
│   │   └── RevenueCat.xcframework.zip
│   └── optimize-xcframework.sh
├── PurchasesUI/                # RevenueCat Paywall UI
│   ├── PurchasesUI.json
│   ├── PurchasesUI-5.78.0/
│   │   └── RevenueCatUI.xcframework.zip
│   └── optimize-xcframework.sh
├── OneSignal/
│   ├── OneSignal.json
│   └── OneSignal-3.12.9/
│       └── OneSignal.xcframework.zip
└── ...
```

Conventions:

- **Folder name:** `{DependencyName}-{version}` (for example `Purchases-5.78.0`)
- **Manifest:** `{DependencyName}.json` maps version strings to raw GitHub URLs
- **Archive:** one zip per version folder — only the zip should be committed, not extracted framework contents

URL format used in manifests:

```
https://github.com/23taps/Dependencies/raw/master/{Folder}/{VersionFolder}/{ArchiveName}.zip
```

## Adding a new framework version

### 1. Download or build the binary

Obtain the framework or xcframework archive from the upstream vendor (or build it locally — see [Building from source](#building-from-source) below).

### 2. Create the version folder

Inside the dependency folder, create a subfolder named after the version:

```bash
mkdir Purchases/Purchases-5.79.0
```

Place the archive in that folder using the existing naming convention for that dependency (for example `RevenueCat.xcframework.zip`, `OneSignal.xcframework.zip`, `Finch.zip`).

### 3. Run any required post-processing

Some dependencies need an extra step before committing. See [Required extra steps](#required-extra-steps) below.

### 4. Update the version manifest

Add a new entry to the dependency's JSON file. The optimize scripts for RevenueCat do this automatically; for other dependencies, add it by hand:

```json
{
    "5.78.0": "https://github.com/23taps/Dependencies/raw/master/Purchases/Purchases-5.78.0/RevenueCat.xcframework.zip",
    "5.79.0": "https://github.com/23taps/Dependencies/raw/master/Purchases/Purchases-5.79.0/RevenueCat.xcframework.zip"
}
```

Keep version keys sorted semantically.

### 5. Commit and push

Commit the version folder (zip only), the updated JSON, and push to `master`. The raw URLs in the manifest only work once the files are on the default branch.

**Do not commit** extracted `.framework` / `.xcframework` directories, `_original.zip` backups, or `__MACOSX` folders left behind by extraction.

---

## Required extra steps

### RevenueCat (`Purchases`) and RevenueCat UI (`PurchasesUI`)

Upstream RevenueCat releases ship xcframeworks with slices for macOS, tvOS, watchOS, visionOS, and Mac Catalyst. This repository only keeps the iOS device and simulator slices to reduce download size.

**Always run the optimize script after adding a new zip.** Do not commit the unoptimized archive.

```bash
# RevenueCat SDK
cd Purchases
./optimize-xcframework.sh 5.79.0

# RevenueCat Paywall UI
cd PurchasesUI
./optimize-xcframework.sh 5.79.0
```

The script will:

1. Extract the xcframework
2. Remove all platform slices except `ios-arm64` and `ios-arm64_x86_64-simulator`
3. Update `Info.plist` and re-sign the xcframework
4. Replace the zip with the optimized version
5. Add the version to `Purchases.json` / `PurchasesUI.json` if it is not already present

**Checklist for RevenueCat versions:**

- [ ] Zip is inside `Purchases-{version}/` or `PurchasesUI-{version}/`
- [ ] `optimize-xcframework.sh` was run with the correct version argument
- [ ] Only `RevenueCat.xcframework.zip` / `RevenueCatUI.xcframework.zip` remains in the version folder
- [ ] No leftover extracted `RevenueCat.xcframework` directory (the Purchases script may leave one behind when the xcframework extracts to the version folder root — delete it before committing)

If a version was added without optimization, re-run the script on the existing folder:

```bash
cd Purchases && ./optimize-xcframework.sh 5.77.0
cd PurchasesUI && ./optimize-xcframework.sh 5.77.0
```

### Other dependencies

Most other folders only need the zip placed in a version folder and a JSON entry added. No extra scripts are required.

| Dependency | Manifest | Notes |
|------------|----------|-------|
| OneSignal | `OneSignal/*.json` | Multiple products (Core, Extension, Notifications, …), each with its own manifest |
| AWS (Core, Cognito, S3) | `AWSCore/*.json`, etc. | Framework zips |
| Finch, Nimble, APNGKit | `{Name}/{Name}.json` | Single-product zips |
| ASN1Swift, TPInAppReceipt | `{Name}/{Name}.json` | Can be built from source (see below) |
| CocoaLumberjack | `CocoaLumberjack/*.json` | Several distribution variants in subfolders |

---

## Building from source

Some dependencies include scripts for archiving frameworks locally instead of downloading vendor binaries:

| Folder | Script | Purpose |
|--------|--------|---------|
| `ASN1Swift/` | `archive-framework-for-distribution.sh`, `archive-xcframework-for-distribution.sh` | Build from Swift package |
| `TPInAppReceipt/` | `archive-framework-for-distribution.sh`, `archive-xcframework-for-distribution.sh` | Build from Xcode project |
| `CocoaLumberjackSwift/` | `build-framework-for-distribution.sh`, `build-xcframeworks-for-distribution.sh` | Build Lumberjack xcframeworks |

After building, move the output zip into a new version folder and update the manifest as described above.

---

## Quick reference: add RevenueCat 5.79.0

```bash
# 1. Place the downloaded zip
mkdir -p Purchases/Purchases-5.79.0 PurchasesUI/PurchasesUI-5.79.0
mv ~/Downloads/RevenueCat.xcframework.zip Purchases/Purchases-5.79.0/
mv ~/Downloads/RevenueCatUI.xcframework.zip PurchasesUI/PurchasesUI-5.79.0/

# 2. Optimize (required)
cd Purchases && ./optimize-xcframework.sh 5.79.0
cd ../PurchasesUI && ./optimize-xcframework.sh 5.79.0

# 3. Verify only zips remain, then commit
```
