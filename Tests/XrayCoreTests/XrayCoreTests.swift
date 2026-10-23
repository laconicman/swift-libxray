import Foundation
import Network
import Testing

import XrayCore

/// Offline contract for the libXray JSON API. `.serialized`: the engine holds one Go
/// runtime per process, and the lifecycle test owns it. Nothing here leaves loopback.
@Suite(.serialized)
struct XrayCoreTests {
    /// Synthetic VLESS+REALITY+xhttp link — invented credentials, never dialed. The pbk is
    /// the 32 bytes 01…20, base64url without padding, the shape a REALITY public key takes.
    static let link = "vless://11111111-2222-4333-8444-555555555555@proxy.example.com:8443"
        + "?type=xhttp&security=reality&fp=chrome&sni=www.example.com"
        + "&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"
        + "&sid=74682ba3&path=/xhttp&mode=stream-one#Test%20Exit"

    /// The provenance check: `xrayVersion` answers what the linked artifact really is.
    /// Bump with the engine asset — see `Upstream/`.
    @Test func versionMatchesEngineAsset() async throws {
        #expect(try await XrayCore.shared.version() == "26.10.21")
    }

    @Test func freePortsRespectsExclusions() async throws {
        let ports = try await XrayCore.shared.freePorts(3, excluding: [10808])
        #expect(ports.count == 3)
        #expect(Set(ports).count == 3)
        #expect(!ports.contains(10808))
        #expect(ports.allSatisfy { $0 > 0 })
    }

    /// The converter's emitted shape is a contract consumers splice from: flat `settings`
    /// (no vnext), `#fragment` → `tag`, `pbk` → `realitySettings.password`.
    @Test func convertEmitsFlatOutbound() async throws {
        let data = try await XrayCore.shared.convertShareLinks(Self.link)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outbounds = try #require(root["outbounds"] as? [[String: Any]])
        #expect(outbounds.count == 1)

        let outbound = outbounds[0]
        #expect(outbound["protocol"] as? String == "vless")
        #expect(outbound["tag"] as? String == "Test Exit")
        #expect(outbound["sendThrough"] == nil)

        let settings = try #require(outbound["settings"] as? [String: Any])
        #expect(settings["address"] as? String == "proxy.example.com")
        #expect(settings["port"] as? Int == 8443)
        #expect(settings["id"] as? String == "11111111-2222-4333-8444-555555555555")
        #expect(settings["encryption"] as? String == "none")

        let stream = try #require(outbound["streamSettings"] as? [String: Any])
        #expect(stream["network"] as? String == "xhttp")
        #expect(stream["security"] as? String == "reality")

        let reality = try #require(stream["realitySettings"] as? [String: Any])
        #expect(reality["password"] as? String == "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA")
        #expect(reality["shortId"] as? String == "74682ba3")
        #expect(reality["fingerprint"] as? String == "chrome")
        #expect(reality["serverName"] as? String == "www.example.com")

        let xhttp = try #require(stream["xhttpSettings"] as? [String: Any])
        #expect(xhttp["mode"] as? String == "stream-one")
        #expect(xhttp["path"] as? String == "/xhttp")
    }

    @Test func convertRejectsNonLink() async throws {
        do {
            _ = try await XrayCore.shared.convertShareLinks("not a link")
            Issue.record("convertShareLinks accepted plain text")
        } catch {
            #expect(error.method == "convertShareLinksToXrayJson")
            #expect(error.stage == .invoke)
            #expect(!error.message.isEmpty)
        }
    }

    /// A converted outbound spliced into a full config must pass `testXray` — this is the
    /// check that the flat shape (no vnext) is what the core itself builds, without any
    /// network. A malformed config throws with Xray's reason.
    @Test func testValidatesAssembledConfig() async throws {
        let converted = try await XrayCore.shared.convertShareLinks(Self.link)
        let parsed = try #require(JSONSerialization.jsonObject(with: converted) as? [String: Any])
        let outbounds = try #require(parsed["outbounds"] as? [[String: Any]])
        let port = try #require(await XrayCore.shared.freePorts(1).first)
        let config: [String: Any] = [
            "log": ["access": "none", "loglevel": "warning"],
            "inbounds": [[
                "tag": "in", "listen": "127.0.0.1", "port": port,
                "protocol": "mixed", "settings": ["udp": false],
            ]],
            "outbounds": outbounds,
        ]
        let configJSON = String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)
        try await XrayCore.shared.test(configJSON: configJSON)
    }

    @Test func testRejectsMalformedConfig() async throws {
        do {
            try await XrayCore.shared.test(configJSON: "{not json")
            Issue.record("test accepted malformed JSON")
        } catch {
            #expect(error.method == "testXray")
            #expect(error.stage == .invoke)
            #expect(!error.message.isEmpty)
        }
    }

    /// The whole loop, offline: run → inbound accepts → CONNECT through the `mixed`
    /// inbound to a loopback echo → tunneled GET → stop → isRunning false → restart works.
    @Test(.timeLimit(.minutes(1)))
    func runProxyStopRestart() async throws {
        let core = XrayCore.shared
        let echo = try EchoServer()
        let echoPort = try await echo.start()
        defer { echo.stop() }

        let inboundPort = try #require(await core.freePorts(1, excluding: [echoPort]).first)
        let configJSON = """
            {"log":{"access":"none","loglevel":"warning"},\
            "inbounds":[{"tag":"in","listen":"127.0.0.1","port":\(inboundPort),\
            "protocol":"mixed","settings":{"udp":false}}],\
            "outbounds":[{"tag":"direct","protocol":"freedom"}]}
            """

        try await core.run(configJSON: configJSON)
        do {
            try await waitForAccept(port: inboundPort, seconds: 3)

            let proxy = try await connect(port: inboundPort)
            try await send(
                "CONNECT 127.0.0.1:\(echoPort) HTTP/1.1\r\nHost: 127.0.0.1:\(echoPort)\r\n\r\n",
                over: proxy
            )
            let connectAnswer = try await receiveUntil(proxy, contains: "\r\n\r\n")
            #expect(connectAnswer.hasPrefix("HTTP/1.1 200"))

            try await send("GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n", over: proxy)
            let getAnswer = try await receiveUntil(proxy, contains: "\r\n\r\nok")
            #expect(getAnswer.hasSuffix("ok"))
            proxy.cancel()

            #expect(await core.isRunning)
        } catch {
            try? await core.stop()
            throw error
        }

        try await core.stop()
        #expect(await !core.isRunning)

        // A second start in the same process — the Go runtime survives stop/start.
        try await core.run(configJSON: configJSON)
        try await waitForAccept(port: inboundPort, seconds: 3)
        #expect(await core.isRunning)
        try await core.stop()
        #expect(await !core.isRunning)
    }

    /// `errorDescription` is "<method>: <message>", checked on a real engine error.
    @Test func errorDescriptionIsMethodColonMessage() async throws {
        do {
            _ = try await XrayCore.shared.convertShareLinks("not a link")
            Issue.record("convertShareLinks accepted plain text")
        } catch {
            #expect(error.errorDescription == "\(error.method): \(error.message)")
        }
    }
}
