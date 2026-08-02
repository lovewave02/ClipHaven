import AppKit
import Foundation

enum ClipPayload: Codable, Equatable, Sendable {
    case text(String)
    case image(Data)

    enum CodingKeys: String, CodingKey { case kind, value }
    enum Kind: String, Codable { case text, image }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try container.decode(String.self, forKey: .value))
        case .image: self = .image(try container.decode(Data.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .image(value):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    var preview: String {
        switch self {
        case let .text(value): return value.replacingOccurrences(of: "\\n", with: " ").prefix(120).description
        case .image: return "Image"
        }
    }
}

struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var payload: ClipPayload
    var capturedAt: Date
    var isPinned: Bool
    var sourceBundleIdentifier: String?

    init(id: UUID = UUID(), payload: ClipPayload, capturedAt: Date = .now, isPinned: Bool = false, sourceBundleIdentifier: String? = nil) {
        self.id = id
        self.payload = payload
        self.capturedAt = capturedAt
        self.isPinned = isPinned
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}
