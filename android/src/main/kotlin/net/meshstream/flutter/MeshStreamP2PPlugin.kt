package net.meshstream.flutter

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.meshstream.sdk.P2pConfig
import io.meshstream.sdk.P2pSdk

/** Flutter engine registration for the MeshStream P2P plugin. */
class MeshStreamP2PPlugin : FlutterPlugin {
    private var host: MeshStreamHostApiImpl? = null
    private var channel: EventChannel? = null
    @Volatile private var delivery: MeshStreamEventDelivery? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val handler = Handler(Looper.getMainLooper())
        val api = MeshStreamHostApiImpl({ config ->
            SdkClient(P2pSdk.create(binding.applicationContext, P2pConfig(
                key = config.key,
                p2pEnabled = config.p2pEnabled ?: true,
            )))
        }, { event -> delivery?.emit(event) })
        host = api
        delivery = MeshStreamEventDelivery({ task -> handler.post { task() } }, api::isSessionActive)
        channel = EventChannel(binding.binaryMessenger, "net.meshstream/meshstream_p2p/events").also {
            it.setStreamHandler(delivery)
        }
        MeshStreamHostApi.setUp(binding.binaryMessenger, api)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MeshStreamHostApi.setUp(binding.binaryMessenger, null)
        channel?.setStreamHandler(null)
        channel = null
        delivery?.close()
        delivery = null
        host?.close()
        host = null
    }
}

/** Queued delivery belongs to the listener that existed when the event arrived. */
internal class MeshStreamEventDelivery(
    private val dispatchMain: (() -> Unit) -> Unit,
    private val isSessionActive: (Map<String, Any>) -> Boolean,
) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var generation = 0L
    private var closed = false

    @Synchronized override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        generation++
        if (!closed) sink = events
    }

    @Synchronized override fun onCancel(arguments: Any?) {
        generation++
        sink = null
    }

    @Synchronized fun close() {
        closed = true
        onCancel(null)
    }

    fun emit(event: Map<String, Any>) {
        val listener = synchronized(this) {
            val current = sink ?: return
            current to generation
        }
        dispatchMain {
            synchronized(this) {
                if (!closed && sink === listener.first && generation == listener.second && isSessionActive(event)) {
                    listener.first.success(event)
                }
            }
        }
    }
}
