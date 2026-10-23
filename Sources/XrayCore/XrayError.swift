// Public: `LocalizedError` is part of the public interface.
public import Foundation

/// The one error ``XrayCore`` throws.
///
/// `message` is libXray's (or Xray's) own text, verbatim — it names what the engine
/// rejected. `stage` says where in the request it happened: encoding the envelope
/// (``Stage/encode``), the engine's answer (`success: false`, ``Stage/invoke``), or
/// reading the response (``Stage/decode``).
public struct XrayError: Error, LocalizedError, Sendable, Hashable {
    /// Where in an invoke the failure happened.
    public enum Stage: Sendable, Hashable {
        /// Encoding `{"apiVersion":3,"method":…,"payload":…}` failed.
        case encode
        /// The engine answered `{"success":false,"error":…}`, or `CGoInvoke` returned nil.
        case invoke
        /// The response envelope or the method's `data` could not be read.
        case decode
    }

    /// The libXray method that was being invoked (`"runXray"`, …).
    public let method: String
    /// Where in the request it failed.
    public let stage: Stage
    /// The engine's or the codec's message, verbatim.
    public let message: String

    public var errorDescription: String? { "\(method): \(message)" }
}
