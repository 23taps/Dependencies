Packaging changes applied to the pinned source (no implementation source was
modified):

- Library products forced to `type: .dynamic`, so the Swift wrapper links
  against the core dynamically instead of absorbing a second copy of its
  implementation.
- `IPHONEOS_DEPLOYMENT_TARGET=15.0`; upstream declares iOS 11.

The `CocoaLumberjackSwiftSupport` target is part of this product's target graph
and is built into it; it is not a separate distributable module.
