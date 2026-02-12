import Foundation

struct IndexedDocument: Identifiable, Codable, Sendable {
    let id: String
    let fileName: String
    let filePath: String
    let documentType: DocumentType
    let chunkCount: Int
    let indexedAt: Date
    let fileSize: Int64

    enum DocumentType: String, Codable, Sendable, CaseIterable {
        case pdf
        case docx
        case doc
        case rtf
        case odt
        case txt
        case markdown
        case unknown

        var displayName: String {
            switch self {
            case .pdf: return "PDF"
            case .docx: return "Word Document"
            case .doc: return "Word Document (Legacy)"
            case .rtf: return "Rich Text"
            case .odt: return "OpenDocument Text"
            case .txt: return "Plain Text"
            case .markdown: return "Markdown"
            case .unknown: return "Unknown"
            }
        }

        var icon: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .docx, .doc: return "doc.fill"
            case .rtf: return "doc.text"
            case .odt: return "doc.text"
            case .txt: return "doc.plaintext"
            case .markdown: return "text.document"
            case .unknown: return "doc.questionmark"
            }
        }

        /// The set of file extensions supported in this implementation.
        static let supportedExtensions: Set<String> = [
            "pdf", "docx", "doc", "rtf", "odt", "txt", "text", "md", "markdown"
        ]

        init(fromExtension ext: String) {
            switch ext.lowercased() {
            case "pdf": self = .pdf
            case "docx": self = .docx
            case "doc": self = .doc
            case "rtf": self = .rtf
            case "odt": self = .odt
            case "txt", "text": self = .txt
            case "md", "markdown": self = .markdown
            default: self = .unknown
            }
        }
    }

    init(
        id: String = UUID().uuidString,
        fileName: String,
        filePath: String,
        documentType: DocumentType,
        chunkCount: Int = 0,
        indexedAt: Date = .now,
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.documentType = documentType
        self.chunkCount = chunkCount
        self.indexedAt = indexedAt
        self.fileSize = fileSize
    }
}
