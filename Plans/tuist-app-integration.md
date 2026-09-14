# Integrating the rebuilt XCFrameworks into the EmojiRelaunch Tuist project

Five binary dependencies have been rebuilt as XCFrameworks with native arm64 iOS
Simulator slices: **ASN1Swift 1.2.3**, **TPInAppReceipt 3.3.0**,
**CocoaLumberjack 3.8.5**, **CocoaLumberjackSwift 3.8.5** and **Finch 1.0.3**.
Every version is unchanged; only architecture, build configuration and packaging
differ. This document is the app-side change list.

UnityFramework is **not** covered here — it still has no arm64 simulator slice,
so the simulator build stays blocked until it is re-exported. Everything below
can be done first; step 6 is the only part that must wait for Unity.

Paths are relative to the app repository root (`~/Dev/Git/Tayfun/EmojiRelaunch`).
The binaries live in the distribution repository
(`~/Dev/Git/Tayfun/Dependencies`), built by `Tools/build-xcframework.sh` there.

---

## 0. Prerequisite: publish the artifacts

**The manifest URLs below return 404 until the distribution repository is
committed and pushed to `master`.** Carthage resolves them over HTTPS from
GitHub; nothing resolves from a local checkout. Do this first, in
`~/Dev/Git/Tayfun/Dependencies`:

```
ASN1Swift/ASN1Swift-1.2.3-xcframework/            (zip + BUILD-RECORD.md)
ASN1Swift/ASN1Swift-xcframework.json
ASN1Swift/PrivacyInfo.xcprivacy
TPInAppReceipt/TPInAppReceipt-3.3.0-xcframework/
TPInAppReceipt/TPInAppReceipt-xcframework.json
TPInAppReceipt/PrivacyInfo.xcprivacy
CocoaLumberjack/CocoaLumberjack-3.8.5-xcframework/
CocoaLumberjack/CocoaLumberjack-xcframework.json
CocoaLumberjackSwift/CocoaLumberjackSwift-3.8.5-xcframework/
CocoaLumberjackSwift/CocoaLumberjackSwift-xcframework.json
Finch/Finch-1.0.3-xcframework/
Finch/Finch-xcframework.json
Tools/                                            (the build tooling)
README.md                                         (modified)
```

The zips are tracked by Git LFS (`.gitattributes` maps `*.zip`). Confirm they
were uploaded as LFS objects and not committed as plain blobs, or the raw URLs
will serve pointer files and Carthage will fail on a corrupt archive.

After pushing, spot-check one URL before touching the app:

```bash
curl -sI https://github.com/23taps/Dependencies/raw/master/ASN1Swift/ASN1Swift-1.2.3-xcframework/ASN1Swift.xcframework.zip | head -1
```

## 1. What changes

| Product | Manifest (new) | Version key | Artifact filename |
| --- | --- | --- | --- |
| ASN1Swift | `ASN1Swift/ASN1Swift-xcframework.json` | `1.2.3-no-bitcode` *(unchanged)* | `ASN1Swift.xcframework` |
| TPInAppReceipt | `TPInAppReceipt/TPInAppReceipt-xcframework.json` | `3.3.0-no-bitcode` *(unchanged)* | `TPInAppReceipt.xcframework` |
| CocoaLumberjack | `CocoaLumberjack/CocoaLumberjack-xcframework.json` | `3.8.5` *(unchanged)* | `CocoaLumberjack.xcframework` |
| CocoaLumberjackSwift | `CocoaLumberjackSwift/CocoaLumberjackSwift-xcframework.json` | `3.8.5` *(unchanged)* | `CocoaLumberjackSwift.xcframework` |
| Finch | `Finch/Finch-xcframework.json` | `1.0.3` *(new dependency)* | `Finch.xcframework` |

Every version pin stays exactly as it is. What changes is the *feed* each pin is
read from and the *filename* Tuist links. The legacy `*.json` feeds and their
fat-framework artifacts are untouched, so a rollback is a one-line revert.

