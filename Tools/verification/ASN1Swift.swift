import Foundation
import ASN1Swift

// `receipt` / `newReceipt` come from the upstream test fixture (fetched by the
// recipe) and are globals, so they stay alive for the whole run. That matters:
// ASN1Swift 1.2.3 returns `Data` built with `Data(bytesNoCopy:deallocator:.none)`
// pointing into the caller's buffer, so the source must outlive the decoded
// result. That is upstream behaviour, and is how TPInAppReceipt holds its
// receipt data.
//
// Expected values were produced independently with `openssl pkcs7` and
// `openssl asn1parse` on the same fixture, so a pass means the binary decodes
// correctly, not merely that it loaded.

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
func hex(_ d: Data) -> String { d.map { String(format: "%02X", $0) }.joined() }

let decoder = ASN1Decoder()
let signed = try decoder.decode(PKCS7Container.self, from: receipt).signedData

check("signedData version", "\(signed.version)", "1")
check("certificate count", "\(signed.certificates.certificates.count)", "3")
check("digest algorithm count", "\(signed.alg.items.count)", "1")
check("digest algorithm OID (sha1)", signed.alg.items[0].algorithm, "1.3.14.3.2.26")
// %X consumes 32 bits; serialNumber is a 64-bit Int.
check("leaf certificate serial",
      String(format: "%016lX", signed.certificates.certificates[0].cert.serialNumber),
      "0EEB5787E79E098D")
check("intermediate certificate serial",
      String(format: "%016lX", signed.certificates.certificates[1].cert.serialNumber),
      "01DEBCC4396DA010")
check("root certificate serial",
      "\(signed.certificates.certificates[2].cert.serialNumber)", "2")
check("signerInfo version", "\(signed.signerInfos.version)", "1")
check("signerInfo encryptedDigest", hex(signed.signerInfos.encryptedDigest),
      "0EA5E1C1DE8754148D5A64C06BACBDD5F28F04A16507E106C52EE78BB4F50AEF9ADF0B093ABA03C02B69EC5ACBE77583ECA460961A89AF876FD20E486747C3171E94E66F3F51339919B1F3344C232A49166672E7FFA772322DC4DE243F9BE44CC674C72A11B8D9E6818AFAF6B141A4EAF169925305171E23B9EA99A3E098847081EC605F900FB0004BBD76F3717635C40D73FCEE2B80DF98B3FFFD567307893C85C018759346FAADDAFDE96C3106603F577E5B4DE866E77A8A1EFBC06CF67636DC8998E4D39B77170312D6DED7AF89E166877C3222A0582304E3EAEE349E24925C9A02B3BC386FFF9AB6A607CFE40BD73384835C20AA1E21780B3E7A47288760")
check("content payload decoded", "\(signed.contentInfo.payload.rawData.count > 0)", "true")

// The StoreKit-test receipt uses indefinite-length encoding throughout.
let newSigned = try decoder.decode(PKCS7Container.self, from: newReceipt).signedData
check("StoreKit-test receipt version", "\(newSigned.version)", "1")
check("StoreKit-test certificate count", "\(newSigned.certificates.certificates.count)", "1")

// Primitive template decoding.
let octetSource = Data([0x04, 0x18, 0x34, 0x30, 0x30, 0x31, 0x2D, 0x30, 0x31, 0x2D,
                        0x30, 0x31, 0x54, 0x30, 0x30, 0x3A, 0x30, 0x30, 0x3A, 0x30,
                        0x30, 0x2B, 0x30, 0x30, 0x30, 0x30])
check("octet string",
      String(data: try decoder.decode(Data.self, from: octetSource,
                                      template: .universal(ASN1Identifier.Tag.octetString)),
             encoding: .ascii) ?? "<nil>",
      "4001-01-01T00:00:00+0000")
withExtendedLifetime(octetSource) {}

let intSource = Data([0x02, 0x01, 0x04])
check("integer", "\(try decoder.decode(Int.self, from: intSource, template: .universal(ASN1Identifier.Tag.integer)))", "4")
withExtendedLifetime(intSource) {}

let version = Bundle(identifier: "com.emoji.ASN1Swift")?
    .infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
print("    ASN1Swift \(version) on \(ProcessInfo.processInfo.operatingSystemVersionString)")
exit(failures == 0 ? 0 : 1)
