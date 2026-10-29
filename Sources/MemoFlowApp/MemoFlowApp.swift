import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(MemoFlowCore)
import MemoFlowCore
#endif

@main
public struct MemoFlowApp: App {
    @StateObject private var store: MemoFlowStore
    @Environment(\.scenePhase) private var scenePhase

    public init() {
        if ProcessInfo.processInfo.arguments.contains("--preview-data") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MemoFlowPreview-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _store = StateObject(wrappedValue: MemoFlowStore(customStorageURL: directory.appendingPathComponent("state.json")))
        } else {
            _store = StateObject(wrappedValue: MemoFlowStore())
        }
        #if os(macOS)
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let iconImage = NSImage(contentsOf: iconURL) {
                NSApplication.shared.applicationIconImage = iconImage
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }

    public var body: some Scene {
        WindowGroup {
            HomeView(store: store)
                .task { await store.refreshKnowledge() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refreshKnowledge() } }
                }
                .preferredColorScheme(store.preferences.appearanceTheme.colorScheme)
                .focusEffectDisabled()
                #if os(macOS)
                .frame(minWidth: 440, idealWidth: 480, minHeight: 760, idealHeight: 840)
                #endif
        }
    }
}

#if os(macOS)
/// 彻底禁用 macOS AppKit 按钮默认蓝色方框焦点环（Focus Ring），保持胶囊按钮与玻璃卡片边缘纯净
extension NSControl {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }
}
#endif

/// 与 AppIcon 一致的 6 柱极简声波品牌图标组件
public struct MemoFlowWaveformBrandIcon: View {
    public var size: CGFloat = 34
    private let barRatios: [CGFloat] = [
        0.115, 0.305, 0.485, 0.235, 0.385, 0.145
    ]

    public init(size: CGFloat = 34) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                )

            HStack(alignment: .center, spacing: size * 0.045) {
                ForEach(Array(barRatios.enumerated()), id: \.offset) { _, ratio in
                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: max(1.8, size * 0.042),
                            height: max(2.6, size * ratio)
                        )
                }
            }
        }
        .frame(width: size, height: size)
    }
}
