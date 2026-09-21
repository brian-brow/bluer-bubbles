import Hummingbird

let database = MacDatabase()
let router = Router()

router.get("health") { _, _ -> String in
    "ok"
}

router.get("contacts") { _, _ in
    try database.contacts()
}

let application = Application(
    router: router,
    configuration: .init(
        address: .hostname("0.0.0.0", port: 8000)
    )
)

try await application.runService()
