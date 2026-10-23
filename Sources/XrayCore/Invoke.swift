import Foundation
import LibXray

/// The single call libXray understands, wrapped once.
///
/// `CGoInvoke` speaks one envelope — `{"apiVersion":3,"method":…,"payload":…}` — and
/// answers `{"success":bool,"data":…,"error":string}` (`invoke.go` / `invoke_model.go`
/// @ v26.10.21). Request and response are capped at 16 MiB upstream.
enum Invoke {
    /// Encodes the envelope, calls `CGoInvoke`, copies and frees the answer, and returns
    /// `data` re-serialised — or an empty `{}` when `data` is null (testXray, runXray,
    /// stopXray answer `{"success":true,"data":{}}`).
    ///
    /// `CGoInvoke` takes a non-const `char *`; `withCString` hands a const one, so the cast
    /// is `UnsafeMutablePointer(mutating:)`. Upstream only reads it (the bridge copies into
    /// a Go string on entry). Every non-null answer is released with `CGoFree` — also on an
    /// error envelope.
    static func call(_ method: String, payload: some Encodable) throws(XrayError) -> Data {
        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(Envelope(method: method, payload: payload))
        } catch {
            throw XrayError(method: method, stage: .encode, message: String(describing: error))
        }

        let request = String(decoding: requestData, as: UTF8.self)
        let answer = request.withCString { CGoInvoke(UnsafeMutablePointer(mutating: $0)) }
        guard let answer else {
            throw XrayError(method: method, stage: .invoke, message: "CGoInvoke returned nil")
        }
        let text = String(cString: answer)
        CGoFree(answer)

        guard let envelope = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let success = envelope["success"] as? Bool
        else {
            throw XrayError(method: method, stage: .decode, message: "unreadable response: \(text)")
        }
        guard success else {
            throw XrayError(method: method, stage: .invoke, message: envelope["error"] as? String ?? "unknown error")
        }
        guard let data = envelope["data"], !(data is NSNull) else {
            return Data("{}".utf8)
        }
        do {
            return try JSONSerialization.data(withJSONObject: data)
        } catch {
            throw XrayError(method: method, stage: .decode, message: String(describing: error))
        }
    }

    /// Decodes a method's `data` into its tiny response struct.
    static func decode<R: Decodable>(_ type: R.Type, from data: Data, method: String) throws(XrayError) -> R {
        do {
            return try JSONDecoder().decode(R.self, from: data)
        } catch {
            throw XrayError(method: method, stage: .decode, message: String(describing: error))
        }
    }
}

// MARK: - Payloads

/// The request envelope `{"apiVersion":3,"method":…,"payload":…}`.
private struct Envelope<Payload: Encodable>: Encodable {
    let apiVersion = 3
    let method: String
    let payload: Payload
}

/// The empty `{}` payload of `xrayVersion`, `getXrayState` and `stopXray`.
struct EmptyPayload: Encodable {}

/// `getFreePorts`: `{"count":N,"excludePorts":[…]}`.
struct FreePortsPayload: Encodable {
    let count: Int
    let excludePorts: [Int]
}

/// `convertShareLinksToXrayJson`: `{"text":"…"}` (its optional `age.secretKey` stays
/// unexposed until a consumer needs an Age-encrypted subscription).
struct ConvertLinksPayload: Encodable {
    let text: String
}

/// `testXray` and `runXray`: `{"xrayJson":"<config as a string>"}`.
struct XrayJSONPayload: Encodable {
    let xrayJson: String
}
