import Flutter
import Foundation
import ImageIO
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// iOS half of the `photolift/media` channel — counterpart of
/// android/.../MediaBridge.kt.
///
///  - `pick` -> {path, width, height} | nil (user cancelled)
///       PHPickerViewController runs out of process, so no photo-library
///       permission is requested; the picked file is copied into the app's
///       caches directory. Dimensions honour EXIF rotation.
///       errors: picker_unavailable | copy_failed
///  - `saveToGallery` {path, displayName} -> true
///       Add-only Photos access (NSPhotoLibraryAddUsageDescription).
///       errors: permission_denied | save_failed
///  - `openSettings` -> nil  (deep link to this app's page in Settings)
final class MediaBridge: NSObject, PHPickerViewControllerDelegate {
  private static let channelName = "photolift/media"

  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
    pending = nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(result)
    case "saveToGallery":
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        result(FlutterError(code: "save_failed", message: "path required", details: nil))
        return
      }
      saveToGallery(path: path, result: result)
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var topViewController: UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: Pick

  private func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "picker_unavailable", message: "picker already open", details: nil))
      return
    }
    guard let host = topViewController else {
      result(FlutterError(code: "picker_unavailable", message: "no view controller", details: nil))
      return
    }
    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    pending = result
    host.present(picker, animated: true)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let result = pending else { return }
    pending = nil
    guard let item = results.first?.itemProvider else {
      result(nil)
      return
    }
    // loadFileRepresentation hands us a temp URL valid only inside the
    // closure, so the copy happens right there.
    item.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
      let outcome: Result<[String: Any], Error> = Result {
        guard let url = url else { throw error ?? NSError(domain: "PhotoLift", code: 1) }
        return try Self.copyIntoCache(url)
      }
      DispatchQueue.main.async {
        switch outcome {
        case .success(let map): result(map)
        case .failure(let e):
          result(FlutterError(code: "copy_failed", message: "\(e)", details: nil))
        }
      }
    }
  }

  private static func copyIntoCache(_ src: URL) throws -> [String: Any] {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let dir = caches.appendingPathComponent("picked", isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let ext = src.pathExtension.isEmpty ? "jpg" : src.pathExtension.lowercased()
    let dest = dir.appendingPathComponent("picked_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
    try FileManager.default.copyItem(at: src, to: dest)
    guard let source = CGImageSourceCreateWithURL(dest as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          var w = props[kCGImagePropertyPixelWidth] as? Int,
          var h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else {
      try? FileManager.default.removeItem(at: dest)
      throw NSError(domain: "PhotoLift", code: 2, userInfo: [NSLocalizedDescriptionKey: "not an image"])
    }
    if let o = props[kCGImagePropertyOrientation] as? UInt32, o >= 5 { swap(&w, &h) }
    return ["path": dest.path, "width": w, "height": h]
  }

  // MARK: Save

  private func saveToGallery(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "save_failed", message: "file missing", details: nil))
      return
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "photo library add access denied", details: nil))
        }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
      }) { ok, error in
        DispatchQueue.main.async {
          if ok {
            result(true)
          } else {
            result(FlutterError(code: "save_failed", message: error?.localizedDescription ?? "unknown", details: nil))
          }
        }
      }
    }
  }
}