Why a different feed rather than a new version: a fat `.framework` cannot carry
an arm64 simulator slice at all. arm64 device and arm64 simulator are the same
CPU type and cannot coexist in one Mach-O, which is why the current binaries top
out at `armv7 + arm64 device + x86_64 simulator`. XCFramework is the mechanism
that separates slices by platform. The library versions never needed to change.

## 2. `Tuist/Dependencies.swift`

Change the four existing manifest URLs and add Finch. Version requirements are
untouched.

```diff
         .binary(
             path:
-                "https://raw.githubusercontent.com/23taps/Dependencies/master/CocoaLumberjack/CocoaLumberjack.json",
+                "https://raw.githubusercontent.com/23taps/Dependencies/master/CocoaLumberjack/CocoaLumberjack-xcframework.json",
             requirement: .exact("3.8.5")),
         .binary(
             path:
-                "https://raw.githubusercontent.com/23taps/Dependencies/master/CocoaLumberjackSwift/CocoaLumberjack.json",
+                "https://raw.githubusercontent.com/23taps/Dependencies/master/CocoaLumberjackSwift/CocoaLumberjackSwift-xcframework.json",
             requirement: .exact("3.8.5")),
```

```diff
         .binary(
             path:
-                "https://raw.githubusercontent.com/23taps/Dependencies/master/ASN1Swift/ASN1Swift.json",
+                "https://raw.githubusercontent.com/23taps/Dependencies/master/ASN1Swift/ASN1Swift-xcframework.json",
             requirement: .exact("1.2.3-no-bitcode")),
         .binary(
             path:
-                "https://raw.githubusercontent.com/23taps/Dependencies/master/TPInAppReceipt/TPInAppReceipt.json",
+                "https://raw.githubusercontent.com/23taps/Dependencies/master/TPInAppReceipt/TPInAppReceipt-xcframework.json",
             requirement: .exact("3.3.0-no-bitcode")),
+        .binary(
+            path:
+                "https://raw.githubusercontent.com/23taps/Dependencies/master/Finch/Finch-xcframework.json",
+            requirement: .exact("1.0.3")),
```

Note the CocoaLumberjackSwift filename also changes: the old feed was
`CocoaLumberjackSwift/CocoaLumberjack.json` (the folder and the file disagreed),
the new one is `CocoaLumberjackSwift/CocoaLumberjackSwift-xcframework.json`.

## 3. `Tuist/ProjectDescriptionHelpers/Dependencies+Carthage.swift`

Four filenames move from `.framework` to `.xcframework`, and Finch gains a
helper. No change to the private `carthage(filename:)` function — it already
routes `.xcframework` names to `Tuist/Dependencies/Carthage/Build/` and
`.framework` names to `Build/iOS/`, which is exactly the distinction that
changes here.

```diff
         public static var CocoaLumberjack: Dependency {
             return Dependency(
-                targetDependency: carthage(filename: "CocoaLumberjack.framework")
+                targetDependency: carthage(filename: "CocoaLumberjack.xcframework")
             )
         }

         public static var CocoaLumberjackSwift: Dependency {
             return Dependency(
-                targetDependency: carthage(filename: "CocoaLumberjackSwift.framework"),
+                targetDependency: carthage(filename: "CocoaLumberjackSwift.xcframework"),
                 dependencies: [
                     CocoaLumberjack
                 ]
             )
         }
```

```diff
         public static var ASN1Swift: Dependency {
             return Dependency(
-                targetDependency: carthage(filename: "ASN1Swift.framework")
+                targetDependency: carthage(filename: "ASN1Swift.xcframework")
             )
         }

         public static var TPInAppReceipt: Dependency {
             return Dependency(
-                targetDependency: carthage(filename: "TPInAppReceipt.framework"),
+                targetDependency: carthage(filename: "TPInAppReceipt.xcframework"),
                 dependencies: [ASN1Swift]
             )
         }
+
+        /// Static-library XCFramework: linked into Games, never embedded.
+        public static var Finch: Dependency {
+            return Dependency(
+                targetDependency: carthage(filename: "Finch.xcframework")
+            )
+        }
```

