import Foundation

enum LineEnding: String {
    case lf = "LF"
    case crlf = "CRLF"

    var characters: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        }
    }
}

enum FileEncoding {
    case utf8
    case utf8BOM
    case latin1

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .latin1: return .isoLatin1
        }
    }

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 BOM"
        case .latin1: return "Latin-1"
        }
    }
}

struct FileContent {
    let content: String
    let encoding: FileEncoding
    let lineEnding: LineEnding
}

struct FileIO {
    // MARK: - Read

    static func readFile(at path: String) throws -> FileContent {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        // Detect encoding
        let encoding = detectEncoding(data)

        // Decode content
        let rawContent: String
        switch encoding {
        case .utf8BOM:
            // Skip 3-byte BOM
            let contentData = data.dropFirst(3)
            guard let decoded = String(data: contentData, encoding: .utf8) else {
                throw FileIOError.decodingFailed(path)
            }
            rawContent = decoded
        case .utf8:
            guard let decoded = String(data: data, encoding: .utf8) else {
                // Fall back to Latin-1
                guard let latin = String(data: data, encoding: .isoLatin1) else {
                    throw FileIOError.decodingFailed(path)
                }
                return FileContent(content: latin.replacingOccurrences(of: "\r\n", with: "\n"),
                                   encoding: .latin1,
                                   lineEnding: detectLineEnding(latin))
            }
            rawContent = decoded
        case .latin1:
            guard let decoded = String(data: data, encoding: .isoLatin1) else {
                throw FileIOError.decodingFailed(path)
            }
            rawContent = decoded
        }

        let lineEnding = detectLineEnding(rawContent)
        // Normalize to LF for the editor
        let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")

        return FileContent(content: normalized, encoding: encoding, lineEnding: lineEnding)
    }

    // MARK: - Write

    static func writeFile(at path: String, content: String, encoding: FileEncoding, lineEnding: LineEnding) throws {
        // Convert line endings
        var output = content
        if lineEnding == .crlf {
            // First normalize to LF, then convert to CRLF
            output = output.replacingOccurrences(of: "\r\n", with: "\n")
            output = output.replacingOccurrences(of: "\n", with: "\r\n")
        }

        guard var data = output.data(using: encoding.stringEncoding) else {
            throw FileIOError.encodingFailed(path)
        }

        // Prepend BOM for UTF-8 BOM files
        if encoding == .utf8BOM {
            data = Data([0xEF, 0xBB, 0xBF]) + data
        }

        // Atomic write
        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Detection

    private static func detectEncoding(_ data: Data) -> FileEncoding {
        // Check for UTF-8 BOM (EF BB BF)
        if data.count >= 3,
           data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return .utf8BOM
        }

        // Try UTF-8 first
        if String(data: data, encoding: .utf8) != nil {
            return .utf8
        }

        return .latin1
    }

    private static func detectLineEnding(_ content: String) -> LineEnding {
        if content.contains("\r\n") {
            return .crlf
        }
        return .lf
    }
}

enum FileIOError: LocalizedError {
    case decodingFailed(String)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let path): return "Could not decode file: \(path)"
        case .encodingFailed(let path): return "Could not encode file: \(path)"
        }
    }
}
