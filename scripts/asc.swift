#!/usr/bin/env swift
// Talks to the App Store Connect API with the key from Config/AppStoreConnect.env (see scripts/testflight.sh).
//
//   swift scripts/asc.swift status                                  # the app's tester groups and latest builds
//   swift scripts/asc.swift distribute --build 4 --notes-file notes.txt [--internal-only]
//
// distribute waits until the build has finished processing, sets its "What to Test" notes, adds it to every tester
// group (internal and external), and submits it for beta review when Apple needs that for external testers.
import CryptoKit
import Foundation

// MARK: Setup

let bundleID = "io.github.nickcia.runcoach"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func say(_ message: String) {
    print(message)
    fflush(stdout)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let env: [String: String] = {
    guard let text = try? String(contentsOf: root.appending(path: "Config/AppStoreConnect.env"), encoding: .utf8) else {
        fail("Missing Config/AppStoreConnect.env (see scripts/testflight.sh).")
    }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") where !line.hasPrefix("#") {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 { values[parts[0]] = parts[1] }
    }
    return values
}()
guard let keyID = env["ASC_KEY_ID"], let issuerID = env["ASC_ISSUER_ID"], !keyID.isEmpty, !issuerID.isEmpty else {
    fail("ASC_KEY_ID and ASC_ISSUER_ID must be set in Config/AppStoreConnect.env.")
}
let keyPath = (env["ASC_KEY_PATH"] ?? "~/.appstoreconnect/private_keys/AuthKey_\(keyID).p8")
    .replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8),
      let signingKey = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    fail("Couldn't read the API key at \(keyPath).")
}

// MARK: API

/// A short-lived token (App Store Connect allows up to 20 minutes), made fresh for each request.
func token() -> String {
    func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header = #"{"alg":"ES256","kid":"\#(keyID)","typ":"JWT"}"#
    let claims = #"{"iss":"\#(issuerID)","iat":\#(now),"exp":\#(now + 15 * 60),"aud":"appstoreconnect-v1"}"#
    let unsigned = base64URL(Data(header.utf8)) + "." + base64URL(Data(claims.utf8))
    let signature = try! signingKey.signature(for: Data(unsigned.utf8))
    return unsigned + "." + base64URL(signature.rawRepresentation)
}

struct APIError: Error, CustomStringConvertible {
    var status: Int
    var body: String
    var description: String {
        let detail = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            .flatMap { ($0["errors"] as? [[String: Any]])?.compactMap { $0["detail"] as? String }.joined(separator: " ") }
        return "App Store Connect said \(status): \(detail ?? body)"
    }
}

typealias JSON = [String: Any]

@discardableResult
func api(_ method: String, _ path: String, _ body: JSON? = nil) async throws -> JSON {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
    request.httpMethod = method
    request.setValue("Bearer \(token())", forHTTPHeaderField: "Authorization")
    if let body {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else { throw APIError(status: status, body: String(decoding: data, as: UTF8.self)) }
    return data.isEmpty ? [:] : (try JSONSerialization.jsonObject(with: data) as? JSON ?? [:])
}

func items(_ reply: JSON) -> [JSON] { reply["data"] as? [JSON] ?? [] }
func attributes(_ item: JSON) -> JSON { item["attributes"] as? JSON ?? [:] }
func id(_ item: JSON) -> String { item["id"] as? String ?? "" }

func appID() async throws -> String {
    guard let app = items(try await api("GET", "/v1/apps?filter[bundleId]=\(bundleID)")).first else {
        fail("No app with bundle ID \(bundleID) in App Store Connect.")
    }
    return id(app)
}

func groups(app: String) async throws -> [JSON] {
    items(try await api("GET", "/v1/apps/\(app)/betaGroups?limit=50"))
}

// MARK: Commands

let arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
}

func status() async throws {
    let app = try await appID()
    say("Tester groups:")
    for group in try await groups(app: app) {
        let a = attributes(group)
        let kind = (a["isInternalGroup"] as? Bool ?? false) ? "internal" : "external"
        let link = (a["publicLinkEnabled"] as? Bool ?? false) ? ", public link on" : ""
        say("  \(a["name"] as? String ?? "?") (\(kind)\(link))")
    }
    say("Latest builds:")
    let builds = items(try await api("GET", "/v1/builds?filter[app]=\(app)&sort=-uploadedDate&limit=5"))
    for build in builds {
        let a = attributes(build)
        say("  build \(a["version"] as? String ?? "?"): \(a["processingState"] as? String ?? "?")\((a["expired"] as? Bool ?? false) ? ", expired" : "")")
    }
}

