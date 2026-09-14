import Foundation
import TPInAppReceipt

// Exercises receipt parsing through the public API, against values derived
// independently from the same fixtures with `openssl` plus a DER reader — so a
// pass means the binary parses correctly, not merely that it loaded.
//
// The fixtures come from the pinned upstream test sources (fetched by the
// recipe). `legacyReceipt` is a definite-length production receipt with 187
// in-app purchases; `newReceipt` is an indefinite-length StoreKit-test receipt.

var failures = 0
func check(_ label: String, _ actual: String, _ expected: String) {
    let ok = actual == expected
    print("    \(ok ? "PASS" : "FAIL")  \(label)")
    if !ok {
        print("            expected: \(expected)")
        print("            actual:   \(actual)")
        failures += 1
    }
}

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]
func stamp(_ date: Date?) -> String {
    guard let date else { return "<nil>" }
    return iso.string(from: date)
}

// ---- production receipt, definite-length encoding -------------------------
let legacy = try InAppReceipt(receiptData: legacyReceipt)
check("legacy bundle identifier", legacy.bundleIdentifier, "com.nutcall.alert")
check("legacy app version", legacy.appVersion, "32")
check("legacy original app version", legacy.originalAppVersion, "1.0")
check("legacy creation date", stamp(legacy.creationDate), "2020-05-06T18:28:49Z")
check("legacy purchase count", "\(legacy.purchases.count)", "187")
check("legacy has purchases", "\(legacy.hasPurchases)", "true")
check("legacy contains known product",
      "\(legacy.containsPurchase(ofProductIdentifier: "com.nutcallalert.inapp.pro"))", "true")
check("legacy rejects unknown product",
      "\(legacy.containsPurchase(ofProductIdentifier: "not.a.product"))", "false")
check("legacy signature present", "\(legacy.signature?.isEmpty == false)", "true")

let earliest = legacy.purchases.min { $0.purchaseDate < $1.purchaseDate }
check("legacy earliest purchase product", earliest?.productIdentifier ?? "<nil>",
      "com.nutcallalert.inapp.pro")
check("legacy earliest purchase date", stamp(earliest?.purchaseDate),
      "2019-12-10T12:54:58Z")
check("legacy earliest subscription expiry", stamp(earliest?.subscriptionExpirationDate),
      "2019-12-10T12:59:58Z")

// ---- StoreKit-test receipt, indefinite-length encoding --------------------
let storeKit = try InAppReceipt(receiptData: newReceipt)
check("storekit bundle identifier", storeKit.bundleIdentifier, "net.zachariadis.cyclemaps")
check("storekit app version", storeKit.appVersion, "31.10.0")
check("storekit purchase count", "\(storeKit.purchases.count)", "1")
check("storekit product identifier",
      storeKit.purchases.first?.productIdentifier ?? "<nil>", "CYCLEMAPS_PREMIUM")
check("storekit purchase date", stamp(storeKit.purchases.first?.purchaseDate),
      "2020-07-22T17:33:14Z")   // fixture records +0100
check("storekit subscription expiry",
      stamp(storeKit.purchases.first?.subscriptionExpirationDate),
      "2021-07-22T17:33:14Z")
check("storekit renewable subscription",
      "\(storeKit.purchases.first?.isRenewableSubscription == true)", "true")

// ---- the certificate bundle -----------------------------------------------
// The two .cer files ship in the package's resource bundle inside the
// framework, and SwiftPM's generated accessor has to find them there after
// embedding. Hash verification reads the receipt's own SHA-1; signature
// verification is what loads AppleIncRootCertificate.cer, so it is the check
// that actually proves the bundle is reachable.
do {
    try legacy.verifyHash()
    check("receipt hash verification runs", "threw", "did not throw")
} catch IARError.validationFailed(reason: .hashValidation) {
    // Expected: the fixture's hash is bound to the device that produced it.
    check("hash verification reaches the device-bound comparison", "reached", "reached")
} catch {
    check("hash verification reaches the device-bound comparison",
          "unexpected error: \(error)", "reached")
}

// Signature verification is what actually loads AppleIncRootCertificate.cer
// through the package's generated resource accessor, so its failure mode is the
// packaging check. Upstream's order is:
//
//   .appleIncRootCertificateNotFound      -> accessor could not find the file
//   .unableToLoadAppleIncRootCertificate  -> found but unreadable
//   .invalidCertificateChainOfTrust       -> loaded, and SecTrust ran
//
// Only the third means the resource bundle survived framework embedding. The
// fixture's own leaf and WWDR intermediate certificates expired years ago, so
// trust evaluation is expected to reject the chain — that is a property of a
// 2020 fixture, not of this build.
do {
    try legacy.verifySignature()
    check("certificate reachable through the resource accessor", "verified", "verified")
} catch IARError.validationFailed(reason: .signatureValidation(.invalidCertificateChainOfTrust)) {
    check("certificate reachable through the resource accessor",
          "loaded; chain rejected (fixture certificates are expired)",
          "loaded; chain rejected (fixture certificates are expired)")
} catch IARError.validationFailed(reason: .signatureValidation(.appleIncRootCertificateNotFound)) {
    check("certificate reachable through the resource accessor",
          "AppleIncRootCertificate.cer NOT FOUND in the embedded framework", "verified")
} catch IARError.validationFailed(reason: .signatureValidation(.unableToLoadAppleIncRootCertificate)) {
    check("certificate reachable through the resource accessor",
          "AppleIncRootCertificate.cer found but unreadable", "verified")
} catch {
    check("certificate reachable through the resource accessor",
          "unexpected error: \(error)", "verified")
}

let version = Bundle(identifier: "com.emoji.TPInAppReceipt")?
    .infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
print("    TPInAppReceipt \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
exit(failures == 0 ? 0 : 1)