Keep both existing relationships — `CocoaLumberjackSwift → CocoaLumberjack` and
`TPInAppReceipt → ASN1Swift`. They are not decorative: each wrapper links its
core dynamically and the app must embed exactly one copy of each core.

## 4. Finch: replace the vendored static library

Finch is the only dependency that is not currently a Carthage binary — it is
vendored at `Features/Games/Libraries/Finch/`. Four edits.

**4.1 — `Features/Project.swift`, Games target dependencies (~line 312):**

```diff
-            Dependency.File.Finch,
+            Dependency.Carthage.Finch,
```

**4.2 — `Features/Project.swift`, `additionalFiles` (~line 42):** delete the
header glob, which becomes a dangling project reference once the folder is gone.

```diff
-        .glob(pattern: "\(WorkspaceConstants.targetGames)/Libraries/Finch/*.h"),
```

**4.3 — `Tuist/ProjectDescriptionHelpers/Dependencies+File.swift`:** `Finch` is
the only member of `Dependency.File`, so the whole file can go once nothing
references it. Confirm with `grep -rn "Dependency.File" .` before deleting.

**4.4 — delete `Features/Games/Libraries/Finch/`** (`libFinch.a`, `FISound.h`,
`FISoundEngine.h`, `Finch.h`) once the build is green.

### What you do *not* need to add

You do **not** need OpenAL/AudioToolbox SDK dependencies, despite
`CLANG_MODULES_AUTOLINK = NO` in `Config/Common.xcconfig`. That setting controls
whether the compiler emits auto-link hints when compiling *this project's*
sources; it does not strip hints already baked into a prebuilt archive. Both the
old and new `libFinch.a` carry `LC_LINKER_OPTION` load commands, and the new
build's set is a superset of the old one's:

| | vendored `libFinch.a` | rebuilt `libFinch.a` |
| --- | --- | --- |
| auto-linked frameworks | AudioToolbox, CFNetwork, CoreFoundation, CoreMIDI, Foundation, OpenAL, Security | the same, plus CoreAudioTypes |

That is why the app links OpenAL today without ever naming it, and why it will
keep doing so. Verified with `otool -l -arch arm64 <lib> | grep LC_LINKER_OPTION`.

### Headers

The vendored folder exposed 3 hand-trimmed headers via `publicHeaders:`. The
XCFramework ships all 9 upstream headers per slice, and Xcode adds the selected
slice's `Headers` directory to the header search path automatically. `EGSound.h`
imports `"FISoundEngine.h"`, which resolves from there.

The known header discrepancy is **inert for this app**: local `FISound.h`
declares `gain`/`pitch` as `CGFloat` where upstream 1.0.3 declares `float`, but
nothing in `Features/Games/Sources/ObjC/` reads or writes either property
(`grep -rn "\.gain\|\.pitch"` is empty). The API the app actually uses is
`+[FISoundEngine sharedEngine]`, `-soundNamed:maxPolyphony:error:`,
`-soundNamed:error:`, `-[FISound play]` and `FISoundEngine.suspended` — all
present with matching selectors and ABI. The remaining differences
(`instancetype` vs `id` return types) are source-level only.

Still confirm audio actually works on device before deleting the old archive;
the rebuilt library was runtime-tested (decode, playback, polyphony,
suspend/resume) but on a simulator only.

### One thing to verify: Tuist 1.51 and static XCFrameworks

`Finch.xcframework` has a **static** payload — `libFinch.a` plus headers, not a
`.framework`. Finch must stay statically linked into Games so it does not
acquire a dynamic framework's separate bundle location; it derives its default
sound bundle from its own class location.

This project pins Tuist **1.51.0**, whose `TargetDependency.xcframework(path:)`
has no linking/embedding parameter — Tuist infers it from the binary. After
generating, check that Finch is **linked but not embedded**:

