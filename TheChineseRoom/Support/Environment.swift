import SwiftUI
import UIKit
import CoreText

/// Patrick Hand supplies Latin text, Xiaolai supplies CJK text, and the system
/// supplies missing glyphs and other scripts. SF Symbols keep their system styles.
enum AppFont {
    static let name = "PatrickHand-Regular"
    static let eastAsianName = "Xiaolai"

    private static let eastAsianDescriptor = CTFontDescriptorCreateWithAttributes([
        kCTFontNameAttribute: eastAsianName,
        kCTFontCharacterSetAttribute: eastAsianCharacters
    ] as CFDictionary)

    private static let eastAsianCharacters: CharacterSet = {
        var characters = CharacterSet()
        // CJK punctuation, kana, Han, Hangul (including decomposed jamo),
        // Bopomofo, compatibility forms, and supplementary CJK characters.
        for range in [0x1100...0x11FF, 0x2E80...0xA4CF, 0xA960...0xA97F,
                      0xAC00...0xD7FF, 0xF900...0xFAFF, 0xFE10...0xFE1F,
                      0xFE30...0xFE4F, 0xFF00...0xFFEF, 0x1AFF0...0x1B2FF,
                      0x20000...0x323AF] {
            characters.insert(charactersIn: Unicode.Scalar(range.lowerBound)!...Unicode.Scalar(range.upperBound)!)
        }
        // Declare only glyphs the font actually contains. Otherwise Core Text
        // can choose Xiaolai for an absent character instead of falling back.
        let available = CTFontCopyCharacterSet(CTFontCreateWithName(eastAsianName as CFString, 17, nil)) as CharacterSet
        return characters.intersection(available)
    }()

    static func text(_ style: Font.TextStyle) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline, .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        @unknown default: size = 17
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func expression(size: CGFloat) -> Font {
        .custom(name, size: size, relativeTo: .largeTitle)
    }

    static func withEastAsianFallback(_ font: CTFont) -> CTFont {
        let systemFallbacks = CTFontCopyDefaultCascadeListForLanguages(font, nil) as? [CTFontDescriptor] ?? []
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(font), [
            kCTFontCascadeListAttribute: [eastAsianDescriptor] + systemFallbacks
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CTFontGetSize(font), nil)
    }

    static func configureNavigationTitles() {
        let standard = withEastAsianFallback(CTFontCreateWithName(name as CFString, 17, nil)) as UIFont
        let large = withEastAsianFallback(CTFontCreateWithName(name as CFString, 34, nil)) as UIFont
        UINavigationBar.appearance().titleTextAttributes = [.font: standard]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.fontResolutionContext) private var context
    let font: Font

    func body(content: Content) -> some View {
        // Resolve the relative custom font first so Dynamic Type keeps its
        // existing scaling, then add Xiaolai to the resulting font's cascade.
        content.font(Font(AppFont.withEastAsianFallback(font.resolve(in: context).ctFont)))
    }
}

extension View {
    func appFont(_ style: Font.TextStyle) -> some View {
        modifier(AppFontModifier(font: AppFont.text(style)))
    }

    func appExpressionFont(size: CGFloat) -> some View {
        modifier(AppFontModifier(font: AppFont.expression(size: size)))
    }
}

/// The user's theme choice; `system` follows the device appearance.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appAppearance"
    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Light beige paper with black ink; dark mode is warm charcoal with cream ink.
extension UIColor {
    static let chineseRoomBackground = adaptive(light: UIColor(red: 0.91, green: 0.86, blue: 0.75, alpha: 1),
                                                dark: UIColor(hex: 0x1F1813))
    static let chineseRoomInk = adaptive(light: .black, dark: UIColor(hex: 0xF0E2CA))
    static let chineseRoomCard = adaptive(light: UIColor(white: 1, alpha: 0.5), dark: UIColor(hex: 0x2D241C))
    static let chineseRoomRule = adaptive(light: UIColor(red: 0.94, green: 0.81, blue: 0.34, alpha: 0.65),
                                          dark: UIColor(hex: 0xE4A949, alpha: 0.29))

    /// White over beige; a faint cream over charcoal at roughly a quarter of the strength.
    static func chineseRoomControl(_ lightOpacity: CGFloat) -> UIColor {
        adaptive(light: UIColor(white: 1, alpha: lightOpacity),
                 dark: UIColor(hex: 0xF0E2CA, alpha: lightOpacity * 0.24))
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    private convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static let chineseRoomBackground = Color(uiColor: .chineseRoomBackground)
    static let chineseRoomInk = Color(uiColor: .chineseRoomInk)
    static let chineseRoomCard = Color(uiColor: .chineseRoomCard)
    static let chineseRoomRule = Color(uiColor: .chineseRoomRule)

    static func chineseRoomControl(_ lightOpacity: CGFloat) -> Color {
        Color(uiColor: .chineseRoomControl(lightOpacity))
    }
}
