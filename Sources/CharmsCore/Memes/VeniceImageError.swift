import Foundation

/// Why Venice returned no artwork. The messages are fixed: text from the
/// service could quote the description, so it is neither shown nor logged.
public enum VeniceImageError: Error, LocalizedError, Equatable, Sendable {
    case turnedOff
    case missingKey
    case keyUnreadable
    case emptyDescription
    case descriptionTooLong
    case rejectedKey
    case paymentRequired
    case forbidden
    case invalidRequest
    case modelUnavailable
    case refused
    case blurred
    case busy
    case unavailable
    case timedOut
    case offline
    case connectionFailed
    case unexpectedResponse

    init(status: Int) {
        switch status {
        case 400: self = .invalidRequest
        case 401: self = .rejectedKey
        case 402: self = .paymentRequired
        case 403: self = .forbidden
        case 404, 410: self = .modelUnavailable
        case 422: self = .refused
        case 429, 503: self = .busy
        case 408, 504: self = .timedOut
        default: self = .unavailable
        }
    }

    init(_ error: URLError) {
        switch error.code {
        case .timedOut: self = .timedOut
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: self = .offline
        default: self = .connectionFailed
        }
    }

    public var errorDescription: String? {
        switch self {
        case .turnedOff: return "Venice is turned off in Settings → Memes."
        case .missingKey: return "Add a Venice API key in Settings → Memes."
        case .keyUnreadable: return "Charms couldn’t read the Venice key. Allow Keychain access, or save the key again in Settings → Memes."
        case .emptyDescription: return "Describe the scene first."
        case .descriptionTooLong: return "Venice accepts up to \(VeniceImageRequest.maximumDescriptionLength) characters. Shorten the description."
        case .rejectedKey: return "Venice didn’t accept the API key. Check the key and your Venice plan."
        case .paymentRequired: return "Your Venice balance or the key’s spending limit is used up."
        case .forbidden: return "This Venice key isn’t allowed to use that model. Check the key’s restrictions."
        case .invalidRequest: return "Venice couldn’t process this request. Change the description or choose another model."
        case .modelUnavailable: return "Venice doesn’t offer that model right now. Choose another one."
        case .refused: return "The content policy blocked this image. Change the description."
        case .blurred: return "Venice’s safe mode blurred this image, so Charms didn’t use it. Change the description."
        case .busy: return "Venice is busy or limiting requests. Try again later."
        case .unavailable: return "Venice couldn’t create the image. Try again later."
        case .timedOut: return "Venice took too long. It may still bill this request, so check before trying again."
        case .offline: return "Charms couldn’t reach Venice. Check your internet connection."
        case .connectionFailed: return "The connection to Venice failed. It may still bill this request, so check before trying again."
        case .unexpectedResponse: return "Venice didn’t return an image Charms can use. It may still bill this request."
        }
    }
}
