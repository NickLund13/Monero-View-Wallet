import Flutter
import LocalAuthentication
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The app's own native code, registered like a plugin so it hears about
    // files opened with the app.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeyImagesFile") {
      KeyImagesFile.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppLock") {
      AppLock.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InAppTor") {
      InAppTor.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QrCamera") {
      QrCamera.register(with: registrar)
    }
  }
}

/// The app's lock (lib/lock.dart): Face ID, Touch ID or the passcode through
/// Apple's LocalAuthentication, and a cover over the app while it isn't
/// active. The app only learns whether a check passed; the face, fingerprint
/// and passcode stay with iOS.
final class AppLock: NSObject, FlutterPlugin {
  /// Hides the app while it isn't active: iOS takes the app switcher's
  /// snapshot then, and it must never show the balance. It stays on after the
  /// app is active again until the Dart side has drawn the app as it is now,
  /// the lock screen if the app locked: until then the app still shows what
  /// it showed before it went away.
  private var cover: UIView?

  static func register(with registrar: FlutterPluginRegistrar) {
    let lock = AppLock()
    registrar.addMethodCallDelegate(
      lock,
      channel: FlutterMethodChannel(
        name: "monero_view_wallet/lock", binaryMessenger: registrar.messenger()))
    let center = NotificationCenter.default
    center.addObserver(
      lock, selector: #selector(AppLock.sceneWillDeactivate(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    center.addObserver(
      lock, selector: #selector(AppLock.sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "kind":
      result(Self.kind())
    case "ask":
      let arguments = call.arguments as? [String: Any]
      Self.ask(
        reason: arguments?["reason"] as? String ?? "Unlock your wallet",
        passcode: arguments?["passcode"] as? Bool ?? true,
        result: result)
    case "uncover":
      // Only while the app is active: one that went away again since keeps
      // its cover for the snapshot.
      if UIApplication.shared.applicationState == .active {
        uncover()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// "faceID" or "touchID" when that can be used, "passcode" when only the
  /// passcode can, and "none" only when the iPhone has no passcode, so the app
  /// can't lock.
  private static func kind() -> String {
    let context = LAContext()
    var biometricError: NSError?
    let biometric = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &biometricError)
    // Locked out after too many tries still counts: the lock screen says so.
    if biometric || biometricError?.code == LAError.Code.biometryLockout.rawValue {
      switch context.biometryType {
      case .faceID: return "faceID"
      case .touchID: return "touchID"
      default: break
      }
    }
    var passcodeError: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &passcodeError) {
      return "passcode"
    }
    return passcodeError?.code == LAError.Code.passcodeNotSet.rawValue ? "none" : "passcode"
  }

  /// Face ID or Touch ID, or with [passcode] the passcode, which iOS may start
  /// with Face ID or Touch ID. Answers with a CheckResult name.
  private static func ask(reason: String, passcode: Bool, result: @escaping FlutterResult) {
    let context = LAContext()
    let policy: LAPolicy
    if passcode {
      policy = .deviceOwnerAuthentication
    } else {
      policy = .deviceOwnerAuthenticationWithBiometrics
      // No "Enter Password" on the Face ID sheet: the lock screen has its own
      // Use passcode.
      context.localizedFallbackTitle = ""
    }
    context.evaluatePolicy(policy, localizedReason: reason) { passed, error in
      let answer = passed ? "ok" : Self.answer(for: error)
      DispatchQueue.main.async { result(answer) }
    }
  }

  private static func answer(for error: Error?) -> String {
    guard let error = error as? LAError else { return "failed" }
    switch error.code {
    case .userCancel, .systemCancel, .appCancel, .userFallback, .notInteractive:
      return "cancelled"
    case .biometryLockout:
      return "lockedOut"
    case .biometryNotAvailable, .biometryNotEnrolled:
      return "unavailable"
    case .passcodeNotSet:
      return "noPasscode"
    default:
      return "failed"
    }
  }

  @objc private func sceneWillDeactivate(_ notification: Notification) {
    guard cover == nil, let scene = notification.object as? UIWindowScene,
      let window = scene.keyWindow ?? scene.windows.first
    else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // The app's background color (docs/design/DESIGN.md, bg), and nothing on it.
    view.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0x10 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1)
        : UIColor(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF1 / 255, alpha: 1)
    }
    window.addSubview(view)
    cover = view
  }

  /// The Dart side asks for the cover to come off once it has drawn a frame
  /// (lib/lock.dart). If it never does, the cover comes off by itself.
  @objc private func sceneDidActivate(_ notification: Notification) {
    let shown = cover
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, let shown, self.cover === shown,
        UIApplication.shared.applicationState == .active
      else { return }
      self.uncover()
    }
  }

  private func uncover() {
    cover?.removeFromSuperview()
    cover = nil
  }
}
