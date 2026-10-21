import Foundation
import MeshStreamKit

// Keep native resource creation behind a small boundary so ownership and event
// ordering can be exercised without starting a native runtime or network work.
protocol MeshStreamNativeClient: AnyObject {
  var status: MeshStreamStatusSnapshot { get }
  var eventHandler: ((String, [String: Any]) -> Void)? { get set }
  func createPlaybackSession(url: URL, options: P2PPlaybackOptions) throws -> MeshStreamNativeSession
  func close()
}

protocol MeshStreamNativeSession: AnyObject {
  var nativeSessionId: String { get }
  var playbackURL: URL { get }
  var playbackMode: P2PPlaybackMode { get }
  var fallbackReason: P2PUnavailableReason? { get }
  var stats: P2PStats { get }
  var diagnosticsSnapshot: MeshStreamDiagnosticsSnapshot { get }
  func preload() -> Bool
  func setP2pEnabled(_ enabled: Bool)
  func updateBufferedDurationMs(_ durationMs: Int64)
  func updateCurrentPositionMs(_ positionMs: Int64)
  func close()
}

// These two SDK classes are returned by getters but their class symbols are
// hidden in the 1.0.2 binary. Copy their immutable fields instead of constructing
// or subclassing them; this also keeps protocol-backed tests independent of ABI.
struct MeshStreamStatusSnapshot {
  var accountEnabled = false
  var applicationEnabled = false
  var keyEnabled = false
  var platformEnabled = false
  var effectiveP2PEnabled = false
  var reason: P2PUnavailableReason = .OK
  var configVersion: String?
  var edgeRegion: String?
  var quotaStatus: String?
}

extension MeshStreamStatusSnapshot {
  init(_ value: P2PSdkStatus) {
    self.init(accountEnabled: value.accountEnabled, applicationEnabled: value.applicationEnabled,
      keyEnabled: value.keyEnabled, platformEnabled: value.platformEnabled,
      effectiveP2PEnabled: value.effectiveP2PEnabled, reason: value.reason,
      configVersion: value.configVersion, edgeRegion: value.edgeRegion, quotaStatus: value.quotaStatus)
  }
}

struct MeshStreamDiagnosticsSnapshot {
  var fallbackCount: Int64 = 0
  var firstPeerConnectMs: Int64 = 0
  var coldStartP2PDownloaded: Int64 = 0
  var coldStartHTTPDownloaded: Int64 = 0
  var lastTrackerError: String?
  var lastPeerError: String?
  var lastErrorAtMs: Int64 = 0
  var iceAttempts: Int64 = 0
  var iceSuccesses: Int64 = 0
  var iceFailures: Int64 = 0
  var iceDurationMs: Int64 = 0
}

extension MeshStreamDiagnosticsSnapshot {
  init(_ value: P2PDiagnostics) {
    self.init(fallbackCount: value.fallbackCount, firstPeerConnectMs: value.firstPeerConnectMs,
      coldStartP2PDownloaded: value.coldStartP2PDownloaded, coldStartHTTPDownloaded: value.coldStartHTTPDownloaded,
      lastTrackerError: value.lastTrackerError, lastPeerError: value.lastPeerError, lastErrorAtMs: value.lastErrorAtMs,
      iceAttempts: value.iceAttempts, iceSuccesses: value.iceSuccesses,
      iceFailures: value.iceFailures, iceDurationMs: value.iceDurationMs)
  }
}

final class MeshStreamHostApiImpl: MeshStreamHostApi {
  typealias ClientFactory = (ApiClientConfig) throws -> MeshStreamNativeClient

  private final class BridgeClient {
    let client: MeshStreamNativeClient
    var sessions: [String: MeshStreamNativeSession] = [:]
    var nativeSessionIds: [String: String] = [:]
    var closedSessionIds: Set<String> = []
    var pendingEvents: [String: [[String: Any]]] = [:]
    var closed = false
    init(_ client: MeshStreamNativeClient) { self.client = client }
  }

  private let queue = DispatchQueue(label: "net.meshstream.flutter.resources")
  private let queueKey = DispatchSpecificKey<Bool>()
  private var clients: [String: BridgeClient] = [:]
  private var detached = false
  private let createNativeClient: ClientFactory
  private let emitEvent: ([String: Any]) -> Void

