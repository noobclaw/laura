import Flutter
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// iOS half of the `photolift/upscale` channel — the counterpart of
/// android/.../UpscaleBridge.kt, speaking the same contract so the Dart side
/// (lib/tool/native_upscaler.dart) does not know which platform it is on.
///
/// Methods:
///  - `capabilities` -> {native: Bool}
///  - `upscale` {jobId, inputPath, outputPath, scale(2|4), model, useGpu, tag,
///               tagText, maxOutPixels, maxOutLongEdge}
///       -> {outputPath, outWidth, outHeight, inWidth, inHeight, downscaled,
///           engine: "ncnn-cpu", elapsedMs}
///       errors: busy | engine_load_failed | decode_failed | too_large |
///               inference_failed | write_failed | cancelled
///  - `cancel` -> nil
/// Events on `photolift/upscale/progress`: {jobId, done, total, stage}
///
/// The bundled ncnn build is CPU-only (see PLAN.md for the MoltenVK plan), so
/// `useGpu` is accepted and ignored and `engine` always reports "ncnn-cpu".
final class UpscaleBridge: NSObject, FlutterStreamHandler {
  private static let methodChannelName = "photolift/upscale"
  private static let eventChannelName = "photolift/upscale/progress"

  /// Un-padded tile edge in input pixels; overlap is replicated context.
  private static let tileCpu = 192
  private static let overlap = 12
  private static let jpegQuality = 0.94

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private let queue = DispatchQueue(label: "com.noobclaw.photolift.upscale", qos: .userInitiated)

  private var busy = false
  private var cancelRequested = false
  private var engine: PhotoLiftEngine?
  private var engineKey: String?

