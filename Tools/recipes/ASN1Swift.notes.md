Packaging changes applied to the pinned source (no implementation source was
modified):

- `Package.swift` library product forced to `type: .dynamic`, so
  `xcodebuild archive` installs a framework and the app keeps embedding
  ASN1Swift as a dynamic framework.
- `IPHONEOS_DEPLOYMENT_TARGET=15.0`; upstream declares iOS 10, which current
  Xcode no longer supports, and the app requires iOS 15.
- `PrivacyInfo.xcprivacy` copied in to match the previously distributed binary.

Note for consumers: 1.2.3 returns `Data` built with
`Data(bytesNoCopy:deallocator:.none)` pointing into the caller's buffer, so a
decoded `Data` is only valid while the source `Data` is alive. That is upstream
behaviour, unchanged by this rebuild.
