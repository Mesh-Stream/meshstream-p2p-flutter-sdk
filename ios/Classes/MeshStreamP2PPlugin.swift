import Flutter
import Foundation

public class MeshStreamP2PPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventChannel: FlutterEventChannel?
  private let sinkLock = NSLock()
  private var eventSink: FlutterEventSink?
  private var sinkGeneration: UInt64 = 0
  private(set) var hostApi: MeshStreamHostApiImpl!

  override public convenience init() { self.init(createNativeClient: MeshStreamSdkClient.create) }

  init(createNativeClient: @escaping MeshStreamHostApiImpl.ClientFactory) {
    super.init()
    hostApi = MeshStreamHostApiImpl(createNativeClient: createNativeClient) { [weak self] event in
      self?.enqueue(event)
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = MeshStreamP2PPlugin()
    MeshStreamHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin.hostApi)
    let channel = FlutterEventChannel(name: "net.meshstream/meshstream_p2p/events", binaryMessenger: registrar.messenger())
    plugin.eventChannel = channel
    channel.setStreamHandler(plugin)
    // Publishing retains the instance and opts it into engine detach callbacks.
    registrar.publish(plugin)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sinkLock.lock()
    sinkGeneration &+= 1
    eventSink = events
    sinkLock.unlock()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sinkLock.lock()
    sinkGeneration &+= 1
    eventSink = nil
    sinkLock.unlock()
    return nil
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    MeshStreamHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    eventChannel?.setStreamHandler(nil)
    eventChannel = nil
    _ = onCancel(withArguments: nil)
    hostApi.close()
  }

  private func enqueue(_ event: [String: Any]) {
    sinkLock.lock()
    let generation = sinkGeneration
    let hasListener = eventSink != nil
    sinkLock.unlock()
    guard hasListener else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.hostApi.isSessionActive(event) else { return }
      self.sinkLock.lock()
      let sink = self.sinkGeneration == generation ? self.eventSink : nil
      self.sinkLock.unlock()
      sink?(event)
    }
  }

  deinit { hostApi.close() }
}