  private struct JobError: Error {
    let code: String
    let message: String
  }

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  func dispose() {
    cancelRequested = true
    engine?.cancel()
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  // MARK: FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ jobId: String, _ done: Int, _ total: Int, _ stage: String) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?(["jobId": jobId, "done": done, "total": total, "stage": stage])
    }
  }

  // MARK: Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      result(["native": true])
    case "cancel":
      cancelRequested = true
      engine?.cancel()
      result(nil)
    case "upscale":
      startJob(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startJob(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !busy else {
      result(FlutterError(code: "busy", message: "another upscale is running", details: nil))
      return
    }
    guard let args = call.arguments as? [String: Any],
          let inputPath = args["inputPath"] as? String,
          let outputPath = args["outputPath"] as? String,
          let scale = args["scale"] as? Int, scale == 2 || scale == 4 else {
      result(FlutterError(code: "bad_args", message: "inputPath/outputPath/scale required", details: nil))
      return
    }
    let jobId = args["jobId"] as? String ?? "job"
    let model = args["model"] as? String ?? "general-x4v3-dn0"
    let tag = args["tag"] as? Bool ?? false
    let tagText = args["tagText"] as? String ?? "PhotoLift"
    let maxOutPixels = (args["maxOutPixels"] as? NSNumber)?.int64Value ?? 24_000_000
    let maxOutLongEdge = args["maxOutLongEdge"] as? Int ?? 8192

    busy = true
    cancelRequested = false
    queue.async { [weak self] in
      guard let self = self else { return }
      let outcome: Result<[String: Any], Error> = Result {
        try self.runJob(jobId: jobId, inputPath: inputPath, outputPath: outputPath, scale: scale,
                        model: model, tag: tag, tagText: tagText,
                        maxOutPixels: maxOutPixels, maxOutLongEdge: maxOutLongEdge)
      }
      DispatchQueue.main.async {
        self.busy = false
        switch outcome {
        case .success(let map):
          result(map)
        case .failure(let e):
          if let je = e as? JobError {
            result(FlutterError(code: je.code, message: je.message, details: nil))
          } else {
            result(FlutterError(code: "inference_failed", message: "\(e)", details: nil))
          }
        }
      }
    }
  }

  // MARK: Engine

  private func ensureEngine(model: String) throws -> PhotoLiftEngine {
    let key = model
    if let e = engine, engineKey == key { return e }
    engine = nil
    let paramKey = FlutterDartProject.lookupKey(forAsset: "assets/models/\(model).param")
    let binKey = FlutterDartProject.lookupKey(forAsset: "assets/models/\(model).bin")
    guard let paramPath = Bundle.main.path(forResource: paramKey, ofType: nil),
          let binPath = Bundle.main.path(forResource: binKey, ofType: nil) else {
      throw JobError(code: "engine_load_failed", message: "model assets missing for \(model)")
    }
    let e = PhotoLiftEngine()
    guard e.loadParam(paramPath, bin: binPath, preferGpu: false) else {
      throw JobError(code: "engine_load_failed", message: "could not load \(model)")
    }
    engine = e
    engineKey = key
    return e
  }

  /// Fit the input so the output stays inside the pixel / long-edge caps.
  private func fitInput(w: Int, h: Int, scale: Int, maxOutPixels: Int64, maxOutLongEdge: Int) -> (Int, Int) {
    let maxInLong = maxOutLongEdge / scale
    let maxInPixels = maxOutPixels / Int64(scale * scale)
    var f = 1.0
    let longEdge = max(w, h)
    if longEdge > maxInLong { f = min(f, Double(maxInLong) / Double(longEdge)) }
    let px = Int64(w) * Int64(h)
    if px > maxInPixels { f = min(f, (Double(maxInPixels) / Double(px)).squareRoot()) }
    if f >= 1.0 { return (w, h) }
    return (max(1, Int(Double(w) * f)), max(1, Int(Double(h) * f)))
  }

  private func runJob(jobId: String, inputPath: String, outputPath: String, scale: Int,
                      model: String, tag: Bool, tagText: String,
                      maxOutPixels: Int64, maxOutLongEdge: Int) throws -> [String: Any] {
    let t0 = Date()
    emit(jobId, 0, 1, "decode")

    // ImageIO decodes straight to the fitted size with the EXIF transform
    // applied — no full-resolution UIImage ever sits in memory.
    let url = URL(fileURLWithPath: inputPath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          var origW = props[kCGImagePropertyPixelWidth] as? Int,
          var origH = props[kCGImagePropertyPixelHeight] as? Int, origW > 0, origH > 0 else {
      throw JobError(code: "decode_failed", message: "not an image")
    }
    if let o = props[kCGImagePropertyOrientation] as? UInt32, o >= 5 { swap(&origW, &origH) }
    let (targetW, targetH) = fitInput(w: origW, h: origH, scale: scale,
                                      maxOutPixels: maxOutPixels, maxOutLongEdge: maxOutLongEdge)
    let downscaled = targetW != origW || targetH != origH
    let thumbOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: max(targetW, targetH),
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
      throw JobError(code: "decode_failed", message: "decode failed")
    }
    if cancelRequested { throw JobError(code: "cancelled", message: "cancelled") }

    // Draw into a tightly packed RGBX buffer — the layout the core expects.
    let inW = cg.width
    let inH = cg.height
    let inStride = inW * 4
    guard let inBuf = calloc(inH, inStride) else {
      throw JobError(code: "too_large", message: "input allocation failed")
    }
    defer { free(inBuf) }
    let space = CGColorSpaceCreateDeviceRGB()
    let rgbx = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let inCtx = CGContext(data: inBuf, width: inW, height: inH, bitsPerComponent: 8,
                                bytesPerRow: inStride, space: space, bitmapInfo: rgbx) else {
      throw JobError(code: "decode_failed", message: "context failed")
    }
    inCtx.interpolationQuality = .high
    inCtx.draw(cg, in: CGRect(x: 0, y: 0, width: inW, height: inH))

    let engine = try ensureEngine(model: model)
    let tile = Self.tileCpu
    let total = max(1, Int(engine.tileCount(forWidth: Int32(inW), height: Int32(inH), tile: Int32(tile))))
    emit(jobId, 0, total, "infer")

    let outW = inW * scale
    let outH = inH * scale
    let outStride = outW * 4
    guard let outBuf = calloc(outH, outStride) else {
      throw JobError(code: "too_large", message: "not enough memory for \(outW)x\(outH)")
    }
    defer { free(outBuf) }

    let rc = engine.processRGBA(inBuf.assumingMemoryBound(to: UInt8.self), width: Int32(inW), height: Int32(inH),
                                inStride: Int32(inStride),
                                output: outBuf.assumingMemoryBound(to: UInt8.self), outStride: Int32(outStride),
                                scale: Int32(scale), tile: Int32(tile), overlap: Int32(Self.overlap)) { [weak self] done, t in
      self?.emit(jobId, Int(done), Int(t), "infer")
    }
    if rc == PhotoLiftErrCancelled || cancelRequested {
      throw JobError(code: "cancelled", message: "cancelled")
    }
    if rc != PhotoLiftErrOk {
      throw JobError(code: "inference_failed", message: PhotoLiftEngine.describeError(rc))
    }

    guard let outCtx = CGContext(data: outBuf, width: outW, height: outH, bitsPerComponent: 8,
                                 bytesPerRow: outStride, space: space, bitmapInfo: rgbx) else {
      throw JobError(code: "write_failed", message: "output context failed")
    }
    if tag { drawTag(in: outCtx, width: outW, height: outH, text: tagText) }

    emit(jobId, total, total, "encode")
    guard let outImage = outCtx.makeImage() else {
      throw JobError(code: "write_failed", message: "makeImage failed")
    }
    let outURL = URL(fileURLWithPath: outputPath)
    let tmpURL = URL(fileURLWithPath: outputPath + ".tmp")
    try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw JobError(code: "write_failed", message: "destination failed")
    }
    CGImageDestinationAddImage(dest, outImage, [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      try? FileManager.default.removeItem(at: tmpURL)
      throw JobError(code: "write_failed", message: "JPEG encode failed")
    }
    do {
      if FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.removeItem(at: outURL)
      }
      try FileManager.default.moveItem(at: tmpURL, to: outURL)
    } catch {
      throw JobError(code: "write_failed", message: "\(error)")
    }

    return [
      "outputPath": outputPath,
      "outWidth": outW,
      "outHeight": outH,
      "inWidth": inW,
      "inHeight": inH,
      "downscaled": downscaled,
      "engine": "ncnn-cpu",
      "elapsedMs": Int(Date().timeIntervalSince(t0) * 1000),
    ]
  }

  /// Free-tier corner tag: a small translucent pill with the app name.
  private func drawTag(in ctx: CGContext, width: Int, height: Int, text: String) {
    let textSize = max(18.0, Double(width) * 0.022)
    let font = UIFont.systemFont(ofSize: textSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let padX = textSize * 0.7
    let padY = textSize * 0.45
    let margin = Double(width) * 0.02
    let rect = CGRect(x: Double(width) - margin - size.width - padX * 2,
                      y: Double(height) - margin - size.height - padY * 2,
                      width: size.width + padX * 2, height: size.height + padY * 2)
    UIGraphicsPushContext(ctx)
    // CGContext is bottom-up; flip so UIKit text draws upright.
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
    UIBezierPath(roundedRect: rect, cornerRadius: textSize * 0.6).fill()
    str.draw(at: CGPoint(x: rect.minX + padX, y: rect.minY + padY))
    ctx.restoreGState()
    UIGraphicsPopContext()
  }
}
