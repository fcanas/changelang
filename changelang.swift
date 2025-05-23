#!/usr/bin/env swift
import Foundation


// Function to run a command line process
func runProcess(executableURL: URL, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    let error = String(data: errorData, encoding: .utf8) ?? ""

    return (process.terminationStatus, output, error)
}

// Helper function to find an executable using 'which' via /usr/bin/env
func findExecutable(named executableName: String) -> URL? {
    let envURL = URL(fileURLWithPath: "/usr/bin/env")

    guard FileManager.default.fileExists(atPath: envURL.path) else {
        print("Error: /usr/bin/env not found. Cannot search for executables.")
        return nil
    }

    do {
        let (status, stdout, stderr) = try runProcess(executableURL: envURL, arguments: ["which", executableName])
        
        if status == 0 {
            let path = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            // Double-check that the path is not empty and the file exists
            if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            } else {
                 print("  'env which \(executableName)' returned invalid path or file not found: '\(path)'")
            }
        } else {
            // Log stderr from 'which' if it failed
            let errorMsg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  'env which \(executableName)' failed (Status: \(status)). \(errorMsg.isEmpty ? "" : "Stderr: \(errorMsg)")")
        }
    } catch {
        print("  Error running '/usr/bin/env which \(executableName)': \(error)")
    }

    print("Error: Could not find executable '\(executableName)'. Please ensure it is installed and in your PATH.")
    return nil
}

// --- Main Script Logic ---

// 1. Check Arguments
guard CommandLine.arguments.count == 2 else {
    print("Usage: \(CommandLine.arguments[0]) <input_file.mkv> [-l <language_code>]")
    exit(1)
}
let inputFilePath = CommandLine.arguments[1]
let inputFileURL = URL(fileURLWithPath: inputFilePath)

// Check if input file exists
guard FileManager.default.fileExists(atPath: inputFilePath) else {
    print("Error: Input file not found at '\(inputFilePath)'")
    exit(1)
}

print("Resolving dependencies...")
// Find ffmpeg and ffprobe dynamically
guard let ffmpegURL = findExecutable(named: "ffmpeg") else {
    // Error message printed within findExecutable
    exit(1)
}
print("  ffmpeg:  \(ffmpegURL.path())")

guard let ffprobeURL = findExecutable(named: "ffprobe") else {
    // Error message printed within findExecutable
    exit(1)
}
print("  ffprobe: \(ffprobeURL.path())")