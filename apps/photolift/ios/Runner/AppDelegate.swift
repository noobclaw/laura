import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// The AI upscaler and the photo picker / Photos writer live in this app
  /// target (no third-party plugin) — see UpscaleBridge.swift / MediaBridge.swift,
  /// the counterparts of the Kotlin bridges on Android.
  private var upscale: UpscaleBridge?
  private var media: MediaBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoLiftBridges")
    if let messenger = registrar?.messenger() {
      upscale = UpscaleBridge(messenger: messenger)
      media = MediaBridge(messenger: messenger)
    }
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    upscale?.dispose()
    upscale = nil
    media?.dispose()
    media = nil
    super.applicationWillTerminate(application)
  }
}
