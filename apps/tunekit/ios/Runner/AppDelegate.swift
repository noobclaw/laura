import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Microphone capture + sample-accurate metronome live in this app target
  /// (no third-party audio plugin) — see AudioBridge.swift, the counterpart
  /// of the Kotlin bridge on Android.
  private var audio: AudioBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TuneBenchAudio")
    if let messenger = registrar?.messenger() {
      audio = AudioBridge(messenger: messenger)
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    audio?.dispose()
    audio = nil
    super.applicationWillTerminate(application)
  }
}
