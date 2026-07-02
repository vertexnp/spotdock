import Foundation

enum FFmpegError: Error, LocalizedError {
    case ffmpegNotFound
    case processError(exitCode: Int32, message: String)
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg executable could not be found. Please ensure it is installed (e.g., via Homebrew)."
        case .processError(let code, let msg):
            return "FFmpeg process failed with exit status \(code). Details: \(msg)"
        case .invalidInput:
            return "The input or output file URL is invalid."
        }
    }
}

/// A thread-safe Swift utility actor that executes FFmpeg CLI operations asynchronously.
actor FFmpegUtility {
    
    /// Common paths where Homebrew or system installs place FFmpeg on macOS
    private static let searchPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    
    /// Finds the FFmpeg executable dynamically on the system
    private static func findFFmpegPath() -> String? {
        let fileManager = FileManager.default
        for path in searchPaths {
            if fileManager.fileExists(atPath: path) && fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    /// Run an asynchronous FFmpeg operation using macOS system Process
    private static func runFFmpeg(arguments: [String]) async throws {
        guard let ffmpegPath = findFFmpegPath() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { completedProcess in
                let status = completedProcess.terminationStatus
                if status == 0 {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown FFmpeg error"
                    continuation.resume(throwing: FFmpegError.processError(exitCode: status, message: errorMessage))
                }
            }
        }
    }
    
    // MARK: - Video Functions (Compression & Format Conversion)
    
    /// Compresses a video file using H.264 codec
    /// - Parameters:
    ///   - inputURL: File URL of the input video
    ///   - outputURL: File URL where the output video will be written
    ///   - crf: Constant Rate Factor quality value (18-28 range; default 23)
    ///   - preset: Compression rate preset (e.g. "fast", "medium", "slow")
    /// Compresses a video file using H.264 codec
    /// - Parameters:
    ///   - inputURL: File URL of the input video
    ///   - outputURL: File URL where the output video will be written
    ///   - quality: Compression quality percentage (10-100; default 80)
    ///   - preset: Compression rate preset (e.g. "fast", "medium", "slow")
    static func compressVideo(inputURL: URL, outputURL: URL, quality: Int = 80, preset: String = "medium") async throws {
        guard inputURL.isFileURL, outputURL.isFileURL else {
            throw FFmpegError.invalidInput
        }
        
        // Map quality percentage (10-100) to CRF (18-32, where 18 is best quality)
        let crf = 18 + ((100 - quality) * 14 / 90)
        
        let arguments = [
            "-y",
            "-i", inputURL.path,
            "-vcodec", "libx264",
            "-crf", "\(crf)",
            "-preset", preset,
            "-acodec", "aac",
            "-b:a", "128k",
            outputURL.path
        ]
        
        try await runFFmpeg(arguments: arguments)
    }
    
    /// Converts a video's container format / extension (fast copy copy streams)
    /// - Parameters:
    ///   - inputURL: File URL of the input video
    ///   - outputURL: File URL where the output video will be written (with target extension)
    static func convertVideoFormat(inputURL: URL, outputURL: URL) async throws {
        guard inputURL.isFileURL, outputURL.isFileURL else {
            throw FFmpegError.invalidInput
        }
        
        let arguments = [
            "-y",
            "-i", inputURL.path,
            "-c:v", "copy",
            "-c:a", "copy",
            outputURL.path
        ]
        
        try await runFFmpeg(arguments: arguments)
    }
    
    // MARK: - Image Functions (Compression & Format Conversion)
    
    /// Compresses an image by lowering the quality factor
    /// - Parameters:
    ///   - inputURL: File URL of the input image
    ///   - outputURL: File URL where the output image will be written
    ///   - quality: Compression quality factor (1-100; default 80)
    static func compressImage(inputURL: URL, outputURL: URL, quality: Int = 80) async throws {
        guard inputURL.isFileURL, outputURL.isFileURL else {
            throw FFmpegError.invalidInput
        }
        
        let ext = outputURL.pathExtension.lowercased()
        var arguments = [
            "-y",
            "-i", inputURL.path,
            "-update", "1"
        ]
        
        if ext == "webp" {
            // WebP quality parameter ranges from 0 to 100 (where 100 is best)
            arguments.append(contentsOf: ["-q:v", "\(quality)"])
        } else if ext == "png" {
            if quality < 100 {
                // Apply lossy palette quantization for PNG to dramatically reduce size (Floyd-Steinberg dithered 256 color palette)
                arguments.append(contentsOf: [
                    "-vf", "split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
                ])
            } else {
                arguments.append(contentsOf: ["-compression_level", "9"])
            }
        } else {
            // JPEG and others use quality scale (1 to 31 where 1 is best and 31 is worst)
            let qscale = 1 + ((100 - quality) * 30 / 100)
            arguments.append(contentsOf: ["-q:v", "\(qscale)"])
        }
        
        arguments.append(outputURL.path)
        
        try await runFFmpeg(arguments: arguments)
    }
    
    /// Converts an image to a different extension / format
    /// - Parameters:
    ///   - inputURL: File URL of the input image
    ///   - outputURL: File URL where the output image will be written (with target extension)
    static func convertImageFormat(inputURL: URL, outputURL: URL) async throws {
        guard inputURL.isFileURL, outputURL.isFileURL else {
            throw FFmpegError.invalidInput
        }
        
        let arguments = [
            "-y",
            "-i", inputURL.path,
            "-update", "1",
            outputURL.path
        ]
        
        try await runFFmpeg(arguments: arguments)
    }
}
