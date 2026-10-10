import Flutter
import UIKit
import UniformTypeIdentifiers

/// Brings the key images file the Monero GUI exported into the app: chosen
/// with the Files picker, or opened with this app from Files, the share sheet
/// or AirDrop. lib/pick_file.dart is the other end of the channel.
///
/// iOS hands the app its own copy of the file in each case. That copy is
/// moved into a folder of its own under tmp/KeyImages, which is never backed
/// up, and the app deletes it once it is imported or set aside. Copies an
/// earlier launch left behind, and anything left in the folders iOS copies
/// files into, are deleted at launch. Nothing here reads the file or logs its
/// name.
final class KeyImagesFile: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate,
  UIDocumentPickerDelegate
{
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?

  /// Answers the Dart side's "pick" once the Files picker closes.
  private var picked: FlutterResult?

  /// Files opened with the app that the Dart side hasn't taken yet: the one
  /// that started the app arrives before the Dart side is listening.
  private var received: [String] = []
  private var dartListening = false

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    // A new launch has nothing waiting to be imported.
    try? FileManager.default.removeItem(at: incoming)
    let channel = FlutterMethodChannel(
      name: "monero_view_wallet/key_images_file",
      binaryMessenger: registrar.messenger())
    let instance = KeyImagesFile(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result)
    case "take":
      dartListening = true
      result(received)
      received.removeAll()
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: The Files picker

  private func pick(_ result: @escaping FlutterResult) {
    guard picked == nil, var top = registrar?.viewController else {
      result(FlutterError(code: "unavailable", message: "Can't show the Files picker now", details: nil))
      return
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    picked = result
    // The GUI's file has no extension of its own, so any file can be chosen.
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let path = urls.first.flatMap { keep($0, isCopy: true) }
    picked?(path)
    picked = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    picked?(nil)
    picked = nil
  }

  // MARK: Files opened with the app

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    let handled = receive(connectionOptions?.urlContexts ?? [])
    // Whatever is still in the inboxes was left by an earlier launch.
    Self.emptyInboxes()
    return handled
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    let handled = receive(URLContexts)
    if handled {
      Self.emptyInboxes()
    }
    return handled
  }

  /// Keeps the files among [contexts] for the Dart side. True if there were
  /// any, so Flutter doesn't treat them as links into the app.
  private func receive(_ contexts: Set<UIOpenURLContext>) -> Bool {
    let files = contexts.filter { $0.url.isFileURL }
    if files.isEmpty {
      return false
    }
    for context in files {
      if let path = keep(context.url, isCopy: !context.options.openInPlace) {
        received.append(path)
      }
    }
    if dartListening && !received.isEmpty {
      channel.invokeMethod("received", arguments: nil)
    }
    return true
  }

  // MARK: The app's copies

  /// tmp/KeyImages: the files waiting to be imported, each in a folder of its
  /// own so it keeps its name.
  private static var incoming: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("KeyImages", isDirectory: true)
  }

  /// Moves [url], the app's own copy, into a new folder under [incoming] and
  /// returns its path there. A file that isn't the app's own copy is copied
  /// instead; Info.plist says the app doesn't open files in place, so iOS
  /// shouldn't send one.
  private func keep(_ url: URL, isCopy: Bool) -> String? {
    let files = FileManager.default
    let folder = Self.incoming.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let kept = folder.appendingPathComponent(url.lastPathComponent)
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      try files.createDirectory(at: folder, withIntermediateDirectories: true)
      if isCopy {
        try files.moveItem(at: url, to: kept)
      } else {
        try files.copyItem(at: url, to: kept)
      }
      return kept.path
    } catch {
      try? files.removeItem(at: folder)
      if isCopy {
        try? files.removeItem(at: url)
      }
      return nil
    }
  }

  /// Deletes what is left in the folders iOS copies files into for the app:
  /// Documents/Inbox for "Open in…" and AirDrop, tmp/<bundle id>-Inbox for
  /// the Files picker.
  private static func emptyInboxes() {
    let files = FileManager.default
    var inboxes: [URL] = []
    if let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first {
      inboxes.append(documents.appendingPathComponent("Inbox", isDirectory: true))
    }
    let tmp = files.temporaryDirectory
    for name in (try? files.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasSuffix("-Inbox") {
      inboxes.append(tmp.appendingPathComponent(name, isDirectory: true))
    }
    for inbox in inboxes {
      for item in (try? files.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? [] {
        try? files.removeItem(at: item)
      }
    }
  }
}
