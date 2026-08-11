import SwiftUI

/// Màu giao diện cố định cho app, ưu tiên nền tối thay vì phụ thuộc vào theme của iOS.
extension Color {
    static let appBackground = Color(red: 0.035, green: 0.047, blue: 0.063)   // #090C10
    static let appSurface = Color(red: 0.075, green: 0.090, blue: 0.118)       // #13171E
    static let appSurface2 = Color(red: 0.105, green: 0.125, blue: 0.157)      // #1B2028
    static let appText = Color(red: 0.94, green: 0.95, blue: 0.97)             // #F0F2F7
    static let appSecondaryText = Color(red: 0.60, green: 0.64, blue: 0.70)    // #99A3B3
    static let appAccent = Color(red: 0.34, green: 0.96, blue: 0.52)            // #57F585
}

struct AppDarkBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .tint(.appAccent)
    }
}

extension View {
    func appDarkStyle() -> some View {
        modifier(AppDarkBackground())
    }
}
