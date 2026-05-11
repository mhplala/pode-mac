import Foundation

struct WhisperLine: Hashable {
    let t: Double
    let text: String
    let speaker: String?
}

struct WhisperResult {
    let lines: [WhisperLine]
    let language: String?
    let text: String
}

enum WhisperError: Error, LocalizedError {
    case missingKey
    case http(Int, String)
    case audioFetch(String)
    case noBody

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your OpenAI API key in Settings."
        case .http(let code, let body): return "Whisper failed (\(code)): \(body.prefix(200))"
        case .audioFetch(let m): return "Audio fetch failed: \(m)"
        case .noBody: return "Empty response."
        }
    }
}

enum WhisperService {
    private struct VerboseResponse: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        let text: String
        let language: String?
        let segments: [Segment]?
    }

    static func transcribe(audioFileURL: URL, apiKey: String, model: String = "whisper-1",
                           language: String? = nil) async throws -> WhisperResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw WhisperError.missingKey }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Stream the multipart body to a temp file instead of building it
        // in memory. Otherwise we'd hold (audio bytes) + (full multipart
        // body bytes) simultaneously — for a 90-minute episode that's ~140 MB
        // each, easily 300 MB resident, plus the system's network buffer
        // copy. Streaming from disk keeps memory at a few KB.
        let tempBodyURL = try buildMultipartBodyFile(
            boundary: boundary,
            model: model,
            language: language,
            audioFileURL: audioFileURL
        )
        defer { try? FileManager.default.removeItem(at: tempBodyURL) }

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: tempBodyURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw WhisperError.http(http.statusCode, bodyText)
        }

        let decoded = try JSONDecoder().decode(VerboseResponse.self, from: data)
        let segments = decoded.segments ?? []
        let speakerBreak: Double = 4.0
        var lastEnd: Double = -.infinity
        let lines: [WhisperLine] = segments.map { seg in
            let speaker: String? = (seg.start - lastEnd > speakerBreak) ? "Speaker" : nil
            lastEnd = seg.end
            return WhisperLine(
                t: floor(seg.start),
                text: seg.text.trimmingCharacters(in: .whitespacesAndNewlines),
                speaker: speaker
            )
        }
        return WhisperResult(lines: lines, language: decoded.language, text: decoded.text)
    }

    /// Streams parts directly to a temp file. The audio file is copied chunk
    /// by chunk via `FileHandle`, never held whole in memory.
    private static func buildMultipartBodyFile(
        boundary: String,
        model: String,
        language: String?,
        audioFileURL: URL
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let bodyURL = tmpDir.appendingPathComponent("whisper-\(UUID().uuidString).body")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: bodyURL)
        defer { try? out.close() }

        out.write(makePart(boundary: boundary, name: "model", value: model))
        out.write(makePart(boundary: boundary, name: "response_format", value: "verbose_json"))
        out.write(makePart(boundary: boundary, name: "timestamp_granularities[]", value: "segment"))
        if let language {
            out.write(makePart(boundary: boundary, name: "language", value: language))
        }

        // File-part header (no body bytes yet)
        let filename = audioFileURL.lastPathComponent
        var fileHeader = Data()
        fileHeader.append(Data("--\(boundary)\r\n".utf8))
        fileHeader.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        fileHeader.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        out.write(fileHeader)

        // Pipe audio file into the body in 1 MB chunks
        let input = try FileHandle(forReadingFrom: audioFileURL)
        defer { try? input.close() }
        let chunkSize = 1 * 1024 * 1024
        while true {
            let chunk = input.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            out.write(chunk)
        }

        // Trailing CRLF + closing boundary
        out.write(Data("\r\n".utf8))
        out.write(Data("--\(boundary)--\r\n".utf8))
        return bodyURL
    }

    private static func makePart(boundary: String, name: String, value: String) -> Data {
        var part = Data()
        part.append(Data("--\(boundary)\r\n".utf8))
        part.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        part.append(Data(value.utf8))
        part.append(Data("\r\n".utf8))
        return part
    }

}

/// URLSessionDownloadTask with real per-chunk progress + Task cancellation.
/// `URLSession.download(from:)` only fires progress at completion, which made
/// the progress bar useless. We use the delegate API instead.
enum AudioDownloader {
    static func download(
        from url: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> URL {
        let handle = _DownloadHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let delegate = _DownloadDelegate(
                    onProgress: progress,
                    onComplete: { result in
                        switch result {
                        case .success(let dest): cont.resume(returning: dest)
                        case .failure(let err):  cont.resume(throwing: err)
                        }
                    }
                )
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 60
                config.timeoutIntervalForResource = 60 * 60   // 1h hard cap
                let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                var req = URLRequest(url: url)
                req.setValue("Pode/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
                let task = session.downloadTask(with: req)
                handle.task = task
                task.resume()
            }
        } onCancel: {
            handle.cancel()
        }
    }
}

private final class _DownloadHandle: @unchecked Sendable {
    var task: URLSessionDownloadTask?
    func cancel() { task?.cancel() }
}

private final class _DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Int64, Int64) -> Void
    let onComplete: @Sendable (Result<URL, Error>) -> Void
    private var done = false
    private let lock = NSLock()

    init(
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onComplete: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    private func deliver(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        onComplete(result)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file at `location` is purged the moment this method returns,
        // so we MUST move it synchronously here.
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Pode/Audio", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let originalExt = downloadTask.originalRequest?.url?.pathExtension ?? ""
            let ext = originalExt.isEmpty ? "mp3" : originalExt
            let dest = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.moveItem(at: location, to: dest)
            deliver(.success(dest))
        } catch {
            deliver(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error else { return }   // success path runs above
        deliver(.failure(error))
        session.invalidateAndCancel()
    }
}
