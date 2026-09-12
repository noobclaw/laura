import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'geo_format.dart';
import 'models.dart';
import 'motion.dart';
import 'pro.dart';
import 'sensors.dart';
import 'store.dart';
import 'watermark.dart';

/// The main viewfinder: live camera preview, a real-time info band showing the
/// current GPS/bearing/time/project, and a shutter that burns those values into
/// the captured photo's pixels.
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.store,
    required this.sensors,
    this.onOpenGallery,
  });

  final FieldStampStore store;
  final SensorHub sensors;

  /// Tapping the last-photo thumbnail beside the shutter jumps to the gallery.
  final VoidCallback? onOpenGallery;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  String? _cameraError;

  /// True when the error is a permission refusal, which gets a "Settings"
  /// button instead of a pointless "Retry".
  bool _cameraDenied = false;
  bool _capturing = false;

  // --- signature motion -------------------------------------------------
  /// Iris blades on the shutter: forward = shut (120 ms), reverse = open
  /// (200 ms). Held shut for the whole capture so the button reads "busy".
  late final AnimationController _aperture = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
    reverseDuration: const Duration(milliseconds: 200),
  );

  /// One breath of the corner brackets whenever GPS quality changes bucket.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _pulseScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.10), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.10, end: 1), weight: 60),
  ]).animate(CurvedAnimation(parent: _pulse, curve: Motion.standard));

  /// Slow continuous breathing while there is no fix at all ("searching").
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  late final Animation<double> _breathAlpha =
      Tween<double>(begin: 0.45, end: 1).animate(
    CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
  );

  bool _pressed = false;
  bool _flash = false;
  int _lastBucket = -1;

  /// The photo currently flying from the shutter to the gallery entry, and
  /// the one shown there once it lands.
  StampPhoto? _flyPhoto;
  StampPhoto? _lastPhoto;
  bool _reduceMotion = false;

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
    widget.sensors.addListener(_onSensors);
    widget.store.addListener(_onStore);
    _onStore();
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _breath.stop();
      _breath.value = 1;
    }
  }

  /// Corner brackets breathe once when the GPS quality bucket changes.
  void _onSensors() {
    final r = widget.sensors.snapshot();
    final bucket = Motion.accuracyBucket(r.accuracy, hasFix: r.hasFix);
    if (bucket == _lastBucket) return;
    final first = _lastBucket == -1;
    _lastBucket = bucket;
    if (_reduceMotion) return;
    if (bucket == 0) {
      _breath.repeat(reverse: true);
    } else {
      _breath.animateTo(1, duration: const Duration(milliseconds: 300));
    }
    if (!first) _pulse.forward(from: 0);
  }

  /// Keep the gallery entry showing the newest photo of the current project
  /// (project switches, deletions) — unless one is mid-flight.
  void _onStore() {
    if (_flyPhoto != null) return;
    final list = widget.store.photosForProject(widget.store.currentProjectId);
    final newest = list.isEmpty ? null : list.first;
    if (newest?.id != _lastPhoto?.id) {
      _lastPhoto = newest;
      if (mounted) setState(() {});
    }
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
            zh: '未授予相机权限。SiteStamp 需要相机才能拍摄取证照片。',
            en: 'Camera permission not granted. SiteStamp needs the camera '
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
    widget.sensors.removeListener(_onSensors);
    widget.store.removeListener(_onStore);
    _aperture.dispose();
    _pulse.dispose();
    _breath.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    // Iris shuts (120 ms) and stays shut until the stamped file has landed.
    unawaited(_aperture.forward());
    try {
      final reading = widget.sensors.snapshot();
      final xfile = await c.takePicture();
      _fireFlash();
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
      if (photo != null) {
        // The new thumbnail lifts off the shutter and lands on the gallery
        // entry at bottom-right; `_onStore` is muted while it is airborne.
        setState(() => _flyPhoto = photo);
      }
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
      if (mounted) {
        setState(() => _capturing = false);
        unawaited(_aperture.reverse());
      }
    }
  }

  /// 80 ms full-viewfinder white flash on capture.
  void _fireFlash() {
    if (!mounted || _reduceMotion) return;
    setState(() => _flash = true);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _landFlight() {
    if (!mounted) return;
    setState(() {
      _lastPhoto = _flyPhoto ?? _lastPhoto;
      _flyPhoto = null;
    });
    _onStore();
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
      appTag: store.pro ? null : 'SiteStamp',
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
                if (_cameraError == null) _cornerBrackets(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _liveInfoBand(),
                ),
                // Capture flash: 80 ms of white over the whole viewfinder.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _flash ? 1 : 0,
                    duration: Motion.of(context, 80),
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        _shutterBar(),
      ],
    );
  }

  /// Four L-shaped frame corners. Colour follows GPS quality (green good /
  /// orange poor / dim white none); they breathe once on a quality change
  /// and pulse slowly while still searching for a fix.
  Widget _cornerBrackets() {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: widget.sensors,
        builder: (context, _) {
          final r = widget.sensors.snapshot();
          final bucket = Motion.accuracyBucket(r.accuracy, hasFix: r.hasFix);
          final color = Motion.accuracyColor(bucket);
          return AnimatedBuilder(
            animation: Listenable.merge([_pulseScale, _breathAlpha]),
            builder: (context, _) => Opacity(
              opacity: bucket == 0 ? _breathAlpha.value : 1,
              child: Transform.scale(
                scale: _pulseScale.value,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 118),
                  child: Stack(
                    children: [
                      for (final a in const [
                        Alignment.topLeft,
                        Alignment.topRight,
                        Alignment.bottomLeft,
                        Alignment.bottomRight,
                      ])
                        Align(
                          alignment: a,
                          child: CornerBracket(color: color, alignment: a),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
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
        final bucket = Motion.accuracyBucket(r.accuracy, hasFix: r.hasFix);
        final accColor = Motion.accuracyColor(bucket);
        // 5 m or better is pin-sharp; 60 m fills the whole ring.
        final accFill = r.accuracy == null
            ? 1.0
            : ((r.accuracy! - 5) / 55).clamp(0.0, 1.0);
        const coordStyle = TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            fontFeatures: [FontFeature.tabularFigures()]);
        const subStyle = TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()]);
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            border: Border(
                left: BorderSide(
                    color: r.hasFix
                        ? const Color(0xFF2E7D32)
                        : Motion.safetyOrange,
                    width: 4)),
            color: Colors.black.withValues(alpha: 0.55),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Accuracy circle: safety orange, core grows with error.
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: accFill),
                    duration: Motion.of(context, 400),
                    curve: Motion.standard,
                    builder: (context, fill, _) => CustomPaint(
                      size: const Size(18, 18),
                      painter: AccuracyRingPainter(
                        fill: fill,
                        color: r.hasFix ? Motion.safetyOrange : Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RollingText(
                      text: formatLatLon(
                          r.latitude, r.longitude, store.coordFormat,
                          noFix: tr(zh: '尚未定位', en: 'No GPS fix')),
                      style: coordStyle,
                    ),
                  ),
                  if (acc.isNotEmpty)
                    AnimatedDefaultTextStyle(
                      duration: Motion.of(context, 300),
                      style: subStyle.copyWith(color: accColor),
                      child: RollingText(text: acc, style: subStyle),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                // On-screen only — the burned-in watermark keeps its own
                // fixed English labels (see _watermarkFor).
                '${tr(zh: '海拔', en: 'Alt')} ${formatAltitude(r.altitude, store.altUnit)}   '
                '${tr(zh: '方位', en: 'Bearing')} ${formatHeading(r.heading)}   '
                '${formatTimestamp(r.time)}',
                style: subStyle,
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

  static const double _shutterSize = 78;
  static const double _entrySize = 48;
  static const double _barHeight = 110;

  /// Shutter bar: the iris shutter in the middle (orange ring, green disc,
  /// six blades that shut on capture), the last-photo gallery entry at the
  /// right, and the in-flight thumbnail that connects the two.
  Widget _shutterBar() {
    final ready = _controller?.value.isInitialized ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canFire = ready && !_capturing;
    return Container(
      color: dark ? Colors.black : Theme.of(context).colorScheme.surface,
      height: _barHeight,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final shutterCenter = Offset(w / 2, _barHeight / 2);
          final entryCenter = Offset(w - 20 - _entrySize / 2, _barHeight / 2);
          return Stack(
            children: [
              Positioned(
                left: shutterCenter.dx - _shutterSize / 2,
                top: shutterCenter.dy - _shutterSize / 2,
                child: Semantics(
                  button: true,
                  enabled: canFire,
                  label: tr(zh: '拍照', en: 'Take photo'),
                  child: GestureDetector(
                    onTapDown: canFire
                        ? (_) => setState(() => _pressed = true)
                        : null,
                    onTapUp: (_) => setState(() => _pressed = false),
                    onTapCancel: () => setState(() => _pressed = false),
                    onTap: canFire ? _capture : null,
                    child: AnimatedScale(
                      scale: _pressed ? 0.9 : 1,
                      duration: Motion.of(context, 110),
                      curve: Motion.standard,
                      child: _shutterButton(ready, dark),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: entryCenter.dx - _entrySize / 2,
                top: entryCenter.dy - _entrySize / 2,
                child: _galleryEntry(),
              ),
              if (_flyPhoto != null)
                _FlyingThumb(
                  key: ValueKey(_flyPhoto!.id),
                  file: File(widget.store.photoPath(_flyPhoto!.fileName)),
                  from: shutterCenter,
                  to: entryCenter,
                  size: _entrySize,
                  duration: Motion.of(context, 520),
                  onLanded: _landFlight,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _shutterButton(bool ready, bool dark) {
    final scheme = Theme.of(context).colorScheme;
    final disc = ready ? const Color(0xFF2E7D32) : scheme.surfaceContainerHighest;
    return AnimatedContainer(
      duration: Motion.of(context, 250),
      width: _shutterSize,
      height: _shutterSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: disc,
        border: Border.all(
          color: ready ? Motion.safetyOrange : scheme.outlineVariant,
          width: 3,
        ),
        boxShadow: ready && !dark
            ? [
                BoxShadow(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4))
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _aperture,
              builder: (context, _) => CustomPaint(
                painter: AperturePainter(
                  closure: _aperture.value,
                  blade: ready ? Colors.white : scheme.outline,
                  seam: disc,
                  rotation: _aperture.value * 0.35,
                ),
              ),
            ),
            if (_capturing)
              const Padding(
                padding: EdgeInsets.all(4),
                child: CircularProgressIndicator(
                    color: Motion.safetyOrange, strokeWidth: 2.5),
              ),
          ],
        ),
      ),
    );
  }

  /// Bottom-right gallery entry showing the newest photo; empty ring when the
  /// project has none yet.
  Widget _galleryEntry() {
    final p = _lastPhoto;
    final file = p == null ? null : File(widget.store.photoPath(p.fileName));
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: tr(zh: '打开相册', en: 'Open gallery'),
      child: GestureDetector(
        onTap: widget.onOpenGallery,
        child: AnimatedSwitcher(
          duration: Motion.of(context, 260),
          switchInCurve: Motion.enter,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1).animate(anim),
                child: child),
          ),
          child: Container(
            key: ValueKey(p?.id ?? 'none'),
            width: _entrySize,
            height: _entrySize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant, width: 1.5),
              color: scheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: file != null && file.existsSync()
                ? Image.file(file,
                    fit: BoxFit.cover, cacheWidth: 160, gaplessPlayback: true)
                : Icon(Icons.photo_library_outlined,
                    size: 22, color: scheme.onSurfaceVariant),
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

/// The freshly stamped thumbnail lifting off the shutter and landing on the
/// gallery entry: an eased arc from [from] to [to] with a small scale-down.
class _FlyingThumb extends StatelessWidget {
  const _FlyingThumb({
    super.key,
    required this.file,
    required this.from,
    required this.to,
    required this.size,
    required this.duration,
    required this.onLanded,
  });

  final File file;
  final Offset from;
  final Offset to;
  final double size;
  final Duration duration;
  final VoidCallback onLanded;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Motion.standard,
      onEnd: onLanded,
      builder: (context, t, child) {
        final c = Offset.lerp(from, to, t)!;
        // A gentle lob: rises 28 px at mid-flight.
        final lift = -28 * (1 - (2 * t - 1) * (2 * t - 1));
        final s = 1.5 - 0.5 * t;
        return Positioned(
          left: c.dx - size / 2,
          top: c.dy - size / 2 + lift,
          child: IgnorePointer(
            child: Transform.scale(scale: s, child: child),
          ),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover, cacheWidth: 160)
            : const ColoredBox(color: Colors.black26),
      ),
    );
  }
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
          zh: '请在系统设置里允许 SiteStamp 使用定位。',
          en: 'Allow SiteStamp to use location in Settings.',
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
