import Hummingbird

let router = Router()

router.get("health") { _, _ -> String in
    "ok"
}

let application = Application(
    router: router,
    configuration: .init(
        address: .hostname("0.0.0.0", port: 8000)
    )
)

try await application.runService()
