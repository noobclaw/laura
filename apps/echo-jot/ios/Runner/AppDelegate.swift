import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// On-device dictation lives in this app target (no third-party speech
  /// plugin) — see DictationBridge.swift, the counterpart of the Kotlin
  /// bridge on Android.
  private var dictation: DictationBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "EchoJotDictation")
    if let messenger = registrar?.messenger() {
      dictation = DictationBridge(messenger: messenger)
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    dictation?.dispose()
    dictation = nil
    super.applicationWillTerminate(application)
  }
}
