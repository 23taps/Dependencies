Packaging changes applied to the pinned source (no implementation source was
modified):

- The ASN1Swift dependency is replaced by a local checkout of exactly commit
  `0f3150de37d38190768caaff19c498d85efad715` (tag 1.2.3), so the receipt build
  cannot resolve an ASN1Swift other than the one this repository distributes,
  and so its product type can be forced dynamic. Pinning the version alone is
  not enough: a resolved dependency keeps the static product type declared by
  its own manifest, which absorbs ASN1Swift's implementation into TPInAppReceipt.
- Both library products forced to `type: .dynamic`, so ASN1Swift stays a
  separate dynamic framework instead of being absorbed statically into
  TPInAppReceipt while also being distributed separately.
- `IPHONEOS_DEPLOYMENT_TARGET=15.0`; upstream declares iOS 10.

`AppleIncRootCertificate.cer` and `StoreKitTestCertificate.cer` ship in the
package's resource bundle, which is copied into the framework. The runtime
harness loads the root certificate through the compiled bundle accessor, so a
bundle that is present but not findable fails verification.