  init(createNativeClient: @escaping ClientFactory = MeshStreamSdkClient.create,
       emitEvent: @escaping ([String: Any]) -> Void) {
    self.createNativeClient = createNativeClient
    self.emitEvent = emitEvent
    queue.setSpecific(key: queueKey, value: true)
  }

  func createClient(config: ApiClientConfig, completion: @escaping (Result<ApiClientReply, Error>) -> Void) {
    respond(completion, code: "CREATE_CLIENT_FAILED") {
      guard !self.detached else { throw self.error("CREATE_CLIENT_FAILED", "MeshStream plugin is detached") }
      let clientId = UUID().uuidString
      let bridge = BridgeClient(try self.createNativeClient(config))
      self.clients[clientId] = bridge
      bridge.client.eventHandler = { [weak self, weak bridge] nativeId, event in
        guard let self = self, let bridge = bridge else { return }
        self.serialized {
          guard !bridge.closed, self.clients[clientId] === bridge,
                !nativeId.isEmpty, !bridge.closedSessionIds.contains(nativeId) else { return }
          if let sessionId = bridge.nativeSessionIds[nativeId] {
            self.send(clientId: clientId, sessionId: sessionId, event: event)
          } else if let pending = bridge.pendingEvents[nativeId] {
            if pending.count < 8 { bridge.pendingEvents[nativeId]?.append(event) }
          } else if bridge.pendingEvents.count < 64 {
            bridge.pendingEvents[nativeId] = [event]
          }
        }
      }
      return ApiClientReply(clientId: clientId)
    }
  }

  func createPlaybackSession(clientId: String, options: ApiPlaybackSessionOptions,
                             completion: @escaping (Result<ApiSessionReply, Error>) -> Void) {
    respond(completion, code: "CREATE_SESSION_FAILED") {
      let bridge = try self.client(clientId)
      guard let url = URL(string: options.url), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else {
        throw self.error("CREATE_SESSION_FAILED", "options.url must be an HTTP(S) URL")
      }
      let nativeOptions = P2PPlaybackOptions()
      nativeOptions.contentId = options.contentId
      nativeOptions.mimeType = options.mimeType
      nativeOptions.originHeaders = options.originHeaders ?? [:]
      let session = try bridge.client.createPlaybackSession(url: url, options: nativeOptions)
      let sessionId = UUID().uuidString
      bridge.sessions[sessionId] = session
      bridge.nativeSessionIds[session.nativeSessionId] = sessionId
      let reply = ApiSessionReply(sessionId: sessionId, playbackUrl: session.playbackURL.absoluteString,
        playbackMode: session.playbackMode == .nativeP2P ? "NATIVE_P2P" : "NATIVE_CDN",
        fallbackReason: session.fallbackReason.map(MeshStreamWire.reason))
      let pending = bridge.pendingEvents.removeValue(forKey: session.nativeSessionId) ?? []
      for event in pending { self.send(clientId: clientId, sessionId: sessionId, event: event) }
      return reply
    }
  }

  func preload(clientId: String, sessionId: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    respond(completion) { try self.session(clientId, sessionId).preload() }
  }
  func setP2pEnabled(clientId: String, sessionId: String, enabled: Bool,
                     completion: @escaping (Result<Void, Error>) -> Void) {
    respond(completion) { try self.session(clientId, sessionId).setP2pEnabled(enabled) }
  }
  func updateBufferedDurationMs(clientId: String, sessionId: String, durationMs: Int64,
                                completion: @escaping (Result<Void, Error>) -> Void) {
    respond(completion) { try self.session(clientId, sessionId).updateBufferedDurationMs(max(0, durationMs)) }
  }
  func updateCurrentPositionMs(clientId: String, sessionId: String, positionMs: Int64,
                               completion: @escaping (Result<Void, Error>) -> Void) {
    respond(completion) { try self.session(clientId, sessionId).updateCurrentPositionMs(max(0, positionMs)) }
  }
  func getStatus(clientId: String, completion: @escaping (Result<ApiStatus, Error>) -> Void) {
    respond(completion) { MeshStreamWire.status(try self.client(clientId).client.status) }
  }
  func getStats(clientId: String, sessionId: String, completion: @escaping (Result<ApiStats, Error>) -> Void) {
    respond(completion) { MeshStreamWire.stats(try self.session(clientId, sessionId).stats) }
  }
  func getDiagnostics(clientId: String, sessionId: String,
                      completion: @escaping (Result<ApiDiagnostics, Error>) -> Void) {
    respond(completion) { MeshStreamWire.diagnostics(try self.session(clientId, sessionId).diagnosticsSnapshot) }
  }
  func closeSession(clientId: String, sessionId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    respond(completion) {
      guard let bridge = self.clients[clientId], let session = bridge.sessions.removeValue(forKey: sessionId) else { return }
      bridge.nativeSessionIds.removeValue(forKey: session.nativeSessionId)
      bridge.closedSessionIds.insert(session.nativeSessionId)
      bridge.pendingEvents.removeValue(forKey: session.nativeSessionId)
      session.close()
    }
  }
  func closeClient(clientId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    respond(completion) {
      if let bridge = self.clients.removeValue(forKey: clientId) { self.release(bridge) }
    }
  }

