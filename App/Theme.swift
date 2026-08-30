import SwiftUI

struct Theme {
    static let red = Color(red: 0xB9/255, green: 0x1C/255, blue: 0x1C/255)
    static let gold = Color(red: 0xB4/255, green: 0x53/255, blue: 0x09/255)
    static let green = Color(red: 0x15/255, green: 0x80/255, blue: 0x3D/255)
    static let black = Color(red: 0x1F/255, green: 0x29/255, blue: 0x37/255)

    static let appBackground = Color(red: 0xE2/255.0, green: 0xE8/255.0, blue: 0xF0/255.0)
    static let appText = Color(red: 0x1E/255.0, green: 0x3A/255.0, blue: 0x8A/255.0)
    static let activeBlue = Color(red: 0x25/255.0, green: 0x63/255.0, blue: 0xEB/255.0)
    static let lightBorder = Color(red: 0xDB/255.0, green: 0xEA/255.0, blue: 0xFE/255.0)
    static let secondaryText = Color(red: 0x1D/255.0, green: 0x4E/255.0, blue: 0xD8/255.0)
    static let white = Color.white
}

extension PreviewGlyphColor {
    var suColor: Color {
        switch self {
        case .red: return Theme.red
        case .gold: return Theme.gold
        case .green: return Theme.green
        case .black: return Theme.black
        }
    }
}

extension Font {
    static func ananse(size: CGFloat, style: PreviewGlyphStyle = .classic) -> Font {
        let name = AnanseAppFont.register(resource: style.fontResource)
        return .custom(name, size: size)
    }
}