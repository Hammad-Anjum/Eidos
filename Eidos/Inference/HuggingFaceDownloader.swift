import Foundation

enum HuggingFaceError: Error, LocalizedError {
    case httpError(Int, String)
    case missingRequiredFile(String)
    case invalidResponse
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let path): "HTTP \(code) for \(path)"
        case .missingRequiredFile(let name): "Required file missing: \(name)"
        case .invalidResponse: "Invalid HTTP response"
        case .invalidURL(let raw): "Invalid HuggingFace URL: \(raw)"
        }
    }
}

/// Downloads a HuggingFace model repository to a local directory using a
/// hardened `URLSession` that:
///   - rejects any TLS handshake whose host isn't on the HuggingFace
///     allowlist (`SecureHTTPSSession.allowedHosts`)
///   - validates the system trust chain
///   - optionally pins the leaf cert's SPKI (off by default; populate
///     `SecureHTTPSSession.pinnedSPKIHashes` to enable)
/// Bypasses the `swift-huggingface` HubClient, which stalls on large
/// LFS shards (reproduced on iOS Simulator and Mac Catalyst as of
/// swift-huggingface 0.9.x).
actor HuggingFaceDownloader {

    struct File: Sendable {
        let name: String
        let required: Bool
    }

    /// Single hardened session used for all probe + download traffic.
    /// Created lazily on first use so a misconfigured allowlist doesn't
    /// fail at app boot. Same session is reused so connection-keep-
    /// alive and HTTP/2 multiplexing work across files.
    private lazy var session: URLSession = SecureHTTPSSession.session()

    /// Files published by `mlx-community/gemma-4-*` repos. Same set for E2B/E4B.
    static let gemma4Files: [File] = [
        File(name: "config.json",                 required: true),
        File(name: "model.safetensors.index.json", required: true),
        File(name: "tokenizer.json",              required: true),
        File(name: "tokenizer_config.json",       required: true),
        File(name: "model.safetensors",           required: true),
        File(name: "generation_config.json",      required: false),
        File(name: "chat_template.jinja",         required: false),
        File(name: "processor_config.json",       required: false),
    ]

    /// Downloads `files` from `huggingface.co/<repoID>/resolve/main/` into
    /// `directory`. Resumes by skipping files already at their full size.
    /// Progress is fraction of total bytes (weighted by file size).
    func download(
        repoID: String,
        files: [File] = gemma4Files,
        to directory: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if DEBUG
        print("[HF] starting download for repo=\(repoID) → \(directory.path)")
        #endif

        // Probe each file with a 1-byte Range GET to get expected size.
        // HEAD requests on HuggingFace's 307 redirect chain are flaky in
        // URLSession; a Range GET is more reliable and still negligible traffic.
        var sizes: [String: Int64] = [:]
        for file in files {
            let url = try Self.resolveURL(repoID: repoID, path: file.name)
            let size = try await probeSize(url: url)
            #if DEBUG
            print("[HF] probe \(file.name): size=\(size)")
            #endif
            if size < 0 {
                if file.required {
                    #if DEBUG
                    print("[HF] required file missing: \(file.name) @ \(url.absoluteString)")
                    #endif
                    throw HuggingFaceError.missingRequiredFile(file.name)
                }
                continue
            }
            sizes[file.name] = size
        }
        let total = sizes.values.reduce(0, +)
        #if DEBUG
        print("[HF] total planned bytes: \(total)")
        #endif

        // Download small files first, large weight shard last.
        let ordered = files
            .filter { sizes[$0.name] != nil }
            .sorted { (sizes[$0.name] ?? 0) < (sizes[$1.name] ?? 0) }

        var completed: Int64 = 0
        for file in ordered {
            let size = sizes[file.name] ?? 0
            let destination = directory.appendingPathComponent(file.name)

            // Skip if already fully downloaded.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: destination.path),
               let existingSize = attrs[.size] as? Int64,
               existingSize == size {
                completed += size
                if total > 0 { onProgress?(Double(completed) / Double(total)) }
                continue
            }

            #if DEBUG
            print("[HF] downloading \(file.name) (\(size) bytes) → \(destination.path)")
            #endif
            let baseBefore = completed
            try await downloadOne(
                url: try Self.resolveURL(repoID: repoID, path: file.name),
                destination: destination,
                onProgress: { fileFraction in
                    let current = baseBefore + Int64(Double(size) * fileFraction)
                    if total > 0 { onProgress?(Double(current) / Double(total)) }
                }
            )
            completed += size
            // Post a progress tick after each file finishes so small
            // config files don't vanish between per-byte updates.
            if total > 0 { onProgress?(Double(completed) / Double(total)) }
            #if DEBUG
            print("[HF] done \(file.name). Total: \(completed)/\(total)")
            #endif
        }

        onProgress?(1.0)
    }

    // MARK: - Internals

    private static func resolveURL(repoID: String, path: String) throws -> URL {
        let raw = "https://huggingface.co/\(repoID)/resolve/main/\(path)"
        guard let url = URL(string: raw) else {
            throw HuggingFaceError.invalidURL(raw)
        }
        return url
    }

    /// Returns the total byte size of the resource at `url`, or `-1` if
    /// missing (404). We use a 1-byte `Range: bytes=0-0` GET — HuggingFace
    /// redirects make HEAD requests flaky in URLSession, but a Range GET
    /// returns `206 Partial Content` with a `Content-Range: bytes 0-0/TOTAL`
    /// header that we can parse deterministically.
    private func probeSize(url: URL) async throws -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HuggingFaceError.invalidResponse
        }
        #if DEBUG
        print("[HF] probe \(url.lastPathComponent) → \(http.statusCode), CL=\(http.expectedContentLength), CR=\(http.value(forHTTPHeaderField: "Content-Range") ?? "-")")
        #endif

        switch http.statusCode {
        case 404:
            return -1
        case 200:
            // Server returned the whole body despite the Range request —
            // fall back to `expectedContentLength`.
            return http.expectedContentLength
        case 206:
            // Parse `Content-Range: bytes 0-0/12345` — the part after `/`.
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let slash = range.lastIndex(of: "/") {
                let totalStr = range[range.index(after: slash)...]
                return Int64(totalStr) ?? http.expectedContentLength
            }
            return http.expectedContentLength
        default:
            throw HuggingFaceError.httpError(http.statusCode, url.path)
        }
    }

    private func downloadOne(
        url: URL,
        destination: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        // We poll `task.progress.fractionCompleted` instead of relying on
        // `URLSessionDownloadDelegate.didWriteData` callbacks — the delegate
        // method is unreliable on the iOS Simulator and certain HTTP/2
        // streamed responses, but `Progress` is always updated natively.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let session = session
            let task = session.downloadTask(with: url) { tempURL, response, error in
                if let error {
                    cont.resume(throwing: error); return
                }
                guard let tempURL, let http = response as? HTTPURLResponse else {
                    cont.resume(throwing: HuggingFaceError.invalidResponse); return
                }
                guard (200..<300).contains(http.statusCode) else {
                    cont.resume(throwing: HuggingFaceError.httpError(http.statusCode, url.path)); return
                }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    onProgress(1.0)  // final tick
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
            task.resume()

            // Poll the task's native Progress object every 300ms.
            // Stops automatically when the task finishes (Progress becomes 1.0).
            let progress = task.progress
            Task.detached {
                while task.state == .running {
                    let fraction = progress.fractionCompleted
                    if fraction > 0 { onProgress(fraction) }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
        }
    }
}