```bash
# Finch should appear in "Link Binary With Libraries", NOT in an embed phase,
# and the built app should contain no Finch.framework.
grep -r "Finch" Features/*.xcodeproj/project.pbxproj | grep -i embed
```

If Tuist 1.51 mishandles it, the fallback is to keep Finch vendored as two raw
archives selected by SDK, with no Tuist dependency entry:

```
Features/Games/Libraries/Finch/
├── include/            # headers from the xcframework
├── ios/libFinch.a
└── ios-simulator/libFinch.a
```

```
LIBRARY_SEARCH_PATHS[sdk=iphoneos*]        = $(SRCROOT)/Games/Libraries/Finch/ios
LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*] = $(SRCROOT)/Games/Libraries/Finch/ios-simulator
OTHER_LDFLAGS = $(inherited) -lFinch
```

Both `.a` files are already inside `Finch.xcframework.zip`; extracting them is
the whole job. A single fat `.a` is not an option — `lipo` refuses two arm64
slices, and a mixed thin archive is rejected by the linker.

## 5. `Config/Common.xcconfig`

Remove the exclusion at line 155:

```diff
-EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64
```

Leave `ARCHS = $(ARCHS_STANDARD)` at line 11 alone.

**Do this last.** Until UnityFramework has an arm64 simulator slice, removing
the exclusion will break the simulator build on Unity, not on anything in this
document. If you want to validate the five rebuilt dependencies before Unity is
ready, keep the exclusion and build for device plus an Intel simulator; the
arm64 slices are verified independently (see §8).

## 6. Fetch and regenerate

```bash
cd ~/Dev/Git/Tayfun/EmojiRelaunch
.tuist-bin/tuist dependencies fetch   # check the exit status
echo "exit: $?"
```

Run `tuist dependencies fetch` **directly**, not via `Scripts/Tuist/prepare.sh`:
that script pipes fetch through `grep ... || true`, so its "Done bootstrapping"
message is printed even when the download failed.

Then confirm the artifacts actually landed and the lockfile updated:

```bash
ls -d Tuist/Dependencies/Carthage/Build/{ASN1Swift,TPInAppReceipt,CocoaLumberjack,CocoaLumberjackSwift,Finch}.xcframework
grep -iE "ASN1|TPInApp|Lumberjack|Finch" Tuist/Dependencies/Lockfiles/Cartfile.resolved
```

The five `.framework` bundles under `Tuist/Dependencies/Carthage/Build/iOS/`
become stale — Carthage will not remove them. Delete
`Tuist/Dependencies/Carthage` entirely and re-fetch if you want certainty that
nothing links the old copies.

```bash
Scripts/Tuist/generate.sh --dont-open
```

## 7. Validation

Build from **fresh DerivedData**, or cached Intel products will be mistaken for
the new build.

- [ ] `App` builds and runs on an arm64 iOS 26+ simulator *(needs Unity; see §5)*
- [ ] `App` builds for device and archives
- [ ] All app extensions build (they consume the logging frameworks)
- [ ] No duplicate-symbol or "missing module" errors
- [ ] Exactly one copy of each framework in the built `.app`:
      `ls App.app/Frameworks/` shows `ASN1Swift.framework`,
      `TPInAppReceipt.framework`, `CocoaLumberjack.framework`,
      `CocoaLumberjackSwift.framework` — and **no** `Finch.framework`
- [ ] Objective-C and Swift logging both produce output, on simulator and device
- [ ] Receipt parsing works against a real device receipt
- [ ] Game audio: one-voice and four-voice effects, mute preference
      (the stored flag is "sound **disabled**"), suspend/resume after
      backgrounding, silent-switch and external-audio mixing
- [ ] No stale `.framework` or `libFinch.a` references survive generation:
      `grep -rn "libFinch\|Build/iOS/\(ASN1Swift\|TPInAppReceipt\|CocoaLumberjack\)" .`

