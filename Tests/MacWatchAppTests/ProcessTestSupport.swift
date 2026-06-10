import Foundation
import XCTest

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        if stderr.isEmpty {
            return stdout
        }
        if stdout.isEmpty {
            return stderr
        }
        return "\(stdout)\n\(stderr)"
    }
}

func runProcess(
    executable: String,
    arguments: [String],
    environment: [String: String] = [:],
    currentDirectoryURL: URL,
    timeout: TimeInterval
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectoryURL
    if environment.isEmpty == false {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if process.isRunning {
        process.terminate()
        XCTFail("Process timed out: \(arguments.joined(separator: " "))")
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
        exitCode: process.terminationStatus,
        stdout: String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
        stderr: String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    )
}
