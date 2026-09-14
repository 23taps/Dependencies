Packaging changes applied to the pinned source (no implementation source was
modified):

- Library products forced to `type: .dynamic`.
- `IPHONEOS_DEPLOYMENT_TARGET=15.0`; upstream declares iOS 11.

This is the core module only. The application also imports `CocoaLumberjackSwift`,
which is a separate module built from this same tag and must be rebuilt
alongside it — the two are not interchangeable, and a folder named "merged" does
not make one archive serve both.

Upstream ships `PrivacyInfo.xcprivacy` as a processed resource, so it arrives in
the framework's own resource bundle rather than being added by this repository.