  func close() {
    serialized {
      detached = true
      let owned = Array(clients.values)
      clients.removeAll()
      for bridge in owned { release(bridge) }
    }
  }

  // Re-check immediately before delivery on the main queue: a previously queued
  // event may outlive closeSession, closeClient, or engine detachment.
  func isSessionActive(_ event: [String: Any]) -> Bool {
    serialized {
      guard let clientId = event["clientId"] as? String, let sessionId = event["sessionId"] as? String,
            let bridge = clients[clientId], !bridge.closed else { return false }
      return bridge.sessions[sessionId] != nil
    }
  }

  private func release(_ bridge: BridgeClient) {
    guard !bridge.closed else { return }
    bridge.closed = true
    bridge.client.eventHandler = nil
    let sessions = Array(bridge.sessions.values)
    bridge.sessions.removeAll()
    bridge.nativeSessionIds.removeAll()
    bridge.closedSessionIds.removeAll()
    bridge.pendingEvents.removeAll()
    for session in sessions { session.close() }
    bridge.client.close()
  }
  private func client(_ clientId: String) throws -> BridgeClient {
    guard let bridge = clients[clientId], !bridge.closed else {
      throw error("UNKNOWN_CLIENT", "Unknown or closed MeshStream client: \(clientId)")
    }
    return bridge
  }
  private func session(_ clientId: String, _ sessionId: String) throws -> MeshStreamNativeSession {
    guard let session = try client(clientId).sessions[sessionId] else {
      throw error("UNKNOWN_SESSION", "Unknown or closed MeshStream session: \(sessionId)")
    }
    return session
  }
  private func serialized<T>(_ operation: () throws -> T) rethrows -> T {
    if DispatchQueue.getSpecific(key: queueKey) == true { return try operation() }
    return try queue.sync(execute: operation)
  }
  private func respond<T>(_ completion: (Result<T, Error>) -> Void, code: String = "NATIVE_ERROR",
                           operation: () throws -> T) {
    let result: Result<T, Error> = Result {
      do { return try serialized(operation) }
      catch let error as PigeonError { throw error }
      catch { throw self.error(code, error.localizedDescription) }
    }
    completion(result)
  }
  private func error(_ code: String, _ message: String) -> PigeonError {
    PigeonError(code: code, message: message, details: nil)
  }
  private func send(clientId: String, sessionId: String, event: [String: Any]) {
    var payload = event
    payload["clientId"] = clientId
    payload["sessionId"] = sessionId
    emitEvent(payload)
  }
}

