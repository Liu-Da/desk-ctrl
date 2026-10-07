import AppKit
import SwiftUI

enum DeskStyle {
    static let blue = Color(red: 0.02, green: 0.43, blue: 1)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let secondary = Color(red: 0.39, green: 0.43, blue: 0.52)
    static let sidebar = Color(red: 0.945, green: 0.961, blue: 0.980)
    static let selection = Color(red: 0.867, green: 0.920, blue: 1)
    static let border = Color(red: 0.81, green: 0.84, blue: 0.89)
    static let control = Color(red: 0.957, green: 0.965, blue: 0.976)
    static let green = Color(red: 0.15, green: 0.69, blue: 0.28)
}

struct FlatButtonStyle: ButtonStyle {
    enum Kind { case secondary, primary, destructive }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 18)
            .frame(minHeight: 38)
            .foregroundStyle(kind == .primary ? Color.white : kind == .destructive ? Color.red : DeskStyle.ink)
            .background(kind == .primary ? DeskStyle.blue : DeskStyle.control,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if kind != .primary {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(DeskStyle.border, lineWidth: 1)
                }
            }
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.06))
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

extension View {
    func deskField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(DeskStyle.border, lineWidth: 1) }
    }
}

func deskNumber(_ string: String) -> Double? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
    guard let value = Double(trimmed), value.isFinite else { return nil }
    return value
}
