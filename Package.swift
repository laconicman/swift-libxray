// swift-tools-version: 6.4
// Layout mirrors devin-kick (laconicman/devin-kick): the vendored engine binary at the
// bottom, a thin handwritten façade over it, and a maintainer tool at the edge that
// re-vendors the artifact and records its provenance.
import PackageDescription

/// Swift 7 upcoming features, on for every handwritten target (see the Design article).
/// `InternalImportsByDefault` turns the layering into a compiler rule: `XrayCore` can only
/// expose the engine's `LibXray` module through an explicit `public import` — and it never
/// does.
let upcoming: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
]

let package = Package(
    name: "swift-libxray",
    platforms: [
        // The artifact's own floors, read off its LC_BUILD_VERSIONs (2026-10-23, spike):
        // the macOS slice's go.o says 13.0 (the Go objects say 12.0; the linker takes the
        // max), and the iOS slice's go.o says 15.0. The xcframework also ships tvOS slices,
        // which stay undeclared until a consumer needs them.
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        // The façade: the API consumers use; `LibXray` stays an implementation detail.
        .library(name: "XrayCore", targets: ["XrayCore"]),
    ],
    dependencies: [
        // DocC catalog rendering via `swift package generate-documentation`.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // The engine: XTLS/libXray's official Apple cgo build, re-zipped so the
        // xcframework sits at the archive root (upstream nests it one folder down) and
        // re-hosted on this repo's Releases. `url` and `checksum` always change together;
        // the provenance record is Upstream/v26.10.21.json.
        .binaryTarget(
            name: "LibXray",
            url: "https://github.com/laconicman/swift-libxray/releases/download/libxray-v26.10.21/LibXray-v26.10.21.xcframework.zip",
            checksum: "c8827e11c5debb005e07510e7450bed399fab93b4dba5c24747b2f1864dfedc0"
        ),
        // Thin façade: one actor and a typed error over CGoInvoke's JSON envelope.
        // `libresolv` is the only extra input — Go's cgo net resolver calls res_9_ninit/
        // nsearch/nclose, the only undefined symbols a consumer link finds (spike, TD-4).
        .target(
            name: "XrayCore",
            dependencies: ["LibXray"],
            swiftSettings: upcoming,
            linkerSettings: [.linkedLibrary("resolv")]
        ),
        // Maintainer tool: fetch the upstream zip, re-pack the xcframework, record
        // provenance, print the Release command. `swift run libxray-asset-tool <tag>`.
        // No dependencies: it parses CommandLine.arguments by hand.
        .executableTarget(
            name: "libxray-asset-tool",
            swiftSettings: upcoming
        ),
        // Offline suite: loopback only, never a real server. `.serialized` — the engine
        // holds one Go runtime per process, and the lifecycle tests own it.
        .testTarget(
            name: "XrayCoreTests",
            dependencies: ["XrayCore"],
            swiftSettings: upcoming
        ),
    ]
)
