import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'geo_format.dart';
import 'models.dart';
import 'pro.dart';
import 'sensors.dart';
import 'store.dart';
import 'watermark.dart';

/// The main viewfinder: live camera preview, a real-time info band showing the
/// current GPS/bearing/time/project, and a shutter that burns those values into
/// the captured photo's pixels.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.store, required this.sensors});

  final FieldStampStore store;
  final SensorHub sensors;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _cameraError;

  /// True when the error is a permission refusal, which gets a "Settings"
  /// button instead of a pointless "Retry".
  bool _cameraDenied = false;
  bool _capturing = false;

  /// Only one initialisation may be in flight. The permission prompt that
  /// `initialize()` itself raises sends the app inactive → resumed while
  /// the first call is still pending; without this guard `resumed` started a
  /// second controller and the two raced for the device (black preview,
  /// error page, or a leaked session — 2026-09-02 audit R2).
  Future<void>? _initFuture;
  int _initGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() {
    final inFlight = _initFuture;
    if (inFlight != null) return inFlight;
    final f = _doInitCamera();
    _initFuture = f;
    return f.whenComplete(() {
      if (identical(_initFuture, f)) _initFuture = null;
    });
  }

  Future<void> _doInitCamera() async {
    final gen = ++_initGen;
    // Drop whatever controller exists before making a new one, so there is
    // never a moment with two live sessions.
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose();
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _fail(tr(zh: '此设备上未找到相机', en: 'No camera found on this device'));
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        // camera_avfoundation maps veryHigh to 1080p while camera_android
        // gives 2160p; ultraHigh brings iOS up to the same 4K evidence frame.
        Platform.isIOS ? ResolutionPreset.ultraHigh : ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (gen != _initGen || !mounted) {
        // Superseded (e.g. the screen went to the background meanwhile);
        // make sure the orphan releases the device.
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraError = null;
        _cameraDenied = false;
      });
    } on CameraException catch (e) {
      if (gen != _initGen) return;
      // Codes from camera_android_camerax / camera_avfoundation.
      const denied = {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
        'cameraPermission',
      };
      if (denied.contains(e.code)) {
        _fail(
          tr(
            zh: '未授予相机权限。FieldStamp 需要相机才能拍摄取证照片。',
            en: 'Camera permission not granted. FieldStamp needs the camera '
                'to take stamped photos.',
          ),
          denied: true,
        );
      } else {
        _fail(tr(
          zh: '相机不可用:${e.description ?? e.code}',
          en: 'Camera unavailable: ${e.description ?? e.code}',
        ));
      }
    } catch (e) {
      if (gen != _initGen) return;
      _fail(tr(zh: '相机不可用:$e', en: 'Camera unavailable: $e'));
    }
  }

  void _fail(String message, {bool denied = false}) {
    if (!mounted) return;
    setState(() {
      _cameraError = message;
      _cameraDenied = denied;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` also fires for the permission dialog and the notification
    // shade; tearing the camera down for those caused the double-init race.
    // Only a real trip to the background releases the device.
    if (state == AppLifecycleState.paused) {
      _initGen++; // invalidate any init still in flight
      // ...and forget its future, or `resumed` would await a controller that
      // the generation check is about to throw away and spin forever.
      _initFuture = null;
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) _initCamera();
      // The user may have just flipped the switch we asked them to.
      if (!widget.sensors.locationReady) widget.sensors.retryLocation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final reading = widget.sensors.snapshot();
      final xfile = await c.takePicture();
      final bytes = await xfile.readAsBytes();
      final StampPhoto? photo;
      try {
        final stamped = await burnWatermark(bytes, _watermarkFor(reading));
        photo = await widget.store
            .saveCapture(stamped, reading, widget.store.currentProjectId);
      } finally {
        // The plugin leaves the unstamped original in the cache directory;
        // an evidence camera must not keep a second, un-watermarked copy
        // of every photo lying around. Removed only once the stamped copy
        // had its chance to land, so a failed save does not lose the shot.
        unawaited(File(xfile.path).delete().catchError((_) => File(xfile.path)));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(photo == null
            ? tr(zh: '照片保存失败', en: 'Could not save photo')
            : reading.hasFix
                ? tr(zh: '已保存,含 GPS 水印', en: 'Saved with GPS stamp')
                : tr(zh: '已保存 — 尚未获得 GPS 定位', en: 'Saved — no GPS fix yet')),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
                content:
                    Text(tr(zh: '拍摄失败:$e', en: 'Capture failed: $e'))));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // NOTE: watermark text is burned into the photo as evidence — its labels and
  // formats deliberately stay fixed (English/units) regardless of UI locale.
  WatermarkContent _watermarkFor(StampReading r) {
    final store = widget.store;
    final acc =
        r.accuracy != null ? '   ±${r.accuracy!.toStringAsFixed(0)}m' : '';
    return WatermarkContent(
      lines: [
        formatLatLon(r.latitude, r.longitude, store.coordFormat),
        'Alt ${formatAltitude(r.altitude, store.altUnit)}   '
            'Bearing ${formatHeading(r.heading)}$acc',
        formatTimestamp(r.time),
        store.projectName(store.currentProjectId),
      ],
      appTag: store.pro ? null : 'FieldStamp',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _projectBar(),
        Expanded(
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _previewLayer(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _liveInfoBand(),
                ),
              ],
            ),
          ),
        ),
        _shutterBar(),
      ],
    );
  }

  Widget _previewLayer() {
    final c = _controller;
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 56),
              const SizedBox(height: 12),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (_cameraDenied)
                    FilledButton.icon(
                      onPressed: SensorHub.openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(tr(zh: '去系统设置', en: 'Open Settings')),
                    ),
                  FilledButton.tonal(
                    onPressed: _initCamera,
                    child: Text(tr(zh: '重试', en: 'Retry')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.previewSize?.height ?? 1,
        height: c.value.previewSize?.width ?? 1,
        child: CameraPreview(c),
      ),
    );
  }

  Widget _projectBar() {
    final store = widget.store;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => InkWell(
          onTap: () => _pickProject(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.projectName(store.currentProjectId),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.expand_more, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveInfoBand() {
    final store = widget.store;
    return AnimatedBuilder(
      animation: Listenable.merge([widget.sensors, store]),
      builder: (context, _) {
        final r = widget.sensors.snapshot();
        final acc = r.accuracy != null
            ? '±${r.accuracy!.toStringAsFixed(0)}m'
            : '';
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            border: const Border(left: BorderSide(color: Color(0xFF2E7D32), width: 4)),
            color: Colors.black.withValues(alpha: 0.55),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    r.hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                    size: 16,
                    color: r.hasFix ? const Color(0xFF69F0AE) : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      formatLatLon(r.latitude, r.longitude, store.coordFormat,
                          noFix: tr(zh: '尚未定位', en: 'No GPS fix')),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (acc.isNotEmpty)
                    Text(acc,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                // On-screen only — the burned-in watermark keeps its own
                // fixed English labels (see _watermarkFor).
                '${tr(zh: '海拔', en: 'Alt')} ${formatAltitude(r.altitude, store.altUnit)}   '
                '${tr(zh: '方位', en: 'Bearing')} ${formatHeading(r.heading)}   '
                '${formatTimestamp(r.time)}',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              if (widget.sensors.locationError != null) ...[
                const SizedBox(height: 8),
                _LocationIssue(sensors: widget.sensors),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _shutterBar() {
    final ready = _controller?.value.isInitialized ?? false;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: GestureDetector(
          onTap: ready && !_capturing ? _capture : null,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ready
                  ? const Color(0xFF2E7D32)
                  : Theme.of(context).disabledColor,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: _capturing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  )
                : const Icon(Icons.camera_alt, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }

  Future<void> _pickProject(BuildContext context) async {
    final store = widget.store;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: store,
        builder: (ctx, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr(zh: '项目 / 工单', en: 'Project / work order'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...store.projects.map((p) => ListTile(
                    leading: Icon(p.id == store.currentProjectId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked),
                    title: Text(p.name),
                    onTap: () {
                      store.selectProject(p.id);
                      Navigator.pop(ctx);
                    },
                  )),
              const Divider(height: 1),
              ListTile(
                leading: Icon(store.pro ? Icons.add : Icons.lock_outline),
                title: Text(store.pro
                    ? tr(zh: '新建项目', en: 'New project')
                    : tr(zh: '新建项目(Pro)', en: 'New project (Pro)')),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!store.pro) {
                    showProSheet(context,
                        reason: tr(
                            zh: '免费版只有一个项目,多项目 / 工单是 Pro 功能。',
                            en: 'The free tier has one project; multiple projects are a Pro feature.'));
                    return;
                  }
                  final name = await _promptName(context);
                  if (name != null && name.trim().isNotEmpty) {
                    store.addProject(name);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptName(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(zh: '新建项目', en: 'New project')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: tr(zh: '例如:幸福路12号巡检', en: 'e.g. 12 Elm St inspection'),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(zh: '取消', en: 'Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr(zh: '创建', en: 'Create'))),
      ],
    ),
  );
}

/// The positioning problem, with the one button that fixes it. Replaces the
/// 11 px orange line that told users "permission denied" and left them there.
class _LocationIssue extends StatelessWidget {
  const _LocationIssue({required this.sensors});

  final SensorHub sensors;

  @override
  Widget build(BuildContext context) {
    final state = sensors.locationState;
    final message = sensors.locationError ?? '';
    String? hint;
    String? action;
    VoidCallback? onAction;
    switch (state) {
      case LocationState.serviceOff:
        hint = tr(zh: '打开系统定位开关后会自动恢复。', en: 'Turn on location and it will resume.');
        action = tr(zh: '打开定位设置', en: 'Location settings');
        onAction = SensorHub.openLocationSettings;
      case LocationState.deniedForever:
        hint = tr(
          zh: '请在系统设置里允许 FieldStamp 使用定位。',
          en: 'Allow FieldStamp to use location in Settings.',
        );
        action = tr(zh: '去系统设置', en: 'Open Settings');
        onAction = SensorHub.openAppSettings;
      case LocationState.denied:
        hint = tr(zh: '没有定位,照片只会烧入时间。', en: 'Without it photos carry only a timestamp.');
        action = tr(zh: '重新申请', en: 'Ask again');
        onAction = sensors.retryLocation;
      case LocationState.error:
        hint = sensors.locationDetail;
        action = tr(zh: '重试', en: 'Retry');
        onAction = sensors.retryLocation;
      case LocationState.ok:
        // Stale fix: keep the last coordinates visible above, explain here.
        final s = sensors.secondsSinceFix;
        hint = s == null
            ? null
            : tr(
                zh: '上次定位 ${s ~/ 60} 分钟前;在此之前拍的照片不会烧入坐标。',
                en: 'Last fix ${s ~/ 60} min ago; photos taken now carry no coordinates.',
              );
      case LocationState.pending:
        break;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined, size: 18, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                if (hint != null)
                  Text(hint,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onAction,
              child: Text(action),
            ),
          ],
        ],
      ),
    );
  }
}
