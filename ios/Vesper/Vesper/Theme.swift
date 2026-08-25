import SwiftUI

/// Vesper's palette — mirrors the CSS variables in app.py (ink / ember / rose).
enum VesperTheme {
    static let bg = Color(hex: 0x140F0C)
    static let bgDeep = Color(hex: 0x0E0B09)
    static let bgWarm = Color(hex: 0x1A120E)
    static let panel = Color(hex: 0x1C1510)
    static let ink = Color(hex: 0xF3E6D8)
    static let mute = Color(hex: 0xB9A090)
    static let ember = Color(hex: 0xC45C26)
    static let rose = Color(hex: 0xA84D4D)
    static let line = Color(hex: 0xF3E6D8).opacity(0.12)

    /// Garamond-ish display type (New York serif).
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The candlelit backdrop: warm vertical fade with ember and rose glows,
/// matching the Gradio app's radial-gradient background.
struct VesperBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [VesperTheme.bgWarm, VesperTheme.bgDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [VesperTheme.ember.opacity(0.22), .clear],
                center: UnitPoint(x: 0.1, y: -0.1),
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [VesperTheme.rose.opacity(0.16), .clear],
                center: UnitPoint(x: 1.0, y: 0.0),
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
