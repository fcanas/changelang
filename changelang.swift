#!/usr/bin/env swift
import Foundation


// Run a command line process synchronously
func runProcess(executableURL: URL, arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    process.standardInput = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    let error = String(data: errorData, encoding: .utf8) ?? ""

    return (process.terminationStatus, output, error)
}

// Find an executable using `/usr/bin/env which`
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
            if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            } else {
                 print("  'env which \(executableName)' returned invalid path or file not found: '\(path)'")
            }
        } else {
            let errorMsg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  'env which \(executableName)' failed (Status: \(status)). \(errorMsg.isEmpty ? "" : "Stderr: \(errorMsg)")")
        }
    } catch {
        print("  Error running '/usr/bin/env which \(executableName)': \(error)")
    }

    print("Error: Could not find executable '\(executableName)'. Please ensure it is installed and in your PATH.")
    return nil
}

// MARK: - FFProbe Data Structures

struct FFProbeStream: Codable {
    let index: Int // Absolute stream index in the file
    let codec_name: String?
    let codec_type: String?
    let sample_fmt: String?
    let sample_rate: String?
    let channel_layout: String?
    let channels: Int?
    let tags: StreamTags?
    let disposition: StreamDisposition?

    struct StreamTags: Codable {
        let language: String?
    }

    struct StreamDisposition: Codable {
        let isDefaultTrack: Int?

        enum CodingKeys: String, CodingKey {
            case isDefaultTrack = "default"
        }
    }

    var language: String {
        return tags?.language ?? "und"
    }

    var isDefault: Bool {
        return disposition?.isDefaultTrack == 1
    }

    var isAudio: Bool { // Though ffprobe -select_streams a should pre-filter
        return codec_type == "audio"
    }
}

struct FFProbeOutput: Codable {
    let streams: [FFProbeStream]
}

// MARK: - Core Logic Functions

func getAudioTracks(filePath: String, ffprobeURL: URL) -> [FFProbeStream]? {
    do {
        let arguments = ["-v", "quiet", "-print_format", "json", "-show_streams", "-select_streams", "a", filePath]
        let (status, stdout, stderr) = try runProcess(executableURL: ffprobeURL, arguments: arguments)

        if status != 0 {
            print("Error: ffprobe failed (Status: \(status)).")
            if !stderr.isEmpty { print("ffprobe stderr: \(stderr)") }
            return nil
        }

        guard let jsonData = stdout.data(using: .utf8) else {
            print("Error: Could not convert ffprobe output to Data.")
            return nil
        }
        
        let decoder = JSONDecoder()
        let ffprobeData = try decoder.decode(FFProbeOutput.self, from: jsonData)
        return ffprobeData.streams // These are already audio streams due to "-select_streams a"
    } catch {
        print("Error processing ffprobe output: \(error)")
        return nil
    }
}

