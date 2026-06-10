import Foundation
import XCTest

final class StatsBoundaryScriptTests: XCTestCase {
    func testScriptFailsWhenForbiddenRemoteSymbolAppearsInSource() throws {
        let fixture = try makeFixture(named: "remote-violation")
        try writeFile(
            at: fixture.appending(path: "Sources/MacWatchApp/App.swift"),
            contents: "let forbidden = \"Remote\"\n"
        )

        let result = try runBoundaryScript(root: fixture)

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Stats boundary verification failed."))
    }

    func testScriptFailsWhenStageThreeForbiddenPatternsAppearInStatsAdapter() throws {
        let forbiddenPatterns = [
            "write(",
            "setFanSpeed",
            "setFanMode",
            "unlockFanControl",
            "resetFanControl",
            "FanMode",
            "DB.shared",
            "SystemStats",
            "Remote",
            "Updater",
            "LevelDB",
            "UserNotifications",
            "Reader<",
            "Module(",
        ]

        for pattern in forbiddenPatterns {
            let fixtureName = pattern
                .replacingOccurrences(of: "(", with: "open")
                .replacingOccurrences(of: "<", with: "lt")
            let fixture = try makeFixture(named: "forbidden-\(fixtureName)")
            try writeFile(
                at: fixture.appending(path: "Sources/StatsAdapter/Adapter.swift"),
                contents: "let forbidden = \"\(pattern)\"\n"
            )

            let result = try runBoundaryScript(root: fixture)

            XCTAssertNotEqual(result.exitCode, 0, "Expected pattern \(pattern) to be rejected")
            XCTAssertTrue(result.output.contains("Stats boundary verification failed."))
        }
    }

    func testScriptAllowsBoundaryDeclarationAndReferenceDocs() throws {
        let fixture = try makeFixture(named: "allowed-declarations")
        try writeFile(
            at: fixture.appending(path: "Sources/StatsAdapter/StatsAdapterBoundary.swift"),
            contents: "let prohibited = [\"Remote\", \"Updater\", \"LevelDB\"]\n"
        )
        try writeFile(
            at: fixture.appending(path: "docs/origin/guide.md"),
            contents: "Do not use Remote or MQTT.\n"
        )
        try writeFile(
            at: fixture.appending(path: "Sources/MacWatchApp/App.swift"),
            contents: "let status = \"ok\"\n"
        )

        let result = try runBoundaryScript(root: fixture)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.output.contains("Stats boundary verification passed."))
    }

    private func makeFixture(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: name)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources/MacWatchApp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources/StatsAdapter"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Tests"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "docs/origin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "docs/architecture"), withIntermediateDirectories: true)
        try writeFile(at: root.appending(path: "Package.swift"), contents: "// fixture\n")
        return root
    }

    private func writeFile(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runBoundaryScript(root: URL) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [boundaryScriptURL.path(percentEncoded: false), root.path(percentEncoded: false)]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    }

    private var boundaryScriptURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "scripts/verify_stats_boundary.sh")
    }
}
