# Fixing the six dependencies missing native simulator support

Investigated 2026-09-14. This document covers only the six binary dependencies that currently prevent an `arm64` iOS Simulator build, their replacement paths, and the integration steps needed to use them. It is an implementation guide; the app dependencies and distribution repository have not been modified.

## Required result

**Preserve the exact versions below.** Obtain a compatible binary of that same version or rebuild that exact source revision, limiting changes to architecture, build configuration and packaging. Do not upgrade a library or Unity, resolve a newer transitive dependency, or replace Finch with another audio implementation. If an exact-version rebuild is blocked, record the blocker; a version change is outside this task.

Each binary dependency must provide separate **iOS device `arm64`** and **iOS Simulator `arm64`** variants. Package these as XCFrameworks. Simulator `x86_64` can remain alongside simulator `arm64` if older development workflows need it. Device `armv7` and simulator `i386` are unnecessary for this app's iOS 15 minimum. Preserve existing device payloads where compatible with the resulting package and Swift/module requirements; if rebuilding them is necessary, use the same pinned source and validate on a device.

| Current dependency | Exact source/engine version to retain | Current distribution pin | Current device slices | Current simulator slices | Fix |
| --- | --- | --- | --- | --- | --- |
| ASN1Swift.framework | **1.2.3** | `1.2.3-no-bitcode` | arm64, armv7 | x86_64 | Rebuild 1.2.3 as ASN1Swift.xcframework |
| CocoaLumberjack.framework | **3.8.5** | `3.8.5` | arm64 | x86_64 | Validate the existing 3.8.5 core XCFramework; otherwise rebuild 3.8.5 |
| CocoaLumberjackSwift.framework | **3.8.5** | `3.8.5` | arm64 | x86_64 | Rebuild the Swift wrapper from the same CocoaLumberjack 3.8.5 source |
| TPInAppReceipt.framework | **3.3.0** | `3.3.0-no-bitcode` | arm64, armv7 | x86_64 | Rebuild 3.3.0 with ASN1Swift fixed to 1.2.3 |
| UnityFramework.xcframework | **2022.3.62f3**, engine revision **96770f904ca7** (device binary evidence; see below) | Vendored; framework bundle version `1.0` | arm64 | x86_64 | Export arm64 simulator using that exact editor and the original game revision |
| libFinch.a | **1.0.3** | Vendored; matches distribution `1.0.3` | arm64, armv7 | i386, x86_64 | Rebuild Finch 1.0.3 as a static-library XCFramework |

Version evidence: [Tuist/Dependencies.swift](../Tuist/Dependencies.swift), [Cartfile.resolved](../Tuist/Dependencies/Lockfiles/Cartfile.resolved), and the installed Carthage frameworks' `CFBundleShortVersionString` agree for the four Carthage products. The `-no-bitcode` suffix belongs to the distribution key, not the upstream source tag. Finch's vendored archive matches the 1.0.3 distribution archive byte-for-byte. Unity's device binary embeds `2022.3.62f3 (96770f904ca7)`; its generic bundle version `1.0` is not its engine version. The Intel simulator binary did not expose a matching engine-version string in this inspection, so its engine version has not been independently confirmed.

An exact version number alone does not establish that an upstream tag includes every historical local patch. Recover and record original source commits, patches and build recipes where available. Finch header differences and the original Unity game revision need particular attention, as described below.

