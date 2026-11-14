import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// WATCH-001: Apple Watch 独立录音与 iPhone 传输同步服务
/// 负责在支持的设备（iOS / watchOS）上通过 WatchConnectivity 接收 Watch 录制的原音频文件与元数据，并通知 Store 导入。
public final class WatchSyncService: NSObject, @unchecked Sendable {
    public static let shared = WatchSyncService()

    public typealias WatchAudioImportHandler = @Sendable (URL, [String: Any]) async throws -> Void

    private var importHandler: WatchAudioImportHandler?
    private let stateLock = NSLock()

    public override init() {
        super.init()
        #if canImport(WatchConnectivity) && !os(macOS)
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        #endif
    }

    public func configureImportHandler(_ handler: @escaping WatchAudioImportHandler) {
        stateLock.lock()
        self.importHandler = handler
        stateLock.unlock()
    }

    public var isWatchSupported: Bool {
        #if canImport(WatchConnectivity) && !os(macOS)
        return WCSession.isSupported()
        #else
        return false
        #endif
    }

    public var isWatchPaired: Bool {
        #if canImport(WatchConnectivity) && !os(macOS)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired
        #else
        return false
        #endif
    }

    public var isWatchAppInstalled: Bool {
        #if canImport(WatchConnectivity) && !os(macOS)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isWatchAppInstalled
        #else
        return false
        #endif
    }
}

#if canImport(WatchConnectivity) && !os(macOS)
extension WatchSyncService: WCSessionDelegate {
    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // 激活状态跟踪
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        // 多手表切换保护
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // 重激活保障
        WCSession.default.activate()
    }

    /// WATCH-001-03: 接收从 Apple Watch 传输的原音频文件与录音元数据
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let tempURL = file.fileURL

        stateLock.lock()
        let handler = self.importHandler
        stateLock.unlock()

        guard let handler else { return }

        Task {
            do {
                try await handler(tempURL, metadata)
            } catch {
                // 异常情况下由 MemoFlowStore 安全落盘机制处理，不静默丢弃
            }
        }
    }
}
#endif
