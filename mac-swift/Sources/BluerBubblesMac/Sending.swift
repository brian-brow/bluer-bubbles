import Foundation
import Hummingbird

struct SendMessageRequest: Decodable, Sendable {
    let identifier: String
    let message: String
}

struct SendMessageResponse: Codable, ResponseEncodable, Sendable {
    let success: Bool
    let returncode: Int32?
    let stdout: String?
    let error: String?
}

struct AppleScriptSender: Sendable {
    func send(
        identifier: String,
        message: String
    ) throws -> SendMessageResponse {
        let script = """
            on run argv
                set targetNumber to item 1 of argv
                set messageText to item 2 of argv
                tell application "Messages"
                    set targetService to first account whose service type is iMessage
                    set targetBuddy to participant targetNumber of targetService
                    send messageText to targetBuddy
                end tell
            end run
            """

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-", identifier, message]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            return SendMessageResponse(
                success: false,
                returncode: process.terminationStatus,
                stdout: stdout,
                error: stderr
            )
        }

        return SendMessageResponse(
            success: true,
            returncode: process.terminationStatus,
            stdout: stdout,
            error: nil
        )
    }
}
