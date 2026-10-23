import CryptoKit
import Foundation

// Re-vendors the engine artifact: fetch XTLS/libXray's `libxray-apple-cgo.zip` for a tag,
// re-zip the xcframework at the archive root (the layout SwiftPM's binaryTarget wants —
// upstream nests it under `libxray-apple-cgo/`), record provenance in `Upstream/<tag>.json`,
// and print the binaryTarget snippet and the `gh release create` command.
//
//   swift run libxray-asset-tool <upstream-tag> [--out DIR]   (default --out Artifacts)
//
// The re-zip's SHA-256 *is* the checksum `swift package compute-checksum` reports — same
// file, same hash; the spike verified the equivalence on v26.10.21.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("libxray-asset-tool: \(message)\n".utf8))
    exit(1)
}

func usage() -> Never {
    let text = """
        usage: libxray-asset-tool <upstream-tag> [--out DIR]
          e.g. libxray-asset-tool v26.10.21 --out Artifacts

        """
    FileHandle.standardError.write(Data(text.utf8))
    exit(64)
}

// MARK: - arguments

var arguments = Array(CommandLine.arguments.dropFirst())
guard let tag = arguments.first, !tag.hasPrefix("-") else { usage() }
arguments.removeFirst()
// Upstream tags are CalVer `vYY.M.D`. The tag becomes a URL and two file names, so anything
// else is refused here rather than trapping in `URL(string:)` or escaping the output folders.
guard tag.wholeMatch(of: /v\d+\.\d+\.\d+/) != nil else {
    fail("invalid upstream tag '\(tag)': expected vYY.M.D, e.g. v26.10.21")
}

var outPath = "Artifacts"
while let argument = arguments.first {
    arguments.removeFirst()
    guard argument == "--out", let dir = arguments.first else { usage() }
    arguments.removeFirst()
    outPath = dir
}

// MARK: - helpers

func run(_ tool: String, _ toolArguments: [String], cwd: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = toolArguments
    process.currentDirectoryURL = cwd
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "libxray-asset-tool", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "\(tool) exited \(process.terminationStatus)"])
    }
}

/// A pipeline failure after the work directory exists: thrown, not `exit`ed, so the
/// directory's `defer` cleanup runs before `fail` prints it.
struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func sha256(of file: URL) throws -> (hex: String, bytes: Int) {
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return (hex, data.count)
}

// MARK: - pipeline

struct Provenance: Encodable {
    let assetBytes: Int
    let assetName: String
    let assetSHA256: String
    let recordedAt: String
    let slices: [String]
    let upstreamBytes: Int
    let upstreamSHA256: String
    let upstreamTag: String
    let upstreamURL: String
}

do {
    let fileManager = FileManager.default
    let upstreamURL = "https://github.com/XTLS/libXray/releases/download/\(tag)/libxray-apple-cgo.zip"
    guard let downloadURL = URL(string: upstreamURL) else { fail("malformed upstream URL \(upstreamURL)") }

    // 1. Download the upstream zip.
    let (downloaded, response) = try await URLSession.shared.download(from: downloadURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        fail("download failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for \(upstreamURL)")
    }
    let work = fileManager.temporaryDirectory.appendingPathComponent("libxray-asset-tool-\(UUID().uuidString)")
    try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: work) }
    let zip = work.appendingPathComponent("libxray-apple-cgo.zip")
    try fileManager.moveItem(at: downloaded, to: zip)
    let upstream = try sha256(of: zip)
    print("upstream \(upstreamURL)\n  \(upstream.bytes) bytes, sha256 \(upstream.hex)")

    // 2. Unpack and find the xcframework (nested one folder down upstream).
    let unpacked = work.appendingPathComponent("unpacked")
    try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
    try run("/usr/bin/unzip", ["-q", zip.path], cwd: unpacked)
    var xcframework: URL?
    let enumerator = fileManager.enumerator(at: unpacked, includingPropertiesForKeys: nil)
    while let candidate = enumerator?.nextObject() as? URL {
        if candidate.lastPathComponent == "LibXray.xcframework" {
            xcframework = candidate
            break
        }
    }
    guard let xcframework else { throw ToolError("no LibXray.xcframework in the upstream zip") }
    let parent = xcframework.deletingLastPathComponent()

    // 3. Read the slices out of Info.plist.
    let plistData = try Data(contentsOf: xcframework.appendingPathComponent("Info.plist"))
    guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
          let libraries = plist["AvailableLibraries"] as? [[String: Any]]
    else { throw ToolError("unreadable Info.plist in LibXray.xcframework") }
    let slices = libraries.compactMap { $0["LibraryIdentifier"] as? String }
    print("slices: \(slices.joined(separator: ", "))")

    // 4. Re-zip with the xcframework at the archive root — the spike's exact command.
    let out = URL(fileURLWithPath: outPath)
    try fileManager.createDirectory(at: out, withIntermediateDirectories: true)
    let assetName = "LibXray-\(tag).xcframework.zip"
    let asset = out.appendingPathComponent(assetName)
    if fileManager.fileExists(atPath: asset.path) { try fileManager.removeItem(at: asset) }
    try run("/usr/bin/zip", ["-r", "-X", asset.path, "LibXray.xcframework"], cwd: parent)
    let digest = try sha256(of: asset)
    print("asset \(asset.path)\n  \(digest.bytes) bytes, sha256 \(digest.hex)")

    // 5. Record provenance (committed; never hand-edited — see CLAUDE.md).
    let record = Provenance(
        assetBytes: digest.bytes,
        assetName: assetName,
        assetSHA256: digest.hex,
        recordedAt: ISO8601DateFormatter().string(from: Date()),
        slices: slices,
        upstreamBytes: upstream.bytes,
        upstreamSHA256: upstream.hex,
        upstreamTag: tag,
        upstreamURL: upstreamURL
    )
    let upstreamDir = URL(fileURLWithPath: "Upstream")
    try fileManager.createDirectory(at: upstreamDir, withIntermediateDirectories: true)
    let recordURL = upstreamDir.appendingPathComponent("\(tag).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(record).write(to: recordURL)
    print("recorded \(recordURL.path)")

    // 6. Release notes beside the zip, then print what a maintainer runs next.
    let notes = out.appendingPathComponent("LibXray-\(tag)-notes.md")
    try """
        libXray \(tag) — official XTLS/libXray Apple cgo build, re-zipped for SwiftPM.

        | | |
        |---|---|
        | Upstream | \(upstreamURL) |
        | Upstream SHA-256 | `\(upstream.hex)` |
        | Upstream bytes | \(upstream.bytes) |
        | Asset SHA-256 (SwiftPM checksum) | `\(digest.hex)` |
        | Asset bytes | \(digest.bytes) |
        | Slices | \(slices.joined(separator: ", ")) |

        """.write(to: notes, atomically: true, encoding: .utf8)

    print("""

        Package.swift:

            .binaryTarget(
                name: "LibXray",
                url: "https://github.com/laconicman/swift-libxray/releases/download/libxray-\(tag)/\(assetName)",
                checksum: "\(digest.hex)"
            ),

        Publish:

            gh release create libxray-\(tag) \(asset.path) --repo laconicman/swift-libxray --target main --title "libXray \(tag)" --notes-file \(notes.path)

        """)
} catch let error as NSError {
    fail(error.localizedDescription)
}
