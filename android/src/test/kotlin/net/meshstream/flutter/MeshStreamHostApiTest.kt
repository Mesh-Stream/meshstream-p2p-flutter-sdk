package net.meshstream.flutter

import io.meshstream.sdk.*
import org.junit.Assert.*
import org.junit.Test
import io.flutter.plugin.common.EventChannel

class MeshStreamHostApiTest {
    private val events = mutableListOf<Map<String, Any>>()
    private val native = FakeClient()
    private val host = MeshStreamHostApiImpl({ native }, events::add)

    @Test fun nativeSessionMapsToPigeonReplyAndPreservesOptions() {
        val client = client()
        val reply = session(client, ApiPlaybackSessionOptions("https://cdn/a.m3u8", "content", "m3u8", mapOf("X-Test" to "v")))
        assertEquals("NATIVE_P2P", reply.playbackMode)
        assertEquals("http://127.0.0.1/a.m3u8", reply.playbackUrl)
        assertNull(reply.fallbackReason)
        assertNotEquals("7", reply.sessionId)
        assertEquals("content", native.options!!.contentId)
        assertEquals("m3u8", native.options!!.mimeType)
        assertEquals(mapOf("X-Test" to "v"), native.options!!.originHeaders)
    }

    @Test fun everyCdnFallbackReasonUsesItsNativeWireName() {
        val client = client()
        for (reason in P2pUnavailableReason.values()) {
            native.next = FakeSession(mode = P2pPlaybackMode.NATIVE_CDN, reason = reason)
            val reply = session(client)
            assertEquals("NATIVE_CDN", reply.playbackMode)
            assertEquals(reason.name, reply.fallbackReason)
        }
    }

    @Test fun closingOneClientClosesOnlyItsSessionsAndIsIdempotent() {
        val second = FakeClient()
        var count = 0
        val api = MeshStreamHostApiImpl({ if (count++ == 0) native else second }, events::add)
        val firstId = await<ApiClientReply> { api.createClient(ApiClientConfig("key"), it) }.clientId
        val secondId = await<ApiClientReply> { api.createClient(ApiClientConfig("key"), it) }.clientId
        await<ApiSessionReply> { api.createPlaybackSession(firstId, ApiPlaybackSessionOptions("https://cdn/a"), it) }
        val secondSession = await<ApiSessionReply> { api.createPlaybackSession(secondId, ApiPlaybackSessionOptions("https://cdn/b"), it) }
        await<Unit> { api.closeClient(firstId, it) }
        await<Unit> { api.closeClient(firstId, it) }
        assertEquals(1, native.next.closes)
        assertEquals(1, native.closes)
        assertEquals(0, second.closes)
        assertEquals(0, second.next.closes)
        assertTrue(await<Boolean> { api.preload(secondId, secondSession.sessionId, it) })
    }

    @Test fun onlyFirstEightEarlyEventsFlushInOrderWithFlutterIds() {
        val client = client()
        native.onCreate = { listener -> repeat(9) { listener.onPeerCountChanged(7, it) } }
        val reply = session(client)
        assertEquals((0..7).toList(), events.map { it["peerCount"] })
        assertTrue(events.all { it.keys == setOf("type", "clientId", "sessionId", "peerCount") })
        assertTrue(events.all { it["clientId"] == client && it["sessionId"] == reply.sessionId })
    }

    @Test fun onlyFirst64UnknownNativeSessionsAreBuffered() {
        val client = client()
        native.onCreate = { listener -> (1L..65L).forEach { listener.onP2pReady(it) } }
        native.next = FakeSession(id = 65)
        session(client)
        assertTrue(events.isEmpty())
        native.onCreate = {}
        native.next = FakeSession(id = 64)
        session(client)
        assertEquals(1, events.size)
        assertEquals("p2pReady", events.single()["type"])
    }

    @Test fun closedSessionEventsAreDiscardedAndCloseIsIdempotent() {
        val client = client()
        val reply = session(client)
        await<Unit> { host.closeSession(client, reply.sessionId, it) }
        native.listener!!.onP2pReady(7)
        await<Unit> { host.closeSession(client, reply.sessionId, it) }
        assertTrue(events.isEmpty())
        assertEquals(1, native.next.closes)
        assertError("UNKNOWN_SESSION") { host.preload(client, reply.sessionId, it) }
        assertError("UNKNOWN_CLIENT") { host.preload("missing", reply.sessionId, it) }
    }