enum MeshStreamWire {
  static func reason(_ value: P2PUnavailableReason) -> String {
    switch value {
    case .OK: return "OK"
    case .noPeers: return "NO_PEERS"
    case .trackerError: return "TRACKER_ERROR"
    case .authFailed: return "AUTH_FAILED"
    case .accountDisabled: return "ACCOUNT_DISABLED"
    case .appDisabled: return "APP_DISABLED"
    case .appNotFound: return "APP_NOT_FOUND"
    case .keyDisabled: return "KEY_DISABLED"
    case .platformDisabled: return "PLATFORM_DISABLED"
    case .originDenied: return "ORIGIN_DENIED"
    case .packageDenied: return "PACKAGE_DENIED"
    case .bundleDenied: return "BUNDLE_DENIED"
    case .signingCertDenied: return "SIGNING_CERT_DENIED"
    case .teamDenied: return "TEAM_DENIED"
    case .configUnavailable: return "CONFIG_UNAVAILABLE"
    case .initializationFailed: return "INITIALIZATION_FAILED"
    case .unsupported: return "UNSUPPORTED"
    case .disabled: return "DISABLED"
    case .keyP2PDisabled: return "KEY_P2P_DISABLED"
    case .quotaExhausted: return "QUOTA_EXHAUSTED"
    case .quotaDisabled: return "QUOTA_DISABLED"
    @unknown default: return "INITIALIZATION_FAILED"
    }
  }
  static func status(_ value: MeshStreamStatusSnapshot) -> ApiStatus {
    ApiStatus(accountEnabled: value.accountEnabled, applicationEnabled: value.applicationEnabled,
      keyEnabled: value.keyEnabled, platformEnabled: value.platformEnabled,
      effectiveP2pEnabled: value.effectiveP2PEnabled, reason: reason(value.reason),
      configVersion: value.configVersion, edgeRegion: value.edgeRegion, quotaStatus: value.quotaStatus)
  }
  static func stats(_ value: P2PStats) -> ApiStats {
    // Convert before adding to avoid Int64 overflow; counters remain Int64 on the wire.
    func ratio(_ successes: Int64, _ other: Int64) -> Double {
      let total = Double(successes) + Double(other)
      return total == 0 ? 0 : Double(successes) / total
    }
    return ApiStats(httpDownloaded: value.httpDownloaded, p2pDownloaded: value.p2pDownloaded,
      p2pUploaded: value.p2pUploaded, httpSegmentDownloadSuccesses: value.httpSegmentDownloadSuccesses,
      httpSegmentDownloadFailures: value.httpSegmentDownloadFailures,
      p2pSegmentDownloadSuccesses: value.p2pSegmentDownloadSuccesses,
      p2pSegmentDownloadFailures: value.p2pSegmentDownloadFailures,
      p2pSegmentUploadSuccesses: value.p2pSegmentUploadSuccesses,
      p2pSegmentUploadFailures: value.p2pSegmentUploadFailures, connectedPeers: Int64(value.connectedPeers),
      peerConnectErrors: value.peerConnectErrors, trackerErrors: value.trackerErrors,
      downloadOffloadRatio: ratio(value.p2pDownloaded, value.httpDownloaded),
      p2pSegmentDownloadSuccessRatio: ratio(value.p2pSegmentDownloadSuccesses, value.p2pSegmentDownloadFailures),
      p2pSegmentUploadSuccessRatio: ratio(value.p2pSegmentUploadSuccesses, value.p2pSegmentUploadFailures))
  }
  static func diagnostics(_ value: MeshStreamDiagnosticsSnapshot) -> ApiDiagnostics {
    ApiDiagnostics(fallbackCount: value.fallbackCount,
      firstPeerConnectMs: value.firstPeerConnectMs > 0 ? value.firstPeerConnectMs : nil,
      coldStart: value.firstPeerConnectMs > 0
        ? ApiColdStartSnapshot(p2pDownloaded: value.coldStartP2PDownloaded, httpDownloaded: value.coldStartHTTPDownloaded) : nil,
      lastTrackerError: value.lastTrackerError, lastPeerError: value.lastPeerError,
      lastErrorAtMs: value.lastErrorAtMs > 0 ? value.lastErrorAtMs : nil,
      iceAttempts: value.iceAttempts, iceSuccesses: value.iceSuccesses,
      iceFailures: value.iceFailures, iceDurationMs: value.iceDurationMs)
  }
  static func statisticsEvent(_ value: P2PStats) -> [String: Any] {
    let stats = self.stats(value)
    return ["httpDownloaded": stats.httpDownloaded, "p2pDownloaded": stats.p2pDownloaded,
      "p2pUploaded": stats.p2pUploaded, "httpSegmentDownloadSuccesses": stats.httpSegmentDownloadSuccesses,
      "httpSegmentDownloadFailures": stats.httpSegmentDownloadFailures,
      "p2pSegmentDownloadSuccesses": stats.p2pSegmentDownloadSuccesses,
      "p2pSegmentDownloadFailures": stats.p2pSegmentDownloadFailures,
      "p2pSegmentUploadSuccesses": stats.p2pSegmentUploadSuccesses,
      "p2pSegmentUploadFailures": stats.p2pSegmentUploadFailures, "connectedPeers": stats.connectedPeers,
      "peerConnectErrors": stats.peerConnectErrors, "trackerErrors": stats.trackerErrors,
      "downloadOffloadRatio": stats.downloadOffloadRatio,
      "p2pSegmentDownloadSuccessRatio": stats.p2pSegmentDownloadSuccessRatio,
      "p2pSegmentUploadSuccessRatio": stats.p2pSegmentUploadSuccessRatio]
  }
}