func setDefaultAudioTrack(inputFilePath: String, ffmpegURL: URL, audioTrackIndexToSetAsDefault: Int) -> Bool {
    let inputFileURL = URL(fileURLWithPath: inputFilePath)
    let tempFileName = UUID().uuidString + "." + inputFileURL.pathExtension
    let tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(tempFileName)

    defer {
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    var ffmpegArguments = [
        "-y", // Overwrite output files without asking
        // "-loglevel", "error", // Suppress verbose output, only show errors
        "-i", inputFilePath,
        "-map", "0",         // Copy all streams (video, audio, subtitles, etc.)
        "-c", "copy",        // Copy codecs without re-encoding
        "-disposition:a", "0" // Clear default flag from all audio streams first
    ]

    // Set the new default audio track. `:a:N` refers to the Nth audio stream.
    ffmpegArguments.append("-disposition:a:\(audioTrackIndexToSetAsDefault)")
    ffmpegArguments.append("default")
    
    ffmpegArguments.append(tempFileURL.path)

    do {
        print("Running ffmpeg to set track \(audioTrackIndexToSetAsDefault + 1) as default...")
        print("  ffmpeg \(ffmpegArguments.joined(separator: " "))") // Log the command
        let (status, _, _) = try runProcess(executableURL: ffmpegURL, arguments: ffmpegArguments)

        if status == 0 {
            do {
                _ = try FileManager.default.replaceItemAt(inputFileURL, withItemAt: tempFileURL, backupItemName: nil, options: [])
                print("Successfully updated default audio track in '\(inputFilePath)'.")
                return true
            } catch {
                print("Error: Could not replace original file '\(inputFilePath)' with temporary file '\(tempFileURL.path)'.")
                print("Error details: \(error)")
                return false
            }
        } else {
            print("Error: ffmpeg failed (Status: \(status)).")
            // stderr is already printed above
            return false
        }
    } catch {
        print("Error running ffmpeg: \(error)")
        return false
    }
}


// --- Main Script Logic ---

// 1. Argument Parsing
var inputFilePath: String? = nil
var targetLanguage: String? = nil

if CommandLine.arguments.count == 2 {
    inputFilePath = CommandLine.arguments[1]
} else if CommandLine.arguments.count == 4 && CommandLine.arguments[2] == "-l" {
    inputFilePath = CommandLine.arguments[1]
    targetLanguage = CommandLine.arguments[3].lowercased()
} else {
    print("Usage: \(CommandLine.arguments[0]) <input_file.mkv> [-l <language_code>]")
    exit(1)
}

guard let guardedInputFilePath = inputFilePath else {
    // This case should ideally not be reached due to the logic above
    print("Error: Input file path could not be determined.")
    exit(1)
}
let inputFileURL = URL(fileURLWithPath: guardedInputFilePath)


// 2. Check if input file exists
guard FileManager.default.fileExists(atPath: guardedInputFilePath) else {
    print("Error: Input file not found at '\(guardedInputFilePath)'")
    exit(1)
}

// 3. Find ffmpeg and ffprobe dynamically
print("Resolving dependencies...")
guard let ffmpegURL = findExecutable(named: "ffmpeg") else {
    exit(1) // Error message printed within findExecutable
}
print("  ffmpeg:  \(ffmpegURL.path)")

guard let ffprobeURL = findExecutable(named: "ffprobe") else {
    exit(1) // Error message printed within findExecutable
}
print("  ffprobe: \(ffprobeURL.path)")

// 4. Get Audio Tracks
guard let audioTracks = getAudioTracks(filePath: guardedInputFilePath, ffprobeURL: ffprobeURL) else {
    print("Error: Could not retrieve audio tracks from the file.")
    exit(1)
}

if audioTracks.isEmpty {
    print("No audio tracks found in the file.")
    exit(0)
}

// 5. Mode Handling
if let langCode = targetLanguage {
    // Language code mode
    var foundTrackIndex: Int? = nil
    for (index, track) in audioTracks.enumerated() {
        if track.language.lowercased() == langCode {
            foundTrackIndex = index
            break
        }
    }

    if let trackIdx = foundTrackIndex {
        print("Found audio track with language '\(langCode)' at index \(trackIdx + 1). Setting as default.")
        if setDefaultAudioTrack(inputFilePath: guardedInputFilePath, ffmpegURL: ffmpegURL, audioTrackIndexToSetAsDefault: trackIdx) {
            // Success message printed in setDefaultAudioTrack
        } else {
            print("Failed to set default audio track.")
            exit(1)
        }
    } else {
        print("No audio track found matching language code '\(langCode)'. No changes made.")
        exit(0)
    }
} else {
    // Interactive mode
    print("\nAvailable audio tracks:")
    for (i, track) in audioTracks.enumerated() {
        let displayIndex = i + 1
        let defaultMarker = track.isDefault ? "*" : " "
        let lang = track.language
        let codec = track.codec_name ?? "N/A"
        let sampleRate = track.sample_rate ?? "N/A"
        let layout = track.channel_layout ?? (track.channels != nil ? "\(track.channels!) ch" : "N/A")
        let format = track.sample_fmt ?? ""
        print("[\(displayIndex)] \(defaultMarker) (\(lang)): \(codec), \(sampleRate) Hz, \(layout)\(format.isEmpty ? "" : ", \(format)")")
    }

    print("\nSet default (enter number, or leave blank to cancel): ", terminator: "")
    if let choiceStr = readLine(), !choiceStr.isEmpty {
        if let choiceNum = Int(choiceStr), choiceNum >= 1 && choiceNum <= audioTracks.count {
            let selectedTrackIndex = choiceNum - 1 // 0-indexed
            if setDefaultAudioTrack(inputFilePath: guardedInputFilePath, ffmpegURL: ffmpegURL, audioTrackIndexToSetAsDefault: selectedTrackIndex) {
                 // Success message printed in setDefaultAudioTrack
            } else {
                print("Failed to set default audio track.")
                exit(1)
            }
        } else {
            print("Invalid selection. No changes made.")
            exit(1)
        }
    } else {
        print("No selection made. File not changed.")
        exit(0)
    }
}
