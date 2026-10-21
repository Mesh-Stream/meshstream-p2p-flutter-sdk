package net.meshstream.flutter

import io.meshstream.sdk.P2pClient
import io.meshstream.sdk.P2pDiagnosticsSnapshot
import io.meshstream.sdk.P2pEventListener
import io.meshstream.sdk.P2pPlaybackMode
import io.meshstream.sdk.P2pSdkStatus
import io.meshstream.sdk.P2pStats
import io.meshstream.sdk.P2pUnavailableReason
import io.meshstream.sdk.PlaybackOptions
import io.meshstream.sdk.PlaybackSession
import java.io.Closeable
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

// Small SDK boundaries keep resource ownership testable without JNI or network I/O.
internal interface NativeClient : Closeable {
    val status: P2pSdkStatus
    fun addEventListener(listener: P2pEventListener)
    fun removeEventListener(listener: P2pEventListener)
    fun createPlaybackSession(url: String, options: PlaybackOptions): NativeSession
}

internal interface NativeSession : Closeable {
    val sessionId: Long
    val playbackUrl: String
    val playbackMode: P2pPlaybackMode
    val fallbackReason: P2pUnavailableReason?
    fun preload(): Boolean
    fun setP2pEnabled(enabled: Boolean)
    fun updateBufferedDurationMs(durationMs: Long)
    fun updateCurrentPositionMs(positionMs: Long)
    fun statistics(): P2pStats
    fun diagnostics(): P2pDiagnosticsSnapshot
}

internal class SdkClient(private val client: P2pClient) : NativeClient {
    override val status get() = client.status
    override fun addEventListener(listener: P2pEventListener) = client.addEventListener(listener)
    override fun removeEventListener(listener: P2pEventListener) = client.removeEventListener(listener)
    override fun createPlaybackSession(url: String, options: PlaybackOptions): NativeSession =
        SdkSession(client.createPlaybackSession(url, options))
    override fun close() = client.close()
}

private class SdkSession(private val session: PlaybackSession) : NativeSession {
    override val sessionId get() = session.sessionId
    override val playbackUrl get() = session.playbackUrl
    override val playbackMode get() = session.playbackMode
    override val fallbackReason get() = session.fallbackReason
    override fun preload() = session.preload()
    override fun setP2pEnabled(enabled: Boolean) = session.setP2pEnabled(enabled)
    override fun updateBufferedDurationMs(durationMs: Long) = session.updateBufferedDurationMs(durationMs)
    override fun updateCurrentPositionMs(positionMs: Long) = session.updateCurrentPositionMs(positionMs)
    override fun statistics() = session.statistics()
    override fun diagnostics() = session.diagnostics()
    override fun close() = session.close()
}