An `arm64` device binary cannot be turned into an `arm64` simulator binary by renaming it, editing its XCFramework manifest, or combining it with `lipo`. Compile for each platform, then use `xcodebuild -create-xcframework` to package the results. [Apple's architecture guidance](https://developer.apple.com/documentation/technotes/tn3117-resolving-build-errors-for-apple-silicon)

## What exists in the binary distribution repository

Repository: `/Users/ck/Dev/Git/Tayfun/Dependencies`.

The affected folders contain binary ZIPs, JSON version manifests and build scripts. No source checkouts, `Package.swift` files, or Xcode source projects were found there, including inside the inspected affected archives. Obtain the upstream source at exactly the versions listed above in a separate build checkout and record the resolved commits. Keep the existing model: build once, publish versioned binaries, and let app checkouts download those binaries.

| Location relative to Dependencies | Finding |
| --- | --- |
| `ASN1Swift/archive-xcframework-for-distribution.sh` | Archives a Swift package for device and simulator and assembles an XCFramework; needs explicit architecture/build configuration and packaging checks |
| `TPInAppReceipt/archive-xcframework-for-distribution.sh` | Also expects a Swift package checkout, despite the repository README describing an Xcode-project build |
| `CocoaLumberjackSwift/build-xcframeworks-for-distribution.sh` | Produces XCFramework containers but still forces simulator `x86_64`; also contains misspelled build settings |
| `CocoaLumberjack-merged/CocoaLumberjack-3.8.5/CocoaLumberjack.xcframework.zip` | Existing candidate: device arm64; simulator arm64 + x86_64. Actual simulator Mach-O metadata confirms the simulator platform |
| `Finch/Finch-1.0.3/Finch.zip` | Contains headers and `Finch/Library/libFinch.a`; that archive member is byte-for-byte identical to the app's vendored binary |

## 1. ASN1Swift and TPInAppReceipt

Handle these together because TPInAppReceipt depends on ASN1Swift.

### Source and build order

The app pins distribution versions `1.2.3-no-bitcode` and `3.3.0-no-bitcode`. Rebuild only the corresponding upstream source tags **ASN1Swift 1.2.3** and **TPInAppReceipt 3.3.0**, retaining any recovered original local patches. The original binaries' complete build provenance is not recorded in the inspected folders; capture that limitation in the artifact build record.

The upstream [TPInAppReceipt 3.3.0 package manifest](https://github.com/tikhop/TPInAppReceipt/blob/3.3.0/Package.swift) allows ASN1Swift versions from `1.0.0` up to the next major. Change that constraint to **exactly 1.2.3** in the distribution build checkout and record the resolved commit; do not let the receipt build resolve another ASN1Swift version. [ASN1Swift 1.2.3 package manifest](https://github.com/tikhop/ASN1Swift/blob/1.2.3/Package.swift)

1. Fetch tags **ASN1Swift 1.2.3** and **TPInAppReceipt 3.3.0**, record their exact commits and retain those versions throughout. If they cannot compile with the required toolchain without implementation changes, document the failure rather than substituting newer versions.
2. Adapt the existing `archive-xcframework-for-distribution.sh` scripts in disposable source checkouts. They rewrite `Package.swift` to create dynamic library products, so record that patch as part of the build recipe.
3. Set Release configuration, device `ARCHS=arm64`, simulator `ARCHS=arm64` (optionally `arm64 x86_64`), `ONLY_ACTIVE_ARCH=NO`, and clear architecture exclusions. Use `SKIP_INSTALL=NO`, `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, and an iOS deployment target compatible with the app's iOS 15 minimum.
4. Build ASN1Swift first, then TPInAppReceipt using that same ASN1Swift revision and a consistent linkage strategy. Inspect `otool -L` and exported symbols so ASN1Swift is supplied exactly once; do not accidentally embed it statically in the receipt binary while also distributing a duplicate dynamic implementation.
5. Preserve Swift modules, `.swiftinterface` files and TPInAppReceipt's certificate resource bundle. Its package processes `AppleIncRootCertificate.cer` and `StoreKitTestCertificate.cer`; verify the compiled bundle accessor locates them after framework embedding. Copying a resource folder without checking lookup behavior is insufficient.
6. Assemble `ASN1Swift.xcframework` and `TPInAppReceipt.xcframework`, each containing separate device/simulator variants. Package each into its own ZIP and expose the unchanged distribution keys through separate XCFramework manifests, as specified below.

### App integration

In [Dependencies+Carthage.swift](../Tuist/ProjectDescriptionHelpers/Dependencies+Carthage.swift), change the artifact filenames to `ASN1Swift.xcframework` and `TPInAppReceipt.xcframework`. The existing helper already routes `.xcframework` names to `Tuist/Dependencies/Carthage/Build/`; `.framework` names currently go through its `Build/iOS/` branch.

Change the manifest URLs in [Tuist/Dependencies.swift](../Tuist/Dependencies.swift), retaining exact pins **`1.2.3-no-bitcode`** and **`3.3.0-no-bitcode`**. Preserve the `TPInAppReceipt → ASN1Swift` dependency relationship and the module names, keeping application imports stable.

Validate receipt parsing and certificate/resource loading with a known receipt fixture or StoreKit test, plus the existing physical-device receipt flow. An empty or unavailable simulator app receipt is not proof that packaging works.

## 2. CocoaLumberjack and CocoaLumberjackSwift

Both must remain at **3.8.5**, built from the same upstream CocoaLumberjack tag. These remain two modules. The application imports both, and the Swift logging functions are used throughout the project.

### Existing core candidate

`CocoaLumberjack-merged/CocoaLumberjack-3.8.5/CocoaLumberjack.xcframework.zip` already contains:

- `ios-arm64`: arm64 device binary.
- `ios-arm64_x86_64-simulator`: arm64 + x86_64 simulator binary.

The binary slices were verified with `lipo`; the arm64 simulator load command identifies platform 7 (iOS Simulator). The archive contains only the **CocoaLumberjack** module and no separate **CocoaLumberjackSwift** module. Its folder name “merged” does not make it a replacement for both dependencies.

The existing manifest is `CocoaLumberjack-merged/CocoaLumberjack.json`, version `3.8.5`. The app currently uses `CocoaLumberjack/CocoaLumberjack.json`, whose `3.8.5` entry points to the incompatible legacy fat framework.

### Steps

1. Use the existing core XCFramework as a candidate, or rebuild core and Swift wrapper together from [CocoaLumberjack 3.8.5](https://github.com/CocoaLumberjack/CocoaLumberjack/tree/3.8.5) for consistent provenance. Verify the candidate's linkage, resources and integration before selecting it as the final artifact.
2. Update `CocoaLumberjackSwift/build-xcframeworks-for-distribution.sh`:
   - Replace simulator `ARCHS="x86_64"` with `arm64`, optionally also retaining `x86_64`.
   - Replace device `ARCHS="arm64 armv7"` with `arm64`.
   - Correct `ONLY_ACTIVE_ARCHS` to **`ONLY_ACTIVE_ARCH`**.
   - Correct `BUILD_LIBRARIES_FOR_DISTRIBUTION` to **`BUILD_LIBRARY_FOR_DISTRIBUTION`**.
   - Clear inherited simulator architecture exclusions and select Xcode 27 explicitly.
   - Collect both intended framework products explicitly rather than assuming everything copied from a products directory is required.
3. Produce `CocoaLumberjack.xcframework` and `CocoaLumberjackSwift.xcframework`. Preserve Swift wrapper interfaces and privacy/resources. If using the package-based build path instead of `Lumberjack.xcodeproj`, account for its `CocoaLumberjackSwiftSupport` target; do not omit its implementation. The upstream [3.8.5 package manifest](https://github.com/CocoaLumberjack/CocoaLumberjack/blob/3.8.5/Package.swift) shows this dependency.
4. Publish rebuilt ZIPs at new immutable artifact URLs under separate XCFramework manifests with the unchanged **3.8.5** key. If reusing the existing core candidate, point the app's core download at the existing `CocoaLumberjack-merged/CocoaLumberjack.json` entry rather than changing what the old manifest's version means.
5. Change both artifact filenames in `Dependencies+Carthage.swift` to `.xcframework`, update the manifest URLs in `Tuist/Dependencies.swift`, retain both exact **3.8.5** pins, and retain `CocoaLumberjackSwift → CocoaLumberjack`.
6. Verify Swift and Objective-C logging on a simulator and device, and build the extensions that consume the logging frameworks. Check embedding for a single copy of the core implementation.

## 3. UnityFramework

The current device framework identifies **Unity 2022.3.62f3, revision 96770f904ca7**. This requires a new export/build from the original Unity project using that exact editor revision. Repackaging the existing Intel simulator binary cannot supply the missing architecture.

The Unity project was not available in the inspected repositories. Before rebuilding, recover its original game/source revision and verify `ProjectSettings/ProjectVersion.txt` matches `2022.3.62f3` / `96770f904ca7`. Preserve its package lockfile, native plug-in versions, assets and export patches. The engine string does not identify the game commit, and matching the framework's bundle version `1.0` is insufficient. If the original editor or game revision cannot be recovered, record that as a reproducibility blocker.

1. Install/use **Unity 2022.3.62f3 (96770f904ca7)** and its matching iOS build-support module. Do not upgrade Unity or project packages. Confirm the required simulator export works with this exact installation; a failure is a blocker to investigate within this version constraint.
2. Export the original game content for **Simulator SDK / ARM64**; if a device rebuild is required, export **Device SDK / ARM64** from the same pinned project/editor. The Unity 2022.3 manual documents the separate Simulator Architecture setting, including ARM64. This documents the release-line capability, not a successful export test of this project's exact editor patch. Native plug-ins need simulator builds of their existing versions too. [Unity 2022.3 iOS Player Settings](https://docs.unity3d.com/2022.3/Documentation/Manual/class-PlayerSettingsiOS.html)
3. Build the exported `UnityFramework` target separately for device and simulator, preserving native bridge headers, module maps, matching Unity data/resources and symbols.
4. Combine those framework outputs with `xcodebuild -create-xcframework`. Replace [UnityFramework.xcframework](../Features/UnityCore/Frameworks/UnityFramework.xcframework) as a complete matched artifact. Its Tuist dependency already uses `.xcframework`, so its format does not need changing.
5. Validate game rendering/input, native callbacks, audio, and background/foreground behavior on both platforms. Audit the existing Unity header search paths against the new export's actual structure.

## 4. Finch 1.0.3: rebuild the existing library

### What is available

The public upstream is [zoul/Finch](https://github.com/zoul/Finch), an Objective-C OpenAL sound-effects library. It is archived, and its [GitHub Releases page](https://github.com/zoul/Finch/releases) has no published releases. The inspected source is version **1.0.3**, commit `6f40fe8c61e5322eff540b488f449ec105fc42ae`. No ready-made, maintained arm64-simulator Finch binary replacement was verified in this research.

The source is available under MIT, so we can build a replacement binary from it and distribute it through the existing pinned-binary repository, while preserving its license. The [upstream podspec](https://github.com/zoul/Finch/blob/6f40fe8c61e5322eff540b488f449ec105fc42ae/Finch.podspec) identifies the production sources, ARC requirement and Apple audio framework dependencies. This does not require adding CocoaPods to the app.

**Feasibility was tested:** all nine non-test Objective-C implementation files compiled with ARC/modules and SDK 27 for `arm64-apple-ios15.0` and `arm64-apple-ios15.0-simulator`. Each produced a static archive; a force-loaded link of all objects against the required Apple frameworks also succeeded. Mach-O metadata identified device platform 2 and simulator platform 7. These were isolated probes in `/tmp`, not installed replacements or audio playback tests. OpenAL deprecation warnings remain.

### Exact-version rebuild steps

1. Pin **Finch 1.0.3**, upstream commit **`6f40fe8c61e5322eff540b488f449ec105fc42ae`**, and recover any original local patches before finalizing the source baseline. Build the nine production `.m` files with ARC/modules, excluding test sources. The 2018 Xcode project contains obsolete settings, so modernize its library target or create a small distribution target using the podspec's production-file selection. Keep the Finch implementation at this version.
2. Produce separate static `libFinch.a` files for arm64 device and arm64 simulator, optionally a universal arm64/x86_64 simulator archive. Link dependencies include OpenAL, AudioToolbox and AVFoundation; preserve Foundation/module requirements as well.
3. Package them into `Finch.xcframework` using `xcodebuild -create-xcframework -library … -headers …` for each platform. Keep a static-library payload so Finch continues to be linked into `Games` rather than acquiring a new dynamic-framework resource bundle location.
4. Publish `Finch.xcframework.zip` through a separate proposed `Finch/Finch-xcframework.json` manifest with exact key **1.0.3**. Add an exact **1.0.3** Finch binary dependency to `Tuist/Dependencies.swift`; the app currently vendors Finch directly. Alternatively retain vendoring and store the same-version XCFramework in the app repository; either route must use the identical pinned source baseline.
5. Change [Dependencies+File.swift](../Tuist/ProjectDescriptionHelpers/Dependencies+File.swift) from the raw `.library(...libFinch.a...)` reference to the downloaded XCFramework, or introduce a Carthage Finch helper and update `Features/Project.swift`. Declare Finch's Apple framework requirements in that dependency (adding OpenAL/AudioToolbox SDK helpers if needed); this project disables module autolinking in `Config/Common.xcconfig`. Preserve one Finch link entry, then remove the obsolete vendored archive.
6. Resolve the existing header/source mismatch before replacing the binary. Local `FISound.h` declares `gain`/`pitch` as **CGFloat**, whereas upstream 1.0.3 declares **float**; local initializers and `sharedEngine` declarations also differ. The matched distribution binary establishes the 1.0.3 artifact version, but not which header edits were accompanied by implementation patches. Recover those patches or establish the actual existing ABI; do not assume unmodified upstream source and the local headers are interchangeable. Record unresolved differences as blockers to an architecture-only replacement. Use headers matching the verified implementation, update the Finch header glob/search paths, and confirm existing `FISoundEngine.h` imports resolve.
7. Preserve the actual application behavior described below and test audio playback before replacing the shipped binary.

### Application behavior to preserve

The direct integration is concentrated in:

- [EGSound.m](../Features/Games/Sources/ObjC/project/CommonClasses/EGSound.m): singleton sound engine, preloaded WAV effects, one-voice and four-voice polyphony, sound-disabled preference, suspend/resume, and ambient audio-session setup.
- [WPEmojiImageView.m](../Features/Games/Sources/ObjC/project/EmojiWords/HelperClasses/WPEmojiImageView.m) and [ETEmojiImageView.m](../Features/Games/Sources/ObjC/project/EmojifyThis/HelperClasses/ETEmojiImageView.m): retained sound objects and playback delayed to match animations.
- `Features/Games/Resources/CommonResources/Sounds/`: bundled effects. Verify `soundBundle` still resolves these and other game WAV assets; upstream Finch derives its initial bundle from its class location.

Test rapid retriggering with one voice, four overlapping voices, mute preference semantics (the stored flag is “sound disabled”), animation timing, external audio mixing/silent-switch behavior, and suspend/resume after backgrounding or interruption.

## Distribution and app integration sequence

1. Prepare and validate each replacement in the distribution/build environment. Set `DEVELOPER_DIR=/Applications/Xcode27RC.app/Contents/Developer` explicitly; this machine's global `xcode-select` still points to Xcode 26.4.
2. Preserve every existing archive URL and manifest entry. Put the rebuilt `.xcframework.zip` at a new path and use a separate XCFramework manifest with the **same exact version key**, following the proposed mapping below. Record source tag and resolved commit, recovered local patches, packaging patches, toolchain, slice list and archive SHA-256. A different artifact URL identifies the packaging change; it does not require a library version upgrade.
3. Publish the new artifacts/manifests before changing app manifest URLs. This document does not publish or push anything. Keep normal app dependency checkout as binary downloads; upstream source checkouts are needed only for producing the distribution artifacts.
4. Update Tuist artifact filenames and manifest URLs, retaining every existing exact version pin; add Finch at exact **1.0.3** if choosing binary distribution. Preserve the two existing wrapper/core dependency relationships. Integrate the Unity export from **2022.3.62f3 (96770f904ca7)** and the **Finch 1.0.3** rebuild.
5. Fetch using `.tuist-bin/tuist dependencies fetch` directly and check its exit status. The current `Scripts/Tuist/prepare.sh` pipes fetch output through a command ending in `|| true`, so its “Done bootstrapping” message does not establish a successful download. Verify the new files and updated lockfile, then regenerate with `Scripts/Tuist/generate.sh --dont-open`.
6. Once all six replacements are ready, remove `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` from [Config/Common.xcconfig](../Config/Common.xcconfig). Leave standard architectures enabled. Build from fresh DerivedData to avoid mistaking cached Intel products for the new build.
7. Build and run `App` on an arm64 iOS 27 simulator. Also build the extensions and a device/archive configuration to check embedding, symbols, resources and device support. Run the dependency-specific receipt, logging, Unity and sound checks above.

### Manifest mapping that preserves exact version keys

Paths are relative to `/Users/ck/Dev/Git/Tayfun/Dependencies`. Except for the existing core candidate, the XCFramework feeds below are **proposed new files**, not artifacts already available to download. Keep the old feeds unchanged. New ZIP filenames or build-specific subdirectories must avoid overwriting existing artifact URLs.

| Product | XCFramework manifest | Exact key | Source version |
| --- | --- | --- | --- |
| ASN1Swift | `ASN1Swift/ASN1Swift-xcframework.json` | `1.2.3-no-bitcode` | `1.2.3` |
| TPInAppReceipt | `TPInAppReceipt/TPInAppReceipt-xcframework.json` | `3.3.0-no-bitcode` | `3.3.0`, with ASN1Swift `1.2.3` |
| CocoaLumberjack | Existing `CocoaLumberjack-merged/CocoaLumberjack.json` if validated; otherwise new `CocoaLumberjack/CocoaLumberjack-xcframework.json` | `3.8.5` | `3.8.5` |
| CocoaLumberjackSwift | `CocoaLumberjackSwift/CocoaLumberjack-xcframework.json` | `3.8.5` | `3.8.5` |
| Finch, if distributed through Carthage | `Finch/Finch-xcframework.json` | `1.0.3` | `1.0.3`, commit `6f40fe8c61e5322eff540b488f449ec105fc42ae`, plus any verified original patches |

Unity remains vendored and has no Carthage manifest. Record editor **2022.3.62f3 (96770f904ca7)**, the recovered game commit, package/plugin revisions, export settings and artifact checksum alongside its build recipe.

## Acceptance criteria

- All six dependencies retain the exact source/engine versions listed above. Carthage version keys remain unchanged for the existing four products; Finch is exactly 1.0.3. Record resolved source commits and verify that dependency resolution introduced no newer implementation versions.
- Original Unity game/source provenance and Finch header/implementation differences are resolved before claiming the replacements preserve the existing implementations. Unresolved provenance or exact-version build failures are explicit blockers, not reasons to silently upgrade.

- All retained replacement XCFrameworks declare iOS device arm64 and iOS Simulator arm64 variants; `lipo` confirms the declared architectures and Mach-O load commands confirm the platform distinction.
- Swift products contain usable interfaces/modules; resource and certificate bundles load from their final installed locations.
- Dependency fetching from the published version pins succeeds in a clean dependency checkout without building upstream source during normal app setup.
- No stale `.framework`/`libFinch.a` link references or duplicate dependency implementations remain after generation.
- Native simulator builds succeed with the arm64 exclusion removed, device builds still succeed, and the affected functionality passes runtime checks.
- The Finch source probe establishes compile/link feasibility only. The final Finch package, the other rebuilt products, the Unity export and complete application runtime validation remain implementation work.
