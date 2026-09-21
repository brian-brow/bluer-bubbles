import Foundation
import Hummingbird
import SQLite3

struct MacContact: Codable, ResponseEncodable, Sendable {
    let id: Int64
    let firstName: String?
    let lastName: String?
    let organization: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case organization
    }
}

struct MacContactIdentifier: Codable, ResponseEncodable, Sendable {
    let contactId: Int64
    let value: String
    let identifierType: String

    enum CodingKeys: String, CodingKey {
        case contactId = "contact_id"
        case value
        case identifierType = "type"
    }
}

struct MacMessage: Codable, ResponseEncodable, Sendable {
    let rowId: Int64
    let guid: String?
    let identifier: String
    let service: String?
    let text: String?
    let date: Int64?
    let isFromMe: Int64
    let isSystemMessage: Int64
    let groupTitle: String?
    let hasAttachments: Int64

    enum CodingKeys: String, CodingKey {
        case rowId = "ROWID"
        case guid
        case identifier
        case service
        case text
        case date
        case isFromMe = "is_from_me"
        case isSystemMessage = "is_system_message"
        case groupTitle = "group_title"
        case hasAttachments = "cache_has_attachments"
    }
}

enum DatabaseError: Error, LocalizedError {
    case open(String)
    case query(String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "database open failed: \(message)"
        case .query(let message): "database query failed: \(message)"
        }
    }
}