## 8. What is different about the new binaries

All five were verified by linking both slices and running them on an arm64
simulator against independently derived expectations (76 assertions, all
passing). Details are in each `BUILD-RECORD.md`.

- **Deployment target is now iOS 15.0.** Upstream manifests declared iOS 10/11,
  which current Xcode cannot build. Matches the app minimum.
- **`armv7` and `i386` are gone.** Neither is supported by current Xcode and the
  iOS 15 minimum does not need them. Simulator slices keep `x86_64` alongside
  `arm64` for Intel machines.
- **Bundle identifiers are now `com.emoji.<Name>`** (previously
  `org.cocoapods.*` / `com.deusty.*`). Only relevant if something looks a
  framework up by identifier — nothing in this app does.
- **TPInAppReceipt's certificates moved** from the framework root into
  `TPInAppReceipt_TPInAppReceipt.bundle` inside the framework. That is the
  correct location for SwiftPM's generated accessor, and it was verified at
  runtime: signature validation loads `AppleIncRootCertificate.cer` and reaches
  certificate-chain evaluation, which it cannot do if the bundle is unreachable.
- **ASN1Swift is supplied exactly once.** `TPInAppReceipt.xcframework` links
  `@rpath/ASN1Swift.framework/ASN1Swift` dynamically, matching the previously
  shipped binary. Check with `otool -L` if you ever suspect a duplicate.
- **CocoaLumberjackSwift links the core dynamically** —
  `@rpath/CocoaLumberjack.framework/CocoaLumberjack`, one implementation.
- **ASN1Swift 1.2.3 returns `Data` that aliases the caller's buffer**
  (`Data(bytesNoCopy:deallocator:.none)`). A decoded `Data` is only valid while
  the source `Data` is alive. This is upstream behaviour, unchanged by the
  rebuild, and TPInAppReceipt holds its receipt as a stored property — but worth
  knowing if any app code ever calls ASN1Swift directly.

### Checksums

From the current local build. **`BUILD-RECORD.md` in each version folder is
authoritative** — every rebuild produces a new archive, so re-read the record
for whatever you actually publish rather than trusting the table below.

| Artifact | SHA-256 |
| --- | --- |
| `ASN1Swift.xcframework.zip` | `1df23c3dfd6b3ebf6f089377e3186073a57c5e989c26c246d1ef55fdb0adb21c` |
| `TPInAppReceipt.xcframework.zip` | `1b95d69d59a0b4963405b22ad29714ceafa2f75ba1b3573a8b56116681f18607` |
| `CocoaLumberjack.xcframework.zip` | `ae786b2067da2f482d9ae9fdc004a0a496485b06432233a751fae4122af61db4` |
| `CocoaLumberjackSwift.xcframework.zip` | `a4fa933d787d78ca8510b7674b1c7755aca3bf19111600dd8a39a0bfeffebd2e` |
| `Finch.xcframework.zip` | `8e9baf703c3381456f0853974c93e5d580b6e082f33080803c16fdbf64aaf7f6` |

## 9. Rollback

Nothing is destructive until step 4.4. To revert: restore the four manifest URLs
and the `.framework` filenames, drop the Finch binary entry, restore
`Dependency.File.Finch` and the vendored folder, re-add the `EXCLUDED_ARCHS`
line, then `tuist dependencies fetch` and regenerate. The legacy feeds and
artifacts were never modified, so the old pins still resolve exactly as before.

## 10. Rebuilding a dependency

In `~/Dev/Git/Tayfun/Dependencies`:

```bash
./Tools/build-xcframework.sh --list
./Tools/build-xcframework.sh ASN1Swift        # or --all
./Tools/verify-xcframework.sh ASN1Swift       # or --all
```

Recipes are in `Tools/recipes/`, runtime harnesses in `Tools/verification/`.
See `Tools/README.md` for the recipe format and for why each packaging decision
was made. Source revisions are pinned by commit and checked against their tag on
every build.
