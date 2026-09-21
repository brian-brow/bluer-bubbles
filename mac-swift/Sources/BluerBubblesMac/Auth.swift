import Hummingbird
import HTTPTypes

struct APIKeyAuth: Sendable {
    private let expectedKey: String

    init() throws {
        guard let key = ProcessInfo.processInfo.environment["BLUE_BUBBLES_API_KEY"],
              !key.isEmpty else {
            throw HTTPError(.internalServerError, message: "BLUE_BUBBLES_API_KEY is not set")
        }

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
