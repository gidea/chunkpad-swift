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
        case rtf
        case txt
        case markdown
        case pptx
        case unknown

        var displayName: String {
            switch self {
            case .pdf: return "PDF"
            case .docx: return "Word Document"
            case .rtf: return "Rich Text"
            case .txt: return "Plain Text"
            case .markdown: return "Markdown"
            case .pptx: return "PowerPoint"
            case .unknown: return "Unknown"
            }
        }

        var icon: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .docx: return "doc.fill"
            case .rtf: return "doc.text"
            case .txt: return "doc.plaintext"
            case .markdown: return "text.document"
            case .pptx: return "rectangle.on.rectangle.angled"
            case .unknown: return "doc.questionmark"
            }
        }

        init(fromExtension ext: String) {
            switch ext.lowercased() {
            case "pdf": self = .pdf
            case "docx", "doc": self = .docx
            case "rtf": self = .rtf
            case "txt", "text": self = .txt
            case "md", "markdown": self = .markdown
            case "pptx", "ppt": self = .pptx
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