    @Test fun detachContinuesCleanupWhenOneNativeCloseThrows() {
        val client = client()
        val first = native.next
        first.closeFailure = true
        session(client)
        native.next = FakeSession(id = 8)
        session(client)
        host.close()
        host.close()
        native.listenerBeforeRemove!!.onP2pReady(8)
        assertEquals(1, first.closes)
        assertEquals(1, native.next.closes)
        assertEquals(1, native.closes)
        assertTrue(events.isEmpty())
        assertError("UNKNOWN_CLIENT") { host.preload(client, "anything", it) }
    }

    @Test fun statisticsKeepLongPrecisionAndComputeRatios() {
        val client = client()
        native.next.stats = P2pStats(100, 300, 9007199254740993L, 2, 1, 3, 1, 1, 3, 5, 6, 7)
        val reply = session(client)
        val stats = await<ApiStats> { host.getStats(client, reply.sessionId, it) }
        assertEquals(9007199254740993L, stats.p2pUploaded)
        assertEquals(0.75, stats.downloadOffloadRatio, 0.0)
        assertEquals(0.75, stats.p2pSegmentDownloadSuccessRatio, 0.0)
        assertEquals(0.25, stats.p2pSegmentUploadSuccessRatio, 0.0)
        native.listener!!.onStatistics(7, native.next.stats)
        val payload = events.single()["statistics"] as Map<*, *>
        assertEquals(9007199254740993L, payload["p2pUploaded"])
        assertEquals(0.75, payload["downloadOffloadRatio"])
        native.next.stats = P2pStats()
        assertEquals(0.0, await<ApiStats> { host.getStats(client, reply.sessionId, it) }.downloadOffloadRatio, 0.0)
    }

    @Test fun allEventShapesUseOnlyLegalPayloads() {
        val client = client()
        val reply = session(client)
        val listener = native.listener!!
        listener.onPeerCountChanged(7, 4)
        listener.onPlaybackPrepared(7, "http://loopback")
        listener.onP2pReady(7)
        listener.onP2pUnavailable(7, P2pUnavailableReason.NO_PEERS)
        listener.onStatistics(7, P2pStats())
        listener.onCdnFallback(7, 9007199254740993L)
        listener.onTrackerError(7, 2)
        listener.onPeerConnectError(7, 3)
        val payloads = listOf("peerCount", "playbackUrl", null, "reason", "statistics", "bytes", "totalErrors", "totalErrors")
        assertEquals(listOf("peerCountChanged", "playbackPrepared", "p2pReady", "p2pUnavailable", "statistics", "cdnFallback", "trackerError", "peerConnectError"), events.map { it["type"] })
        events.zip(payloads).forEach { (event, payload) ->
            assertEquals(setOfNotNull("type", "clientId", "sessionId", payload), event.keys)
            assertEquals(client, event["clientId"])
            assertEquals(reply.sessionId, event["sessionId"])
        }
        assertEquals("NO_PEERS", events[3]["reason"])
        assertEquals(9007199254740993L, events[5]["bytes"])
    }

    @Test fun statusAndDiagnosticsPreserveOptionalTelemetry() {
        val client = client()
        val reply = session(client)
        native.status = P2pSdkStatus(false, true, false, true, false, P2pUnavailableReason.KEY_DISABLED, "v1", "edge", "blocked", false)
        val status = await<ApiStatus> { host.getStatus(client, it) }
        assertEquals(listOf(false, true, false, true, false, "KEY_DISABLED", "v1", "edge", "blocked", false), status.toList())
        native.next.snapshot = P2pDiagnosticsSnapshot(2, 31, P2pColdStartSnapshot(100, 300), "tracker", "peer", 123, 5, 3, 2, 99)
        val diagnostics = await<ApiDiagnostics> { host.getDiagnostics(client, reply.sessionId, it) }
        assertEquals(listOf(2L, 31L, ApiColdStartSnapshot(100, 300), "tracker", "peer", 123L, 5L, 3L, 2L, 99L), diagnostics.toList())
    }

    @Test fun sessionControlsClampNegativePlaybackValues() {
        val client = client()
        val reply = session(client)
        await<Unit> { host.updateBufferedDurationMs(client, reply.sessionId, -4, it) }
        await<Unit> { host.updateCurrentPositionMs(client, reply.sessionId, -2, it) }
        await<Unit> { host.setP2pEnabled(client, reply.sessionId, false, it) }
        assertEquals(0L, native.next.buffered)
        assertEquals(0L, native.next.position)
        assertEquals(false, native.next.enabled)
    }

