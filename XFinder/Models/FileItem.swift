import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case german

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .german: "Deutsch"
        }
    }
}

enum NewFileKind: String, CaseIterable, Identifiable, Sendable {
    case text
    case richText
    case word
    case excel
    case powerpoint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text Document (.txt)"
        case .richText: "Rich Text Document (.rtf)"
        case .word: "Word Document (.docx)"
        case .excel: "Excel Workbook (.xlsx)"
        case .powerpoint: "PowerPoint Presentation (.pptx)"
        }
    }

    var baseName: String {
        switch self {
        case .text: "New Text Document"
        case .richText: "New Rich Text Document"
        case .word: "New Word Document"
        case .excel: "New Excel Workbook"
        case .powerpoint: "New PowerPoint Presentation"
        }
    }

    var pathExtension: String {
        switch self {
        case .text: "txt"
        case .richText: "rtf"
        case .word: "docx"
        case .excel: "xlsx"
        case .powerpoint: "pptx"
        }
    }
}

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let size: Int64?
    let modificationDate: Date?
    let kind: String

    var id: URL { url.standardizedFileURL }
    var canNavigateInto: Bool { isDirectory && !isPackage }

    var formattedSize: String {
        guard !isDirectory, let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedModificationDate: String {
        guard let modificationDate else { return "—" }
        return modificationDate.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SidebarLocation: Identifiable, Hashable, Sendable {
    let title: String
    let systemImage: String
    let url: URL
    var isCustom = false
    var opensExternally = false

    var id: URL { url.standardizedFileURL }
}
