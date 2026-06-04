import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum ViewMode: Int {
    case split
    case tabbed
    case fullscreen
}

enum Density: Int {
    case compact
    case comfortable
    case spacious

    var itemSide: CGFloat {
        switch self {
        case .compact: 118
        case .comfortable: 162
        case .spacious: 220
        }
    }

    var next: Density {
        switch self {
        case .compact: .comfortable
        case .comfortable: .spacious
        case .spacious: .compact
        }
    }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        case .spacious: "Spacious"
        }
    }
}

enum KeyCode {
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let space: UInt16 = 49
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let escape: UInt16 = 53
    static let return_: UInt16 = 36
}

struct ImageAsset: Hashable {
    let url: URL
    let name: String
    let byteCount: Int64
}

struct ModelFolder: Hashable {
    let url: URL
    let name: String
    let profileURL: URL?
    let images: [ImageAsset]
}
