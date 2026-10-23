import AppKit
import PDFKit
import UniformTypeIdentifiers

/// One file in the user's repository, with the text Clipmorph could read from it.
struct RepositoryDocument: Identifiable {
    var url: URL
    var text: String

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isReadable: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Rough token count (about 4 characters per token), for size hints in Settings.
    var estimatedTokens: Int { text.count / 4 }
}

/// Reference documents (product sheets, company info, tone of voice) kept in a folder in
/// Application Support and sent along with recipes that use the repository.
enum Repository {
    static let supportedExtensions = ["pdf", "docx", "rtf", "txt", "md", "markdown", "csv", "json", "html", "htm", "xml", "yaml", "yml"]

    static var folderURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Clipmorph/Repository", isDirectory: true)
    }

    @discardableResult
    static func ensureFolder() -> URL {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    static func load() -> [RepositoryDocument] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { RepositoryDocument(url: $0, text: extractText(from: $0)) }
    }

    /// Copies files into the repository, replacing any with the same name.
    static func add(_ urls: [URL]) throws {
        let folder = ensureFolder()
        for url in urls {
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
        }
    }

    /// Moves a document to the Trash, so it can still be recovered.
    static func remove(_ document: RepositoryDocument) throws {
        try FileManager.default.trashItem(at: document.url, resultingItemURL: nil)
    }

    static func extractText(from url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFDocument(url: url)?.string ?? ""
        case "docx":
            return attributedText(url, type: .officeOpenXML)
        case "rtf":
            return attributedText(url, type: .rtf)
        case let ext where supportedExtensions.contains(ext):
            return (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                ?? ""
        default:
            return ""
        }
    }

    private static func attributedText(_ url: URL, type: NSAttributedString.DocumentType) -> String {
        let string = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        return string?.string ?? ""
    }

    static var contentTypes: [UTType] {
        supportedExtensions.compactMap { UTType(filenameExtension: $0) }
    }
}
