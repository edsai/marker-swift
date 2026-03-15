import XCTest
@testable import Marker

final class FileIOTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Read

    func testReadUTF8File() throws {
        let path = tempDir.appendingPathComponent("test.md").path
        try "# Hello\nWorld".write(toFile: path, atomically: true, encoding: .utf8)

        let result = try FileIO.readFile(at: path)
        XCTAssertEqual(result.content, "# Hello\nWorld")
        XCTAssertEqual(result.encoding.displayName, "UTF-8")
        XCTAssertEqual(result.lineEnding, .lf)
    }

    func testReadUTF8BOMFile() throws {
        let path = tempDir.appendingPathComponent("bom.md").path
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("# BOM test".data(using: .utf8)!)
        try data.write(to: URL(fileURLWithPath: path))

        let result = try FileIO.readFile(at: path)
        XCTAssertEqual(result.content, "# BOM test")
        XCTAssertEqual(result.encoding.displayName, "UTF-8 BOM")
    }

    func testReadCRLFFile() throws {
        let path = tempDir.appendingPathComponent("crlf.md").path
        try "line1\r\nline2\r\n".write(toFile: path, atomically: true, encoding: .utf8)

        let result = try FileIO.readFile(at: path)
        XCTAssertEqual(result.content, "line1\nline2\n") // Normalized to LF
        XCTAssertEqual(result.lineEnding, .crlf)
    }

    // MARK: - Write

    func testWriteUTF8File() throws {
        let path = tempDir.appendingPathComponent("out.md").path
        try FileIO.writeFile(at: path, content: "# Test", encoding: .utf8, lineEnding: .lf)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(String(data: data, encoding: .utf8), "# Test")
    }

    func testWriteCRLFFile() throws {
        let path = tempDir.appendingPathComponent("crlf-out.md").path
        try FileIO.writeFile(at: path, content: "line1\nline2\n", encoding: .utf8, lineEnding: .crlf)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(String(data: data, encoding: .utf8), "line1\r\nline2\r\n")
    }

    func testWriteUTF8BOMFile() throws {
        let path = tempDir.appendingPathComponent("bom-out.md").path
        try FileIO.writeFile(at: path, content: "BOM", encoding: .utf8BOM, lineEnding: .lf)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(data[0], 0xEF)
        XCTAssertEqual(data[1], 0xBB)
        XCTAssertEqual(data[2], 0xBF)
        XCTAssertEqual(String(data: data.dropFirst(3), encoding: .utf8), "BOM")
    }

    // MARK: - Round-trip

    func testRoundTripPreservesEncoding() throws {
        let path = tempDir.appendingPathComponent("round.md").path
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("hello\r\nworld".data(using: .utf8)!)
        try data.write(to: URL(fileURLWithPath: path))

        let read = try FileIO.readFile(at: path)
        XCTAssertEqual(read.encoding.displayName, "UTF-8 BOM")
        XCTAssertEqual(read.lineEnding, .crlf)
        XCTAssertEqual(read.content, "hello\nworld") // Normalized

        try FileIO.writeFile(at: path, content: read.content, encoding: read.encoding, lineEnding: read.lineEnding)

        let reread = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(reread[0], 0xEF) // BOM preserved
        XCTAssertEqual(String(data: reread.dropFirst(3), encoding: .utf8), "hello\r\nworld") // CRLF restored
    }
}