final class MeshStreamSdkClient: MeshStreamNativeClient {
  private let client: P2PClient
  private let listener = MeshStreamSdkListener()
  var status: MeshStreamStatusSnapshot { MeshStreamStatusSnapshot(client.sdkStatus) }
  var eventHandler: ((String, [String: Any]) -> Void)? {
    get { listener.handler }
    set {
      let wasListening = listener.handler != nil
      listener.handler = newValue
      if !wasListening && newValue != nil { client.add(listener) }
      if wasListening && newValue == nil { client.remove(listener) }
    }
  }
  static func create(_ config: ApiClientConfig) throws -> MeshStreamNativeClient {
    let native = P2PConfig(key: config.key)
    if let enabled = config.p2pEnabled { native.p2pEnabled = enabled }
    return MeshStreamSdkClient(try P2PSDK.client(with: native))
  }
  init(_ client: P2PClient) { self.client = client }
  func createPlaybackSession(url: URL, options: P2PPlaybackOptions) throws -> MeshStreamNativeSession {
    MeshStreamSdkSession(try client.createPlaybackSession(with: url, options: options))
  }
  func close() { eventHandler = nil; client.close() }
}

private final class MeshStreamSdkSession: MeshStreamNativeSession {
  private let session: PlaybackSession
  init(_ session: PlaybackSession) { self.session = session }
  var nativeSessionId: String { session.sessionId }
  var playbackURL: URL { session.playbackUrl }
  var playbackMode: P2PPlaybackMode { session.playbackMode }
  var fallbackReason: P2PUnavailableReason? { session.playbackMode == .nativeCDN ? session.fallbackReason : nil }
  var stats: P2PStats { session.statistics() }
  var diagnosticsSnapshot: MeshStreamDiagnosticsSnapshot { MeshStreamDiagnosticsSnapshot(session.diagnostics()) }
  func preload() -> Bool { session.preload() }
  func setP2pEnabled(_ enabled: Bool) { session.setP2PEnabled(enabled) }
  func updateBufferedDurationMs(_ durationMs: Int64) { session.updateBufferedDurationMs(durationMs) }
  func updateCurrentPositionMs(_ positionMs: Int64) { session.updateCurrentPositionMs(positionMs) }
  func close() { session.close() }
}

final class MeshStreamSdkListener: NSObject, P2PEventListener {
  // Native callbacks arrive on main; protect the handler against engine teardown
  // on the resource queue, and invoke a captured closure after unlocking.
  private let lock = NSLock()
  private var storedHandler: ((String, [String: Any]) -> Void)?
  var handler: ((String, [String: Any]) -> Void)? {
    get { lock.lock(); defer { lock.unlock() }; return storedHandler }
    set { lock.lock(); storedHandler = newValue; lock.unlock() }
  }
  func onPlaybackPrepared(withSessionId sessionId: String, playbackUrl: URL) {
    handler?(sessionId, ["type": "playbackPrepared", "playbackUrl": playbackUrl.absoluteString])
  }
  func onStatistics(withSessionId sessionId: String, stats: P2PStats) {
    handler?(sessionId, ["type": "statistics", "statistics": MeshStreamWire.statisticsEvent(stats)])
  }
  func onPeerCountChanged(withSessionId sessionId: String, peerCount: Int) {
    handler?(sessionId, ["type": "peerCountChanged", "peerCount": peerCount])
  }
  func onP2PReady(withSessionId sessionId: String) { handler?(sessionId, ["type": "p2pReady"]) }
  func onP2PUnavailable(withSessionId sessionId: String, reason: P2PUnavailableReason) {
    handler?(sessionId, ["type": "p2pUnavailable", "reason": MeshStreamWire.reason(reason)])
  }
  func onCdnFallback(withSessionId sessionId: String, bytes: Int64) {
    handler?(sessionId, ["type": "cdnFallback", "bytes": bytes])
  }
  func onTrackerError(withSessionId sessionId: String, totalErrors: Int64) {
    handler?(sessionId, ["type": "trackerError", "totalErrors": totalErrors])
  }
  func onPeerConnectError(withSessionId sessionId: String, totalErrors: Int64) {
    handler?(sessionId, ["type": "peerConnectError", "totalErrors": totalErrors])
  }
}
