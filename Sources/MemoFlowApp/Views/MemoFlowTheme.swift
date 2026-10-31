import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

extension AppearanceTheme {
    public var colorScheme: ColorScheme? {
        switch self {
        case .warmPaper: return .light
        case .darkNight: return .dark
        case .system: return nil
        }
    }
}

/// 动态明暗响应颜色辅助器：在 macOS / iOS 原生提供 Readwise 纸张质感与深邃夜读模式
public func mfDynamicColor(light: Color, dark: Color) -> Color {
    #if os(macOS)
    return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor(dark) : NSColor(light)
    }))
    #elseif os(iOS)
    return Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
    #else
    return light
    #endif
}

extension Color {
    public init?(hex: String?) {
        guard let raw = hex?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted),
              raw.count == 6,
              let intVal = UInt64(raw, radix: 16) else {
            return nil
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// MemoFlow 全局设计系统（PRD V1.3 VIS-001：Readwise 风格极简纸质化 UI）
/// 设计关键词：纸张感、书籍感、克制、安静、温暖、可读、留白
public enum MFTheme {
    public static var activeTheme: AppearanceTheme = .warmPaper

    public static func resolveColor(light: Color, dark: Color) -> Color {
        switch activeTheme {
        case .warmPaper:
            return light
        case .darkNight:
            return dark
        case .system:
            return mfDynamicColor(light: light, dark: dark)
        }
    }

    // MARK: - Core Backgrounds & Surfaces (Readwise 暖纸与书页卡片)

    /// V2.1 语义 Token
    public static var paperBackground: Color { canvasBg }
    public static var paperSurface: Color { cardBgTop }
    public static var inkPrimary: Color { textPrimary }
    public static var inkSecondary: Color { textSecondary }
    public static var warmAccent: Color { iceBlue }
    public static var lineSubtle: Color { paperBorder }

    /// 书页主背景：Light #F7F4EE (暖白纸质书页) / Dark #161514 (深邃夜读墨木)
    public static var canvasBg: Color {
        resolveColor(
            light: Color(red: 0.969, green: 0.957, blue: 0.933),
            dark: Color(red: 0.086, green: 0.082, blue: 0.078)
        )
    }

    /// 弹窗与抽屉底板：Light #FAF8F4 / Dark #1B1A18
    public static var sheetBg: Color {
        resolveColor(
            light: Color(red: 0.980, green: 0.973, blue: 0.957),
            dark: Color(red: 0.106, green: 0.102, blue: 0.094)
        )
    }

    /// 内容卡片顶底轻微渐变：Light #FFFEFA -> #FAF8F4 (纯净温润象牙纸页) / Dark #21201D -> #1A1917
    public static var cardBgTop: Color {
        resolveColor(
            light: Color(red: 1.000, green: 0.996, blue: 0.980),
            dark: Color(red: 0.137, green: 0.133, blue: 0.125)
        )
    }
    public static var cardBgBottom: Color {
        resolveColor(
            light: Color(red: 0.980, green: 0.973, blue: 0.957),
            dark: Color(red: 0.114, green: 0.110, blue: 0.102)
        )
    }

    /// 内凹槽、搜索栏底色：Light #EFECE4 / Dark #11100F
    public static var recessedBg: Color {
        resolveColor(
            light: Color(red: 0.937, green: 0.925, blue: 0.894),
            dark: Color(red: 0.071, green: 0.067, blue: 0.063)
        )
    }

    // MARK: - Accents (低饱和典雅暖金、茶墨与印章暖红)

    /// 主强调色（Readwise 沉香琥珀金 #B68E58 / 兼容原 iceBlue 调用）
    public static var iceBlue: Color {
        resolveColor(
            light: Color(red: 0.714, green: 0.557, blue: 0.345),
            dark: Color(red: 0.796, green: 0.647, blue: 0.431)
        )
    }
    public static var iceCyan: Color {
        resolveColor(
            light: Color(red: 0.353, green: 0.529, blue: 0.588),
            dark: Color(red: 0.518, green: 0.706, blue: 0.765)
        )
    }
    public static var warmAmber: Color {
        resolveColor(
            light: Color(red: 0.769, green: 0.510, blue: 0.247),
            dark: Color(red: 0.875, green: 0.612, blue: 0.322)
        )
    }
    public static var mintGreen: Color {
        resolveColor(
            light: Color(red: 0.290, green: 0.549, blue: 0.400),
            dark: Color(red: 0.345, green: 0.620, blue: 0.455)
        )
    }
    public static var softViolet: Color {
        resolveColor(
            light: Color(red: 0.490, green: 0.420, blue: 0.608),
            dark: Color(red: 0.616, green: 0.541, blue: 0.733)
        )
    }
    public static var coralRed: Color {
        resolveColor(
            light: Color(red: 0.761, green: 0.329, blue: 0.302),
            dark: Color(red: 0.863, green: 0.412, blue: 0.384)
        )
    }

    // MARK: - Text Hierarchy (深暖墨黑与温润书卷灰)

    /// 墨色正文（#292822）
    public static var textPrimary: Color {
        resolveColor(
            light: Color(red: 0.161, green: 0.157, blue: 0.133),
            dark: Color(red: 0.925, green: 0.918, blue: 0.898)
        )
    }
    /// 次级正文与批注（#6B675E）
    public static var textSecondary: Color {
        resolveColor(
            light: Color(red: 0.420, green: 0.404, blue: 0.369),
            dark: Color(red: 0.667, green: 0.651, blue: 0.620)
        )
    }
    /// 弱化时间戳与元数据（#969186）
    public static var textMuted: Color {
        resolveColor(
            light: Color(red: 0.588, green: 0.569, blue: 0.529),
            dark: Color(red: 0.490, green: 0.475, blue: 0.447)
        )
    }

    // MARK: - Borders & Dividers (极柔和淡灰褐 #E8E4DA)
    public static var paperBorder: Color {
        resolveColor(
            light: Color(red: 0.910, green: 0.894, blue: 0.855),
            dark: Color(red: 0.208, green: 0.200, blue: 0.188)
        )
    }

    // MARK: - Gradients
    public static var cardSurfaceGradient: LinearGradient {
        LinearGradient(
            colors: [cardBgTop, cardBgTop],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static var cardBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                paperBorder,
                paperBorder.opacity(0.65)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var ambientTopGlow: RadialGradient {
        RadialGradient(
            colors: [
                Color.clear,
                Color.clear
            ],
            center: .top,
            startRadius: 10,
            endRadius: 360
        )
    }
}

// MARK: - Reusable Paper Card & Pill Modifiers

public struct MFGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var paddingAmount: CGFloat = 16
    var highlightColor: Color? = nil

    public func body(content: Content) -> some View {
        let isLight = (MFTheme.activeTheme == .warmPaper)
        let shadowColor = Color.clear
        let shadowRadius: CGFloat = isLight ? 6 : 12
        let shadowY: CGFloat = isLight ? 2 : 5

        let border = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                highlightColor?.opacity(isLight ? 0.35 : 0.45) ?? MFTheme.paperBorder,
                lineWidth: 0.8
            )

        return content
            .padding(paddingAmount)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(MFTheme.cardSurfaceGradient)
                    if let tint = highlightColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(isLight ? 0.05 : 0.09))
                    }
                    border
                }
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

extension View {
    public func mfGlassCard(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        tint: Color? = nil
    ) -> some View {
        modifier(MFGlassCardModifier(cornerRadius: cornerRadius, paddingAmount: padding, highlightColor: tint))
    }
}

/// 精致的书卷式状态胶囊徽章
public struct MFBadgePill: View {
    let text: String
    let color: Color
    var icon: String? = nil

    public init(_ text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    public var body: some View {
        let isLight = (MFTheme.activeTheme == .warmPaper)
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(color.opacity(isLight ? 0.08 : 0.16))
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(isLight ? 0.28 : 0.35), lineWidth: 0.7)
                )
        )
        .foregroundStyle(color)
    }
}

/// 典雅暖金/印章感操作按钮
public struct MFLuminousActionButton: View {
    let title: String
    let icon: String?
    var tint: Color = MFTheme.iceBlue
    let action: () -> Void

    public init(_ title: String, icon: String? = nil, tint: Color = MFTheme.iceBlue, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7)
                }
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