/** Implements the generated interface; generated Pigeon models are never duplicated. */
internal class MeshStreamHostApiImpl(
    private val createNativeClient: (ApiClientConfig) -> NativeClient,
    private val emitEvent: (Map<String, Any>) -> Unit,
) : MeshStreamHostApi, Closeable {
    private class BridgeClient(val client: NativeClient) {
        val sessions = ConcurrentHashMap<String, NativeSession>()
        val nativeSessionIds = mutableMapOf<Long, String>()
        val closedSessionIds = mutableSetOf<Long>()
        val pendingEvents = ConcurrentHashMap<Long, MutableList<Map<String, Any>>>()
        lateinit var listener: P2pEventListener
        @Volatile var closed = false
    }

    private val clients = ConcurrentHashMap<String, BridgeClient>()
    private val lifecycleLock = Any()
    private var detached = false

    override fun createClient(config: ApiClientConfig, callback: (Result<ApiClientReply>) -> Unit) =
        respond(callback, "CREATE_CLIENT_FAILED") {
            synchronized(lifecycleLock) {
                check(!detached) { "MeshStream plugin is detached" }
                val clientId = UUID.randomUUID().toString()
                val bridge = BridgeClient(createNativeClient(config))
                bridge.listener = listener(clientId, bridge)
                clients[clientId] = bridge
                try {
                    bridge.client.addEventListener(bridge.listener)
                } catch (error: Throwable) {
                    clients.remove(clientId)
                    release(bridge)
                    throw error
                }
                ApiClientReply(clientId)
            }
        }

    override fun createPlaybackSession(clientId: String, options: ApiPlaybackSessionOptions, callback: (Result<ApiSessionReply>) -> Unit) =
        respond(callback, "CREATE_SESSION_FAILED") {
            withClient(clientId) { bridge ->
                val session = bridge.client.createPlaybackSession(options.url, PlaybackOptions(
                    contentId = options.contentId,
                    mimeType = options.mimeType,
                    originHeaders = options.originHeaders ?: emptyMap(),
                ))
                val sessionId = UUID.randomUUID().toString()
                try {
                    val reply = ApiSessionReply(sessionId, session.playbackUrl, session.playbackMode.name, session.fallbackReason?.name)
                    bridge.sessions[sessionId] = session
                    bridge.nativeSessionIds[session.sessionId] = sessionId
                    bridge.pendingEvents.remove(session.sessionId)?.forEach { send(clientId, sessionId, it) }
                    reply
                } catch (error: Throwable) {
                    bridge.sessions.remove(sessionId)
                    bridge.nativeSessionIds.remove(session.sessionId)
                    bridge.closedSessionIds.add(session.sessionId)
                    bridge.pendingEvents.remove(session.sessionId)
                    runCatching { session.close() }
                    throw error
                }
            }
        }

    override fun preload(clientId: String, sessionId: String, callback: (Result<Boolean>) -> Unit) =
        respond(callback) { withSession(clientId, sessionId) { it.preload() } }

    override fun setP2pEnabled(clientId: String, sessionId: String, enabled: Boolean, callback: (Result<Unit>) -> Unit) =
        respond(callback) { withSession(clientId, sessionId) { it.setP2pEnabled(enabled) } }

    override fun updateBufferedDurationMs(clientId: String, sessionId: String, durationMs: Long, callback: (Result<Unit>) -> Unit) =
        respond(callback) { withSession(clientId, sessionId) { it.updateBufferedDurationMs(durationMs.coerceAtLeast(0)) } }

    override fun updateCurrentPositionMs(clientId: String, sessionId: String, positionMs: Long, callback: (Result<Unit>) -> Unit) =
        respond(callback) { withSession(clientId, sessionId) { it.updateCurrentPositionMs(positionMs.coerceAtLeast(0)) } }

    override fun getStatus(clientId: String, callback: (Result<ApiStatus>) -> Unit) = respond(callback) {
        withClient(clientId) { bridge -> bridge.client.status.let {
            ApiStatus(it.accountEnabled, it.applicationEnabled, it.keyEnabled, it.platformEnabled,
                it.effectiveP2pEnabled, it.reason.name, it.configVersion, it.edgeRegion, it.quotaStatus, it.trackerPoolReady)
        } }
    }

    override fun getStats(clientId: String, sessionId: String, callback: (Result<ApiStats>) -> Unit) =
        respond(callback) { withSession(clientId, sessionId) { it.statistics().toApi() } }

    override fun getDiagnostics(clientId: String, sessionId: String, callback: (Result<ApiDiagnostics>) -> Unit) = respond(callback) {
        withSession(clientId, sessionId) { session -> session.diagnostics().let {
            ApiDiagnostics(it.fallbackCount, it.firstPeerConnectMs,
                it.coldStart?.let { cold -> ApiColdStartSnapshot(cold.p2pDownloaded, cold.httpDownloaded) },
                it.lastTrackerError, it.lastPeerError, it.lastErrorAtMs,
                it.iceAttempts, it.iceSuccesses, it.iceFailures, it.iceDurationMs)
        } }
    }

    override fun closeSession(clientId: String, sessionId: String, callback: (Result<Unit>) -> Unit) = respond(callback) {
        clients[clientId]?.let { bridge ->
            val session = synchronized(bridge) {
                bridge.sessions.remove(sessionId)?.also {
                    bridge.nativeSessionIds.remove(it.sessionId)
                    bridge.closedSessionIds.add(it.sessionId)
                    bridge.pendingEvents.remove(it.sessionId)
                }
            }
            // Removal precedes native close so concurrent callbacks cannot revive the resource.
            if (session != null) runCatching { session.close() }
        }
        Unit
    }

    override fun closeClient(clientId: String, callback: (Result<Unit>) -> Unit) = respond(callback) {
        clients.remove(clientId)?.let(::release)
        Unit
    }

    override fun close() {
        val owned = synchronized(lifecycleLock) {
            detached = true
            clients.values.toList().also { clients.clear() }
        }
        owned.forEach(::release)
    }

    fun isSessionActive(event: Map<String, Any>): Boolean {
        val bridge = clients[event["clientId"]] ?: return false
        return !bridge.closed && bridge.sessions.containsKey(event["sessionId"])
    }

    private fun release(bridge: BridgeClient) {
        val sessions = synchronized(bridge) {
            if (bridge.closed) return
            bridge.closed = true
            bridge.sessions.values.toList().also {
                bridge.sessions.clear()
                bridge.nativeSessionIds.clear()
                bridge.closedSessionIds.clear()
                bridge.pendingEvents.clear()
            }
        }
        runCatching { bridge.client.removeEventListener(bridge.listener) }
        sessions.forEach { runCatching { it.close() } }
        runCatching { bridge.client.close() }
    }

    private fun <T> withClient(clientId: String, operation: (BridgeClient) -> T): T {
        val bridge = clients[clientId] ?: throw FlutterError("UNKNOWN_CLIENT", "Unknown or closed MeshStream client: $clientId")
        return synchronized(bridge) {
            if (bridge.closed || clients[clientId] !== bridge) throw FlutterError("UNKNOWN_CLIENT", "Unknown or closed MeshStream client: $clientId")
            operation(bridge)
        }
    }

    private fun <T> withSession(clientId: String, sessionId: String, operation: (NativeSession) -> T): T =
        withClient(clientId) { bridge ->
            operation(bridge.sessions[sessionId] ?: throw FlutterError("UNKNOWN_SESSION", "Unknown or closed MeshStream session: $sessionId"))
        }

    private fun <T> respond(callback: (Result<T>) -> Unit, code: String = "NATIVE_ERROR", operation: () -> T) {
        val result = try { Result.success(operation()) } catch (error: Throwable) {
            Result.failure(if (error is FlutterError) error else FlutterError(code, error.message))
        }
        // The consumer may throw; it must never be called a second time by our error handler.
        callback(result)
    }

    private fun listener(clientId: String, bridge: BridgeClient) = object : P2pEventListener {
        private fun emit(nativeSessionId: Long, type: String, payload: Map<String, Any> = emptyMap()) {
            synchronized(bridge) {
                if (bridge.closed || clients[clientId] !== bridge || nativeSessionId in bridge.closedSessionIds) return
                val event = mapOf("type" to type) + payload
                val sessionId = bridge.nativeSessionIds[nativeSessionId]
                if (sessionId != null) {
                    send(clientId, sessionId, event)
                } else {
                    val pending = bridge.pendingEvents[nativeSessionId]
                    if (pending != null) {
                        if (pending.size < 8) pending.add(event)
                    } else if (bridge.pendingEvents.size < 64) {
                        bridge.pendingEvents[nativeSessionId] = mutableListOf(event)
                    }
                }
            }
        }
        override fun onStatistics(sessionId: Long, stats: P2pStats) = emit(sessionId, "statistics", mapOf("statistics" to stats.toApi().toEventMap()))
        override fun onPeerCountChanged(sessionId: Long, peerCount: Int) = emit(sessionId, "peerCountChanged", mapOf("peerCount" to peerCount))
        override fun onPlaybackPrepared(sessionId: Long, playbackUrl: String) = emit(sessionId, "playbackPrepared", mapOf("playbackUrl" to playbackUrl))
        override fun onP2pReady(sessionId: Long) = emit(sessionId, "p2pReady")
        override fun onP2pUnavailable(sessionId: Long, reason: P2pUnavailableReason) = emit(sessionId, "p2pUnavailable", mapOf("reason" to reason.name))
        override fun onTrackerError(sessionId: Long, totalErrors: Long) = emit(sessionId, "trackerError", mapOf("totalErrors" to totalErrors))
        override fun onPeerConnectError(sessionId: Long, totalErrors: Long) = emit(sessionId, "peerConnectError", mapOf("totalErrors" to totalErrors))
        override fun onCdnFallback(sessionId: Long, bytes: Long) = emit(sessionId, "cdnFallback", mapOf("bytes" to bytes))
    }

    private fun send(clientId: String, sessionId: String, event: Map<String, Any>) =
        emitEvent(event + mapOf("clientId" to clientId, "sessionId" to sessionId))
}