func distribute() async throws {
    guard let number = option("--build") else { fail("Say which build: --build 4") }
    let notes: String
    if let file = option("--notes-file") {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { fail("Can't read \(file).") }
        notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let text = option("--notes") {
        notes = text
    } else {
        fail("Give the What to Test notes: --notes-file notes.txt (or --notes \"...\").")
    }
    let internalOnly = arguments.contains("--internal-only")
    let app = try await appID()

    // 1. Wait for the build to show up and finish processing (Apple usually takes 10 to 30 minutes).
    say("Waiting for build \(number) to finish processing…")
    var build: JSON?
    let deadline = Date().addingTimeInterval(60 * 60)
    while Date() < deadline {
        build = items(try await api("GET", "/v1/builds?filter[app]=\(app)&filter[version]=\(number)&limit=1")).first
        let state = build.map { attributes($0)["processingState"] as? String ?? "" } ?? "not there yet"
        if state == "VALID" { break }
        if state == "FAILED" || state == "INVALID" { fail("Build \(number) failed processing (\(state)). Check App Store Connect.") }
        say("  \(state); checking again in a minute")
        try await Task.sleep(for: .seconds(60))
    }
    guard let build, attributes(build)["processingState"] as? String == "VALID" else {
        fail("Build \(number) still wasn't ready after an hour. Run this again later.")
    }
    let buildID = id(build)
    say("Build \(number) is ready.")

    // 2. What to Test.
    let localizations = items(try await api("GET", "/v1/builds/\(buildID)/betaBuildLocalizations"))
    if let existing = localizations.first {
        try await api("PATCH", "/v1/betaBuildLocalizations/\(id(existing))", [
            "data": ["type": "betaBuildLocalizations", "id": id(existing), "attributes": ["whatsNew": notes]]])
    } else {
        try await api("POST", "/v1/betaBuildLocalizations", [
            "data": ["type": "betaBuildLocalizations", "attributes": ["locale": "en-US", "whatsNew": notes],
                     "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]])
    }
    say("Set What to Test.")

    // 3. Every tester group (internal ones only with --internal-only).
    let targets = try await groups(app: app).filter { !internalOnly || (attributes($0)["isInternalGroup"] as? Bool ?? false) }
    var external = false
    for group in targets {
        let a = attributes(group)
        let name = a["name"] as? String ?? "?"
        // Groups set to get every build (usually the internal one) can't have builds added; App Store Connect
        // answers 404 or 409 for them.
        if a["hasAccessToAllBuilds"] as? Bool == true {
            say("\(name) gets every build automatically.")
            if !(a["isInternalGroup"] as? Bool ?? false) { external = true }
            continue
        }
        do {
            // Added from the group's side: the build's own betaGroups relationship now answers 404.
            try await api("POST", "/v1/betaGroups/\(id(group))/relationships/builds",
                          ["data": [["type": "builds", "id": buildID]]])
            say("Added to \(name).")
        } catch let error as APIError where error.status == 409 || error.status == 422 {
            say("Already in \(name), or it gets every build anyway.")
        }
        if !(a["isInternalGroup"] as? Bool ?? false) { external = true }
    }

    // 4. External testers need Apple's beta review for a build that hasn't had one.
    if external {
        let detail = try await api("GET", "/v1/builds/\(buildID)/buildBetaDetail")
        let state = (detail["data"] as? JSON).map { attributes($0)["externalBuildState"] as? String ?? "" } ?? ""
        if state == "READY_FOR_BETA_SUBMISSION" {
            try await api("POST", "/v1/betaAppReviewSubmissions", [
                "data": ["type": "betaAppReviewSubmissions",
                         "relationships": ["build": ["data": ["type": "builds", "id": buildID]]]]])
            say("Submitted for beta review. External testers get it once Apple approves (usually within a day).")
        } else {
            say("External testing: \(state.replacingOccurrences(of: "_", with: " ").lowercased()).")
        }
    }
    say("Done.")
}

do {
    switch arguments.first {
    case "status": try await status()
    case "distribute": try await distribute()
    default: fail("Use: swift scripts/asc.swift status | distribute --build N --notes-file FILE [--internal-only]")
    }
} catch {
    fail("\(error)")
}
