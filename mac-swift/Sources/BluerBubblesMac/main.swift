import Hummingbird

let database = MacDatabase()
let sender = AppleScriptSender()
let auth = try APIKeyAuth()
let router = Router()

router.get("health") { _, _ -> String in
    "ok"
}

router.get("contacts") { request, _ in
    try auth.requireKey(from: request)
    return try database.contacts()
}

router.get("contacts/identifiers") { request, _ in
    try auth.requireKey(from: request)
    return try database.contactIdentifiers()
}

router.get("messages/:rowid") { request, context in
    try auth.requireKey(from: request)
    let rowId = try context.parameters.require("rowid", as: Int64.self)
    return try database.messages(after: rowId)
}

router.post("send") { request, context in
    try auth.requireKey(from: request)
    let payload = try await request.decode(
        as: SendMessageRequest.self,
        context: context
    )

    return try sender.send(
        identifier: payload.identifier,
        message: payload.message
    )
}

let application = Application(
    router: router,
    configuration: .init(
        address: .hostname("0.0.0.0", port: 8000)
    )
)

try await application.runService()