    @Test fun creationFailuresHaveStableCodesAndUnknownClientIsNotRewrapped() {
        val failing = MeshStreamHostApiImpl({ throw IllegalStateException("failure") }, events::add)
        val error = failure<ApiClientReply> { failing.createClient(ApiClientConfig("key"), it) }
        assertEquals("CREATE_CLIENT_FAILED", error.code)
        val client = client()
        native.onCreate = { throw IllegalStateException("failure") }
        assertEquals("CREATE_SESSION_FAILED", failure<ApiSessionReply> { host.createPlaybackSession(client, ApiPlaybackSessionOptions("url"), it) }.code)
        assertEquals("UNKNOWN_CLIENT", failure<ApiSessionReply> { host.createPlaybackSession("missing", ApiPlaybackSessionOptions("url"), it) }.code)
    }

    @Test fun callbacksAreInvokedOnceEvenWhenConsumerThrows() {
        var calls = 0
        try {
            host.createClient(ApiClientConfig("key")) { calls++; error("consumer failed") }
            fail("Consumer failure must propagate")
        } catch (_: IllegalStateException) { }
        assertEquals(1, calls)
    }

    @Test fun queuedEventIsDroppedAfterCancelDetachOrSessionClose() {
        val queue = mutableListOf<() -> Unit>()
        var active = true
        val delivery = MeshStreamEventDelivery({ queue.add(it) }, { active })
        val received = mutableListOf<Any?>()
        val sink = object : EventChannel.EventSink {
            override fun success(event: Any?) { received.add(event) }
            override fun error(code: String, message: String?, details: Any?) { fail("Unexpected error") }
            override fun endOfStream() { }
        }
        val event = mapOf<String, Any>("type" to "p2pReady", "clientId" to "c", "sessionId" to "s")
        delivery.emit(event)
        assertTrue(queue.isEmpty())
        delivery.onListen(null, sink)
        delivery.emit(event)
        assertTrue(received.isEmpty())
        queue.removeAt(0).invoke()
        assertEquals(listOf(event), received)
        delivery.emit(event)
        delivery.onCancel(null)
        delivery.onListen(null, sink)
        queue.removeAt(0).invoke()
        delivery.emit(event)
        active = false
        queue.removeAt(0).invoke()
        active = true
        delivery.emit(event)
        delivery.close()
        queue.removeAt(0).invoke()
        assertEquals(listOf(event), received)
    }

    private fun client() = await<ApiClientReply> { host.createClient(ApiClientConfig("key"), it) }.clientId
    private fun session(client: String, options: ApiPlaybackSessionOptions = ApiPlaybackSessionOptions("https://cdn/a")) =
        await<ApiSessionReply> { host.createPlaybackSession(client, options, it) }

    private fun assertError(code: String, call: ((Result<Boolean>) -> Unit) -> Unit) = assertEquals(code, failure(call).code)

    private fun <T> failure(call: ((Result<T>) -> Unit) -> Unit): FlutterError {
        var failure: Throwable? = null
        call { failure = it.exceptionOrNull() }
        return failure as FlutterError
    }

    private fun <T> await(call: ((Result<T>) -> Unit) -> Unit): T {
        var result: Result<T>? = null
        call { check(result == null) { "Callback invoked twice" }; result = it }
        return checkNotNull(result) { "Callback not invoked" }.getOrThrow()
    }

    private class FakeClient : NativeClient {
        override var status = P2pSdkStatus()
        var next = FakeSession()
        var listener: P2pEventListener? = null
        var listenerBeforeRemove: P2pEventListener? = null
        var onCreate: (P2pEventListener) -> Unit = {}
        var options: PlaybackOptions? = null
        var closes = 0
        override fun addEventListener(listener: P2pEventListener) { this.listener = listener }
        override fun removeEventListener(listener: P2pEventListener) { listenerBeforeRemove = listener; this.listener = null }
        override fun createPlaybackSession(url: String, options: PlaybackOptions): NativeSession {
            this.options = options
            onCreate(listener!!)
            return next
        }
        override fun close() { closes++ }
    }

    private class FakeSession(val id: Long = 7, val mode: P2pPlaybackMode = P2pPlaybackMode.NATIVE_P2P, val reason: P2pUnavailableReason? = null) : NativeSession {
        override val sessionId get() = id
        override val playbackUrl = "http://127.0.0.1/a.m3u8"
        override val playbackMode get() = mode
        override val fallbackReason get() = reason
        var stats = P2pStats()
        var snapshot = P2pDiagnosticsSnapshot()
        var closes = 0
        var closeFailure = false
        var buffered = -1L
        var position = -1L
        var enabled = true
        override fun preload() = true
        override fun setP2pEnabled(enabled: Boolean) { this.enabled = enabled }
        override fun updateBufferedDurationMs(durationMs: Long) { buffered = durationMs }
        override fun updateCurrentPositionMs(positionMs: Long) { position = positionMs }
        override fun statistics() = stats
        override fun diagnostics() = snapshot
        override fun close() { closes++; if (closeFailure) error("already closed") }
    }
}
