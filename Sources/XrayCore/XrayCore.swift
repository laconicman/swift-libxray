// Public: `Data` appears in the public signature of `convertShareLinks`.
public import Foundation

/// The process's one door into Xray-core.
///
/// The `LibXray` artifact embeds a single Go runtime, so there is exactly one engine per
/// process and this actor is its only door: every call is serialized here. Use
/// ``shared``.
///
/// Two behaviors to plan around (measured on macOS 26.6, Xray 26.10.21):
///
/// - ``run(configJSON:)`` *returns before the inbounds accept*. The call itself takes
///   ~1 ms, while the core finishes starting ~350 ms later. ``isRunning`` flips true at
///   once; probe the inbound socket itself before sending traffic.
/// - Xray writes its own log to **stdout** — start banner, then one `accepted` line per
///   connection — and the JSON API exposes no log hook (`app/log/log_creator.go` at
///   v26.10.21 registers the console writer as `log.New(os.Stdout, …)`). Silence it at
///   the config level (`"log":{"access":"none","loglevel":"none"}`) or route it to a
///   file (`"log":{"access":"none","error":"<path>"}`) if stdout is yours.
public actor XrayCore {
    /// The shared instance: the Go runtime is process-global; this actor is its only door.
    public static let shared = XrayCore()

    private init() {}

    /// Xray's own version string (`xrayVersion`), e.g. `"26.10.21"`.
    ///
    /// This is the provenance check: it answers what the linked artifact really is. The
    /// test suite pins it; bump the expectation when the engine asset changes.
    public func version() throws(XrayError) -> String {
        struct Response: Decodable { let version: String }
        let data = try Invoke.call("xrayVersion", payload: EmptyPayload())
        return try Invoke.decode(Response.self, from: data, method: "xrayVersion").version
    }

    /// Up to `count` currently-free TCP ports (`getFreePorts`), excluding `excluding`
    /// (system proxies, other inbounds). Not reserved — bind promptly or race.
    public func freePorts(_ count: Int, excluding: Set<UInt16> = []) throws(XrayError) -> [UInt16] {
        struct Response: Decodable { let ports: [Int] }
        let payload = FreePortsPayload(count: count, excludePorts: excluding.map(Int.init))
        let data = try Invoke.call("getFreePorts", payload: payload)
        let response = try Invoke.decode(Response.self, from: data, method: "getFreePorts")
        return response.ports.compactMap(UInt16.init(exactly:))
    }

    /// Parses share links (or a subscription's text) into Xray outbounds
    /// (`convertShareLinksToXrayJson`).
    ///
    /// Returns the JSON object `{"outbounds":[…]}` **exactly as libXray produced it** — the
    /// caller splices it into a full config. Two properties of the emitted shape (Xray
    /// 26.10.21):
    ///
    /// - It is the *flat* outbound shape: `settings` carries `{address, port, id,
    ///   encryption}` directly — no `vnext`/`users` — and `pbk` lands in
    ///   `realitySettings.password`, `sid` in `shortId`, `spx` in `spiderX`.
    /// - The link's `#fragment` becomes the outbound's `tag`; nothing is written to
    ///   `sendThrough`.
    ///
    /// Unparseable links are dropped silently; only a text that yields *no* outbound is an
    /// error.
    public func convertShareLinks(_ text: String) throws(XrayError) -> Data {
        try Invoke.call("convertShareLinksToXrayJson", payload: ConvertLinksPayload(text: text))
    }

    /// Validates a full config (`testXray`) without starting anything — the config builds
    /// or the call throws with Xray's reason. Cheap: ~0.4 ms.
    public func test(configJSON: String) throws(XrayError) {
        _ = try Invoke.call("testXray", payload: XrayJSONPayload(xrayJson: configJSON))
    }

    /// Starts the core (`runXray`) with a full config. **Returns before the inbounds
    /// accept** (~1 ms for the call, ~350 ms to accept — see the type's discussion). A
    /// second ``run(configJSON:)`` after ``stop()`` starts cleanly in the same process.
    public func run(configJSON: String) throws(XrayError) {
        _ = try Invoke.call("runXray", payload: XrayJSONPayload(xrayJson: configJSON))
    }

    /// Stops the core (`stopXray`). ``isRunning`` reads false right after.
    public func stop() throws(XrayError) {
        _ = try Invoke.call("stopXray", payload: EmptyPayload())
    }

    /// Whether the engine's instance is up (`getXrayState` → `data.running`). False on any
    /// engine error — the engine not answering is indistinguishable from not running.
    public var isRunning: Bool {
        struct Response: Decodable { let running: Bool }
        guard let data = try? Invoke.call("getXrayState", payload: EmptyPayload()),
              let response = try? Invoke.decode(Response.self, from: data, method: "getXrayState")
        else { return false }
        return response.running
    }
}
