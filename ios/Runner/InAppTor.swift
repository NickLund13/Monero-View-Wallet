import Flutter
import Foundation

/// The app's own Tor on iPhone (lib/tor.dart): the Tor Project's tor, built as
/// a library by Tor.framework (tool/fetch_tor.sh fetches it), running on a
/// thread of its own inside the app, since an iPhone app can't start a
/// program. Tor can run only once in an app's life, so it isn't stopped:
/// lib/tor.dart turns its network off and on again through Tor's control
/// port. Nothing here reads or logs what Tor says or carries.
final class InAppTor: NSObject, FlutterPlugin {
  /// Whether Tor has been started in this launch, and whether it has stopped
  /// since. Only used on the main thread.
  private static var started = false
  private static var exited = false

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addMethodCallDelegate(
      InAppTor(),
      channel: FlutterMethodChannel(
        name: "monero_view_wallet/tor", binaryMessenger: registrar.messenger()))
  }

  /// "start" with Tor's command line: "started", "running" if Tor already
  /// is, or "exited" if it ran and stopped, which needs the app restarted.
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "start" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String] else {
      result(FlutterError(code: "arguments", message: "Expected Tor's command line.", details: nil))
      return
    }
    if Self.exited {
      result("exited")
      return
    }
    if Self.started {
      result("running")
      return
    }
    Self.started = true
    let thread = Thread {
      Self.run(["tor"] + arguments)
      DispatchQueue.main.async { Self.exited = true }
    }
    thread.name = "Tor"
    // More than the 512 KB a secondary thread gets by default.
    thread.stackSize = 4 << 20
    thread.start()
    result("started")
  }

  /// Runs Tor until it exits. Tor keeps its command line until then.
  private static func run(_ arguments: [String]) {
    var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
    defer { argv.forEach { free($0) } }
    guard let config = tor_main_configuration_new() else { return }
    defer { tor_main_configuration_free(config) }
    argv.withUnsafeMutableBufferPointer { buffer in
      guard
        tor_main_configuration_set_command_line(config, Int32(buffer.count), buffer.baseAddress)
          == 0
      else { return }
      _ = tor_run_main(config)
    }
  }
}
