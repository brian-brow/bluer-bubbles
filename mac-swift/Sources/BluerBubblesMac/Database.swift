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
    private let contactsPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

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

    private func message(for database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}
