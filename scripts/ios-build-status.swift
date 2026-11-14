// Waits for App Store Connect to finish processing an uploaded build and says how it went.
//   swift scripts/ios-build-status.swift <app id> <build number>
// Uses the team API key from ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID. Exits 1 when Apple
// rejects the build (its errors are printed) or nothing is known after 30 minutes.
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
guard CommandLine.arguments.count == 3, let keyPath = env["ASC_KEY_PATH"], let keyID = env["ASC_KEY_ID"], let issuer = env["ASC_ISSUER_ID"],
      let pem = try? String(contentsOfFile: (keyPath as NSString).expandingTildeInPath, encoding: .utf8),
      let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    print("usage: ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… swift scripts/ios-build-status.swift <app id> <build number>")
    exit(2)
}
let appID = CommandLine.arguments[1], build = CommandLine.arguments[2]

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func token() -> String {
    let now = Int(Date().timeIntervalSince1970)
    let header = base64URL(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"]))
    let claims = base64URL(try! JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"]))
    let signature = try! key.signature(for: Data("\(header).\(claims)".utf8))
    return "\(header).\(claims).\(base64URL(signature.rawRepresentation))"
}

func uploads() -> [[String: Any]] {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com/v1/apps/\(appID)/buildUploads?limit=20")!)
    request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")
    let done = DispatchSemaphore(value: 0)
    var result: [[String: Any]] = []
    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            result = body["data"] as? [[String: Any]] ?? []
        }
        done.signal()
    }.resume()
    done.wait()
    return result
}

for _ in 0..<60 {
    let upload = uploads().first { (($0["attributes"] as? [String: Any])?["cfBundleVersion"] as? String) == build }
    let attributes = upload?["attributes"] as? [String: Any]
    let state = attributes?["state"] as? [String: Any]
    switch state?["state"] as? String {
    case "COMPLETE":
        print("build \(build): processed, ready in TestFlight")
        exit(0)
    case "FAILED":
        print("build \(build): REJECTED by App Store Connect")
        for error in state?["errors"] as? [[String: Any]] ?? [] {
            print("  \(error["code"] ?? ""): \(error["description"] ?? "")")
        }
        exit(1)
    default:
        Thread.sleep(forTimeInterval: 30)
    }
}
print("build \(build): no verdict after 30 minutes")
exit(1)
