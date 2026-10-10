import AVFoundation
import Flutter
import UIKit

/// The camera for Scan wallet QR (lib/scan_screen.dart is the other end of the
/// channel). Apple's own AVFoundation reads QR codes on the iPhone: no
/// scanning library, nothing sent anywhere.
///
/// Each camera view on the Dart side is a platform view with a capture
/// session of its own, which runs from the moment the view is made until it
/// reads one code or the Dart side takes the view away. The picture is only
/// ever shown on screen, never saved, and no code's text is logged.
final class QrCamera: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "monero_view_wallet/camera", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(QrCamera(), channel: channel)
    registrar.register(
      QrCameraViewFactory(channel: channel), withId: "monero_view_wallet/camera")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      // Whether the person has answered, without asking them.
      result(Self.status())
    case "allowed":
      // Asks the first time only: iOS shows its question with the text of
      // NSCameraUsageDescription in Info.plist.
      if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async { result(granted) }
        }
      } else {
        result(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
      }
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    case "stop":
      if let id = call.arguments as? Int {
        QrCameraView.views.object(forKey: NSNumber(value: id))?.stop()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func status() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    @unknown default: return "unknown"
    }
  }
}

final class QrCameraViewFactory: NSObject, FlutterPlatformViewFactory {
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    QrCameraView(frame: frame, id: viewId, channel: channel)
  }
}

final class QrCameraView: NSObject, FlutterPlatformView {
  /// The views still on the Dart side's screen, by id, so "stop" can reach
  /// them.
  static let views = NSMapTable<NSNumber, QrCameraView>.strongToWeakObjects()

  private let preview: CameraPreview
  private let session = AVCaptureSession()
  /// The capture output's delegate. It holds this view weakly, so the view
  /// goes, and with it the camera, when Flutter lets go of it, even if the
  /// Dart side never learnt its id to send "stop".
  private let reader = CodeReader()
  /// startRunning and stopRunning wait for the camera, so they run here.
  private let queue = DispatchQueue(label: "monero_view_wallet.camera")
  private let id: Int64
  private let channel: FlutterMethodChannel
  /// True once a code was read or the view was stopped: nothing more is
  /// handed over.
  private var done = false

  init(frame: CGRect, id: Int64, channel: FlutterMethodChannel) {
    preview = CameraPreview(frame: frame)
    self.id = id
    self.channel = channel
    super.init()
    reader.view = self
    QrCameraView.views.setObject(self, forKey: NSNumber(value: id))
    preview.previewLayer.videoGravity = .resizeAspectFill
    preview.previewLayer.session = session
    // The start-up holds neither this view nor its preview, so neither is
    // ever let go of on the camera queue.
    let session = self.session
    let reader = self.reader
    let preview = self.preview
    queue.async { [weak preview] in
      guard QrCameraView.configure(session, delegate: reader) else { return }
      session.startRunning()
      DispatchQueue.main.async { preview?.setNeedsLayout() }
    }
  }

  deinit {
    let session = self.session
    queue.async { QrCameraView.tearDown(session) }
  }

  func view() -> UIView { preview }

  /// The back camera in, QR codes out. False when there is no camera to use:
  /// not allowed, or none at all, as on the simulator.
  private static func configure(
    _ session: AVCaptureSession, delegate: AVCaptureMetadataOutputObjectsDelegate
  ) -> Bool {
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
      let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device)
    else { return false }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    let output = AVCaptureMetadataOutput()
    guard session.canAddInput(input), session.canAddOutput(output) else { return false }
    session.addInput(input)
    session.addOutput(output)
    // Only once the output is in the session does it know it can read QR.
    guard output.availableMetadataObjectTypes.contains(.qr) else { return false }
    output.metadataObjectTypes = [.qr]
    output.setMetadataObjectsDelegate(delegate, queue: .main)
    return true
  }

  /// Turns the camera off and lets go of it and of the delegate.
  private static func tearDown(_ session: AVCaptureSession) {
    session.stopRunning()
    session.beginConfiguration()
    session.inputs.forEach(session.removeInput)
    session.outputs.forEach(session.removeOutput)
    session.commitConfiguration()
  }

  func stop() {
    done = true
    QrCameraView.views.removeObject(forKey: NSNumber(value: id))
    let session = self.session
    queue.async { QrCameraView.tearDown(session) }
  }

  /// The first code read goes to the Dart side, on the main queue.
  fileprivate func read(_ metadataObjects: [AVMetadataObject]) {
    guard !done,
      let text = metadataObjects.lazy
        .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first
    else { return }
    // One code per view: the camera stops at once.
    stop()
    channel.invokeMethod("code", arguments: ["view": id, "text": text])
  }
}

/// Hands what the camera reads to its view without keeping the view:
/// AVCaptureMetadataOutput may hold its delegate strongly.
private final class CodeReader: NSObject, AVCaptureMetadataOutputObjectsDelegate {
  weak var view: QrCameraView?

  func metadataOutput(
    _ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    view?.read(metadataObjects)
  }
}

/// A view whose layer is the camera's live picture, turned the way the app's
/// screen is.
final class CameraPreview: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let connection = previewLayer.connection,
      let orientation = window?.windowScene?.interfaceOrientation
    else { return }
    if #available(iOS 17.0, *) {
      let angle: CGFloat
      switch orientation {
      case .landscapeRight: angle = 0
      case .landscapeLeft: angle = 180
      case .portraitUpsideDown: angle = 270
      default: angle = 90
      }
      if connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle
      }
    } else if connection.isVideoOrientationSupported {
      switch orientation {
      case .landscapeRight: connection.videoOrientation = .landscapeRight
      case .landscapeLeft: connection.videoOrientation = .landscapeLeft
      case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
      default: connection.videoOrientation = .portrait
      }
    }
  }
}
