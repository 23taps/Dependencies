The payload is a static `libFinch.a` per platform, not a dynamic framework, so
Finch stays linked into the Games target and does not acquire a framework's
separate resource-bundle location — it derives its default sound bundle from its
own class location.

An XCFramework is used rather than keeping a single fat `libFinch.a` because one
archive cannot carry both arm64 slices. The previously vendored archive held
`armv7 i386 x86_64 arm64`, which worked only because the architectures
disambiguated the platform on their own: i386/x86_64 could only be simulator,
armv7/arm64 only device. An arm64 simulator has no distinct CPU type, so
`lipo -create` refuses ("same architectures (arm64) found"), and merging the
object files into one thin archive instead makes the linker refuse ("building
for 'iOS-simulator', but linking in object file ... built for 'iOS'"). Both were
tested. This is packaging only: consumers still link a static library.

Built from the implementation files the upstream podspec names, with ARC and
modules, excluding test sources. OpenAL deprecation warnings are expected.

**Unresolved before this can replace the vendored `libFinch.a`:** the
application's local `FISound.h` declares `gain`/`pitch` as `CGFloat` where
upstream 1.0.3 declares `float`, and the local initializer and `sharedEngine`
declarations differ too. The vendored binary matches the 1.0.3 distribution
archive byte-for-byte, which establishes the artifact version but not which
header edits were accompanied by implementation patches. Reconcile the headers
against the shipped ABI, or recover the original patches, before swapping the
binary — this build is unmodified upstream 1.0.3.