struct MacDatabase: Sendable {
    private let messagesPath: String
    private let contactsPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        messagesPath = "\(home)/Library/Messages/chat.db"
        contactsPath = "\(home)/Library/Application Support/AddressBook/Sources/" +
            "A00AB68E-95C9-440F-88D0-576D7C3B6242/AddressBook-v22.abcddb"
    }

    func contacts() throws -> [MacContact] {
        let database = try open(path: contactsPath)
        defer { sqlite3_close(database) }

        let sql = """
            SELECT
                Z_PK AS id,
                ZFIRSTNAME AS first_name,
                ZLASTNAME AS last_name,
                ZORGANIZATION AS organization
            FROM ZABCDRECORD;
            """

        var statement: OpaquePointer?
        let prepareResult = sql.withCString {
            sqlite3_prepare_v2(database, $0, -1, &statement, nil)
        }

        guard prepareResult == SQLITE_OK, let statement else {
            throw DatabaseError.query(message(for: database))
        }
        defer { sqlite3_finalize(statement) }

        var contacts: [MacContact] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            contacts.append(
                MacContact(
                    id: sqlite3_column_int64(statement, 0),
                    firstName: text(from: statement, column: 1),
                    lastName: text(from: statement, column: 2),
                    organization: text(from: statement, column: 3)
                )
            )
        }

        return contacts
    }

    func contactIdentifiers() throws -> [MacContactIdentifier] {
        let database = try open(path: contactsPath)
        defer { sqlite3_close(database) }

        let sql = """
            SELECT
                ZOWNER AS contact_id,
                ZFULLNUMBER AS value,
                'phone' AS type
            FROM ZABCDPHONENUMBER

            UNION ALL

            SELECT
                ZOWNER AS contact_id,
                ZADDRESS AS value,
                'email' AS type
            FROM ZABCDEMAILADDRESS;
            """

        var statement: OpaquePointer?
        let prepareResult = sql.withCString {
            sqlite3_prepare_v2(database, $0, -1, &statement, nil)
        }

        guard prepareResult == SQLITE_OK, let statement else {
            throw DatabaseError.query(message(for: database))
        }
        defer { sqlite3_finalize(statement) }

        var identifiers: [MacContactIdentifier] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            identifiers.append(
                MacContactIdentifier(
                    contactId: sqlite3_column_int64(statement, 0),
                    value: text(from: statement, column: 1) ?? "",
                    identifierType: text(from: statement, column: 2) ?? ""
                )
            )
        }

        return identifiers
    }

    func messages(after rowId: Int64) throws -> [MacMessage] {
        let database = try open(path: messagesPath)
        defer { sqlite3_close(database) }

        let sql = """
            SELECT
                message.ROWID,
                message.guid,
                handle.id AS identifier,
                message.service,
                message.text,
                message.date,
                message.is_from_me,
                message.is_system_message,
                message.group_title,
                message.cache_has_attachments,
                message.attributedBody
            FROM message
            JOIN handle ON message.handle_id = handle.ROWID
            WHERE message.ROWID > ?1
            ORDER BY message.date DESC;
            """

        var statement: OpaquePointer?
        let prepareResult = sql.withCString {
            sqlite3_prepare_v2(database, $0, -1, &statement, nil)
        }

        guard prepareResult == SQLITE_OK, let statement else {
            throw DatabaseError.query(message(for: database))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int64(statement, 1, rowId) == SQLITE_OK else {
            throw DatabaseError.query(message(for: database))
        }

        var messages: [MacMessage] = []

        while true {
            let result = sqlite3_step(statement)

            if result == SQLITE_ROW {
                let messageText = text(from: statement, column: 4)
                    ?? attributedText(from: statement, column: 10)

                messages.append(
                    MacMessage(
                        rowId: sqlite3_column_int64(statement, 0),
                        guid: text(from: statement, column: 1),
                        identifier: text(from: statement, column: 2) ?? "",
                        service: text(from: statement, column: 3),
                        text: messageText,
                        date: integer(from: statement, column: 5),
                        isFromMe: sqlite3_column_int64(statement, 6),
                        isSystemMessage: sqlite3_column_int64(statement, 7),
                        groupTitle: text(from: statement, column: 8),
                        hasAttachments: sqlite3_column_int64(statement, 9)
                    )
                )
            } else if result == SQLITE_DONE {
                break
            } else {
                throw DatabaseError.query(message(for: database))
            }
        }

        return messages
    }

    private func open(path: String) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = path.withCString {
            sqlite3_open_v2($0, &database, SQLITE_OPEN_READONLY, nil)
        }

        guard result == SQLITE_OK, let database else {
            throw DatabaseError.open("could not open \(path)")
        }

        return database
    }

    private func text(
        from statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard let value = sqlite3_column_text(statement, column) else {
            return nil
        }

        return String(cString: value)
    }

    private func integer(
        from statement: OpaquePointer,
        column: Int32
    ) -> Int64? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else {
            return nil
        }

        return sqlite3_column_int64(statement, column)
    }

    private func attributedText(
        from statement: OpaquePointer,
        column: Int32
    ) -> String? {
        guard let blob = sqlite3_column_blob(statement, column) else {
            return nil
        }

        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0 else { return nil }

        let data = Array(
            UnsafeBufferPointer(
                start: blob.assumingMemoryBound(to: UInt8.self),
                count: count
            )
        )

        let markers = [Array("NSString".utf8), Array("NSMutableString".utf8)]
        guard let match = markers.compactMap({ marker in
            find(marker, in: data).map { ($0, marker.count) }
        }).min(by: { $0.0 < $1.0 }) else {
            return nil
        }

        var index = match.0 + match.1 + 5
        guard index < data.count else { return nil }

        let length: Int
        switch data[index] {
        case 0x81:
            guard index + 3 <= data.count else { return nil }
            length = Int(data[index + 1]) | (Int(data[index + 2]) << 8)
            index += 3
        case 0x82:
            guard index + 4 <= data.count else { return nil }
            length = Int(data[index + 1]) |
                (Int(data[index + 2]) << 8) |
                (Int(data[index + 3]) << 16)
            index += 4
        default:
            length = Int(data[index])
            index += 1
        }

        guard length > 0, index + length <= data.count else { return nil }

        return String(decoding: data[index..<(index + length)], as: UTF8.self)
    }

    private func find(_ marker: [UInt8], in data: [UInt8]) -> Int? {
        guard !marker.isEmpty, marker.count <= data.count else { return nil }

        for index in 0...(data.count - marker.count) {
            if data[index..<(index + marker.count)].elementsEqual(marker) {
                return index
            }
        }

        return nil
    }

    private func message(for database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