private fun P2pStats.toApi() = ApiStats(
    httpDownloaded, p2pDownloaded, p2pUploaded, httpSegmentDownloadSuccesses, httpSegmentDownloadFailures,
    p2pSegmentDownloadSuccesses, p2pSegmentDownloadFailures, p2pSegmentUploadSuccesses, p2pSegmentUploadFailures,
    connectedPeers.toLong(), peerConnectErrors, trackerErrors,
    downloadOffloadRatio, p2pSegmentDownloadSuccessRatio, p2pSegmentUploadSuccessRatio,
)

private fun ApiStats.toEventMap(): Map<String, Any> = mapOf(
    "httpDownloaded" to httpDownloaded, "p2pDownloaded" to p2pDownloaded, "p2pUploaded" to p2pUploaded,
    "httpSegmentDownloadSuccesses" to httpSegmentDownloadSuccesses, "httpSegmentDownloadFailures" to httpSegmentDownloadFailures,
    "p2pSegmentDownloadSuccesses" to p2pSegmentDownloadSuccesses, "p2pSegmentDownloadFailures" to p2pSegmentDownloadFailures,
    "p2pSegmentUploadSuccesses" to p2pSegmentUploadSuccesses, "p2pSegmentUploadFailures" to p2pSegmentUploadFailures,
    "connectedPeers" to connectedPeers, "peerConnectErrors" to peerConnectErrors, "trackerErrors" to trackerErrors,
    "downloadOffloadRatio" to downloadOffloadRatio, "p2pSegmentDownloadSuccessRatio" to p2pSegmentDownloadSuccessRatio,
    "p2pSegmentUploadSuccessRatio" to p2pSegmentUploadSuccessRatio,
)
