import Foundation
import Hummingbird
import HTTPTypes

struct APIKeyAuth: Sendable {
    private let expectedKey: String

    init() throws {
        if let key = try Keychain.load(), !key.isEmpty {
            expectedKey = key
            return
        }

        guard let key = ProcessInfo.processInfo.environment["BLUE_BUBBLES_API_KEY"],
              !key.isEmpty else {
            throw HTTPError(
                .internalServerError,
                message: "API key is not in Keychain or BLUE_BUBBLES_API_KEY"
            )
        }

        try Keychain.store(key)
        expectedKey = key
    }

    func requireKey(from request: Request) throws {
        guard request.headers[.apiKey] == expectedKey else {
            throw HTTPError(.unauthorized)
        }
    }
}

private extension HTTPField.Name {
    static let apiKey = Self("X-API-Key")!
}
