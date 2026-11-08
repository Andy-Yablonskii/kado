import SwiftUI
import UIKit
import KadoCore

/// Whether Kadō follows the system appearance or pins itself to light
/// or dark. Stored as a raw string in `UserDefaults` (see
/// ``ColorSchemePreference/key``) — a display preference, per device,
/// so it stays out of the SwiftData schema.
enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "kado.colorScheme"

    var id: Self { self }

    /// Applied to every window rather than through
    /// `.preferredColorScheme`: going back to `nil` there doesn't
    /// release an override on every runtime, and sheets presented from
    /// a window inherit the window's style for free.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// Settings → Appearance: light, dark, or follow the system.
struct ColorSchemeSection: View {
    @AppStorage(ColorSchemePreference.key)
    private var preference: ColorSchemePreference = .system

    var body: some View {
        Section {
            Picker("Mode", selection: $preference) {
                ForEach(ColorSchemePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.colorSchemePicker")
        } header: {
            Text("Light & dark")
                .foregroundStyle(Color.kadoForegroundSecondary)
        } footer: {
            Text("System follows your iPhone's setting.")
                .foregroundStyle(Color.kadoForegroundSecondary)
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        .onChange(of: preference) { _, newValue in newValue.apply() }
    }
}

#Preview {
    Form { ColorSchemeSection() }
}

#Preview("Dark") {
    Form { ColorSchemeSection() }
        .preferredColorScheme(.dark)
}
