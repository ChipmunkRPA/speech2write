import Foundation

/// Artifact-validation helpers for locally cached Hugging Face model files.
///
/// The instance download machinery this type used to carry was removed with the
/// retired Nemotron / external-CoreML engines; the surviving statics are the
/// install-completeness and markup-corruption checks used by the live Parakeet
/// engines (SettingsStore.parakeetModelsExist / parakeetRealtimeModelsExist).
enum HuggingFaceModelDownloader {
    struct ModelItem {
        let path: String
        let isDirectory: Bool
    }

    static func artifactsAreComplete(root: URL, items: [ModelItem]) -> Bool {
        items.allSatisfy { item in
            Self.artifactIsComplete(
                at: root.appendingPathComponent(item.path, isDirectory: item.isDirectory),
                isDirectory: item.isDirectory
            )
        }
    }

    static func artifactIsComplete(at url: URL, isDirectory: Bool) -> Bool {
        guard isDirectory else { return self.fileHasContents(at: url) }

        if url.pathExtension == "mlpackage" {
            let manifestURL = url.appendingPathComponent("Manifest.json")
            guard
                Self.fileHasContents(at: manifestURL),
                let data = try? Data(contentsOf: manifestURL),
                let manifestObject = try? JSONSerialization.jsonObject(with: data),
                let manifest = manifestObject as? [String: Any],
                let entries = manifest["itemInfoEntries"] as? [String: [String: Any]],
                !entries.isEmpty
            else {
                return false
            }

            return entries.values.allSatisfy { entry in
                guard let relativePath = entry["path"] as? String else { return false }
                let artifact = url
                    .appendingPathComponent("Data", isDirectory: true)
                    .appendingPathComponent(relativePath)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: artifact.path, isDirectory: &isDirectory) else {
                    return false
                }
                return Self.artifactIsComplete(at: artifact, isDirectory: isDirectory.boolValue)
            }
        }
        if url.pathExtension == "mlmodelc" {
            // `model.mil` is optional in valid compiled bundles (the Flash preprocessor ships
            // without it), so installation truth comes from compiled metadata plus weights.
            return self.fileHasContents(at: url.appendingPathComponent("coremldata.bin"))
                && self.fileHasContents(at: url.appendingPathComponent("metadata.json"))
                && self.fileHasContents(
                    at: url
                        .appendingPathComponent("weights", isDirectory: true)
                        .appendingPathComponent("weight.bin")
                )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        for case let fileURL as URL in enumerator where Self.fileHasContents(at: fileURL) {
            return true
        }
        return false
    }

    private static func fileHasContents(at url: URL) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let type = attributes[.type] as? FileAttributeType,
            type == .typeRegular,
            let size = attributes[.size] as? NSNumber
        else {
            return false
        }
        return size.int64Value > 0 && !Self.cachedFileIsMarkup(at: url)
    }

    // MARK: - Content Validation

    /// Validates a freshly-downloaded artifact before it is persisted as a model file.
    ///
    /// A network proxy / secure web gateway can return an HTML (or XML) block page with
    /// HTTP 200 in place of the real file. Persisting that markup (e.g. as `coremldata.bin`)
    /// permanently caches a corrupt model. We reject any payload that looks like HTML/XML
    /// markup — by its `Content-Type` or by its leading bytes — since no model artifact
    /// (CoreML binary, JSON vocab, `.mil`) is a markup document. See issue #353.
    static func validateDownloadedFile(at fileURL: URL, response: URLResponse?, relativePath: String) throws {
        if let expectedBytes = response?.expectedContentLength, expectedBytes > 0 {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard
                let actualBytes = attributes[.size] as? NSNumber,
                actualBytes.int64Value == expectedBytes
            else {
                throw NSError(
                    domain: "HF",
                    code: -5,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Could not download \(relativePath): the received file size did not match the server response.",
                    ]
                )
            }
        }

        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")
        {
            let lowered = contentType.lowercased()
            if lowered.contains("text/html") || lowered.contains("text/xml") || lowered.contains("application/xml") {
                throw Self.invalidContentError(
                    relativePath: relativePath,
                    detail: "the server returned a markup page (Content-Type: \(contentType))"
                )
            }
        }

        // Sniff the leading bytes in case markup was returned without a markup Content-Type.
        // Read a small prefix only — model files can be gigabytes.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 512)) ?? Data()
        if Self.looksLikeHTML(prefix) {
            throw Self.invalidContentError(
                relativePath: relativePath,
                detail: "the downloaded file is an HTML/markup document, not the expected model data"
            )
        }
    }

    /// Returns `true` if a file already on disk is an HTML/markup payload rather than real
    /// model data — a corrupt artifact cached before download-time validation existed (#353).
    ///
    /// This is the cached-file analog of `validateDownloadedFile`'s byte-sniff: it reuses the
    /// same `looksLikeHTML` check on a small leading prefix (model files can be gigabytes, so
    /// only 512 bytes are read). There is no `URLResponse` for a cached file, so only the
    /// content is inspected, not a `Content-Type`. Returns `false` (treat as valid) on any
    /// read error, so an unreadable file is never deleted on uncertainty.
    static func cachedFileIsMarkup(at fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 512)) ?? Data()
        return Self.looksLikeHTML(prefix)
    }

    /// Returns `true` if any cached payload under `relativePaths` (each resolved against `root`)
    /// is an HTML/markup document rather than real model data — the cached-*tree* analog of
    /// `cachedFileIsMarkup`, intended for a provider preflight to call before trusting a present
    /// cache and skipping the downloader. The downloader itself already re-validates each file via
    /// `needsDownload`, but a preflight that returns on file-existence alone never reaches it, so a
    /// corrupt-but-present cache would slip through (see #353).
    ///
    /// Each relative path may be a regular file or a directory (e.g. a `.mlpackage` bundle).
    /// Directories are scanned recursively and every regular file inside is byte-sniffed with
    /// `cachedFileIsMarkup`, reusing the single `looksLikeHTML` detector — there is no second
    /// markup heuristic. Conservative on uncertainty, mirroring `cachedFileIsMarkup`: a path that
    /// does not exist, a file that cannot be read, or a directory that cannot be enumerated is
    /// skipped (treated as non-markup), so a valid cache is never reported corrupt. An empty
    /// required directory therefore yields `false` here — its incompleteness is the existence
    /// check's concern, not this markup check's.
    static func cachedPayloadContainsMarkup(root: URL, relativePaths: [String]) -> Bool {
        let fileManager = FileManager.default
        for relativePath in relativePaths {
            let url = root.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                for case let fileURL as URL in enumerator {
                    let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                    guard isRegularFile else { continue }
                    if Self.cachedFileIsMarkup(at: fileURL) {
                        return true
                    }
                }
            } else if Self.cachedFileIsMarkup(at: url) {
                return true
            }
        }
        return false
    }

    /// Returns `true` if `data` begins with an HTML / XML markup marker, ignoring a leading
    /// UTF-8 BOM and ASCII whitespace.
    ///
    /// No artifact this downloader fetches legitimately begins with `<`: CoreML compiled
    /// `.mlmodelc` / `.mlpackage` payloads are binary (`coremldata.bin`, `weights/weight.bin`,
    /// `model.mlmodel` protobuf) or JSON (`metadata.json`, `Manifest.json`) starting with
    /// `{` / `[`; the MIL program text (`model.mil`) starts with `program`; the vocab JSON
    /// starts with `{`; and `tokenizer.model` is a SentencePiece binary. So any payload that,
    /// after BOM + whitespace stripping, starts with `<` followed by a markup-ish byte is a
    /// proxy/block page or a markup document standing in for the real file — reject it. This
    /// catches `<!doctype`, `<html`, `<head>`, `<body>`, `<script>`, `<meta>`, comments
    /// (`<!-- -->`) and XML / `<?xml` declarations, not just the two prefixes we used to
    /// match. See issue #353.
    static func looksLikeHTML(_ data: Data) -> Bool {
        var bytes = [UInt8](data.prefix(512))
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) {
            bytes.removeFirst(3)
        }
        while let first = bytes.first,
              first == 0x20 || first == 0x09 || first == 0x0a || first == 0x0d
        {
            bytes.removeFirst()
        }
        // Must begin with `<` (0x3C)…
        guard bytes.first == 0x3c, bytes.count >= 2 else {
            return false
        }
        // …immediately followed by a markup-ish byte: an ASCII letter (a tag such as
        // `<html`), `!` (0x21 — `<!doctype`, `<!--`), `?` (0x3F — `<?xml`), or `/` (0x2F —
        // a stray closing tag). Requiring this second byte avoids over-rejecting a
        // hypothetical text artifact that merely contains a stray `<` not followed by markup.
        let second = bytes[1]
        let isAsciiLetter = (second >= 0x41 && second <= 0x5a) || (second >= 0x61 && second <= 0x7a)
        return isAsciiLetter || second == 0x21 || second == 0x3f || second == 0x2f
    }

    private static func invalidContentError(relativePath: String, detail: String) -> NSError {
        NSError(domain: "HF", code: -3, userInfo: [
            NSLocalizedDescriptionKey:
                "Could not download \(relativePath): \(detail). A network proxy or firewall may be blocking model downloads.",
        ])
    }
}
