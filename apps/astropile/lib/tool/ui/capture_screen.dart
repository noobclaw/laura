import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/output.dart';
import '../engine/picker.dart';
import '../pro.dart';
import '../store.dart';
import 'frames_screen.dart';
import 'widgets.dart';

/// Shoot the burst inside the app instead of switching to the camera app and
/// back.
///
/// The point is not a better camera — the phone's own is better — it is that
/// **every frame in the burst is shot with the same settings**. Focus and
/// exposure are locked before the first shot and stay locked to the last, so
/// the stack does not have to throw away frames the camera decided to
/// re-meter halfway through. What it deliberately does *not* claim: it cannot
/// set a long exposure. Flutter's camera plugin exposes no shutter control on
/// either platform, so each frame is whatever the phone chooses.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.store});
  final AstroStore store;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

/// Burst lengths offered. All four are always shown; the ones above the
/// user's tier limit carry a lock and open the unlock sheet, the same way the
/// stacking modes do. Hiding them instead left a free user looking at a lone
/// "4" with no way to find out the others exist.
const List<int> kBurstCounts = [4, 8, 16, 32];

/// Gap between shots. Long enough that the sensor is not still reading out
/// the previous frame, short enough that a 32-frame burst is under a minute.
const Duration kBurstGap = Duration(milliseconds: 400);

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;

  /// Set when the camera could not be opened: shown on screen with the reason
  /// rather than leaving a black rectangle.
  String? _error;
  bool _permanentlyDenied = false;

  int _count = 8;
  bool _shooting = false;
  bool _stopRequested = false;
  int _shot = 0;

  /// Keep the individual frames in Photos, not only the stack made from them.
  ///
  /// Default on, and deliberately so: anything that opens a camera is
  /// expected to keep what it shot. The burst otherwise lives in a scratch
  /// folder the frames screen deletes on the way out, and a user who stacked
  /// 32 frames and then went back would have lost all 32 originals with no
  /// warning.
  bool _keepOriginals = true;

  /// Guards the async gap inside [_open]: a lifecycle transition that lands
  /// while `initialize()` is in flight must invalidate the controller that
  /// eventually arrives, or the screen comes back to a frozen preview it
  /// thinks is live.
  int _openGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _count = widget.store.frameLimit >= 8 ? 8 : 4;
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  /// Set when the app went to the background mid-burst: the controller
  /// cannot be torn down under an in-flight `takePicture` (that is a native
  /// crash on several Android devices), so the burst loop does it on the way
  /// out instead.
  bool _teardownAfterBurst = false;

  /// The OS hands the camera to whatever comes to the front, and a controller
  /// that was alive across that hand-off comes back dead (a frozen preview on
  /// Android, a black one on iOS). So it is torn down on the way out and
  /// rebuilt on the way back in — never merely paused.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Invalidate any `_open()` currently awaiting `initialize()`: the
      // controller it is about to produce belongs to a session the OS has
      // already taken the camera away from.
      _openGeneration++;
      if (_shooting) {
        _stopRequested = true;
        _teardownAfterBurst = true;
        return;
      }
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && c == null && !_shooting) {
      // No "already opening" guard: an open that was in flight when we went
      // to the background never lands (its generation is stale), so the case
      // where one is outstanding is exactly the case that most needs a fresh
      // open — guarding on it left a permanent spinner.
      _open();
    }
  }

  /// Delete a burst folder nothing took ownership of. Every early exit from
  /// [_shoot] goes through here: only the path that hands the folder to the
  /// frames screen leaves it on disk, and that screen deletes it itself.
  Future<void> _discard(Directory? dir) async {
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('burst cleanup skipped: $e');
    }
  }

  /// Finish the teardown the lifecycle handler had to defer.
  Future<void> _drainTeardown() async {
    if (!_teardownAfterBurst) return;
    _teardownAfterBurst = false;
    final c = _controller;
    _controller = null;
    await c?.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    final generation = ++_openGeneration;
    setState(() {
      _error = null;
      _permanentlyDenied = false;
    });
    try {
      final cameras = await availableCameras();
      if (generation != _openGeneration) return;
      if (cameras.isEmpty) {
        _fail(tr(
          zh: '这台设备上找不到可用的相机。',
          en: 'No usable camera was found on this device.',
        ));
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        // `ultraHigh` (~2160p, 8.3 MP), not `max`: the sensor's own maximum
        // on a 48 MP or 108 MP phone would be refused by the stacker's
        // `kMaxFramePixels` cap of 26 MP, and 8.3 MP is comfortably under it.
        // Not `veryHigh` either — that is 1080p, i.e. a 2 MP stack out of a
        // phone whose camera app shoots 12 MP, which is what shipped in the
        // first cut of this screen.
        ResolutionPreset.ultraHigh,
        // Stills only. The Android manifest strips RECORD_AUDIO to match, so
        // the store page never asks the user for a microphone.
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted || generation != _openGeneration) {
        await controller.dispose();
        return;
      }
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      setState(() {
        _controller = controller;
      });
    } on CameraException catch (e) {
      if (generation != _openGeneration) return;
      _fail(_cameraMessage(e), permanent: _isDenied(e));
    } catch (e) {
      if (generation != _openGeneration) return;
      _fail('${tr(zh: '相机打不开', en: 'The camera could not be opened')}: $e');
    }
  }

  void _fail(String message, {bool permanent = false}) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _permanentlyDenied = permanent;
      _controller = null;
    });
  }

  bool _isDenied(CameraException e) =>
      e.code == 'CameraAccessDenied' ||
      e.code == 'CameraAccessDeniedWithoutPrompt' ||
      e.code == 'CameraAccessRestricted';

  String _cameraMessage(CameraException e) {
    if (_isDenied(e)) {
      return tr(
        zh: '没有相机权限,无法连拍。你可以在系统设置里允许本应用使用相机,或者改用「从相册选择」。',
        en: 'Camera permission was denied, so the burst cannot run. Allow camera access for this app in system settings, or pick photos from the library instead.',
      );
    }
    return '${tr(zh: '相机打不开', en: 'The camera could not be opened')}: ${e.description ?? e.code}';
  }

  /// Lock focus and exposure, then take [_count] shots into a scratch folder.
  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || _shooting) return;
    setState(() {
      _shooting = true;
      _stopRequested = false;
      _shot = 0;
    });
    Directory? dir;
    final files = <String>[];
    try {
      dir = await WorkDirs.fresh('burst');
      // Locking is best-effort: some devices report the mode as unsupported,
      // and a burst with auto-exposure is still worth having.
      for (final lock in [
        () => c.setFocusMode(FocusMode.locked),
        () => c.setExposureMode(ExposureMode.locked),
      ]) {
        try {
          await lock();
        } on CameraException catch (e) {
          debugPrint('capture lock unsupported: ${e.code}');
        }
      }
      for (var i = 0; i < _count; i++) {
        if (_stopRequested || !mounted || _controller == null) break;
        final shot = await c.takePicture();
        final path = '${dir.path}/burst-${(i + 1).toString().padLeft(3, '0')}.jpg';
        await File(shot.path).copy(path);
        try {
          await File(shot.path).delete();
        } catch (_) {}
        files.add(path);
        if (!mounted) break;
        setState(() => _shot = i + 1);
        if (i + 1 < _count) await Future<void>.delayed(kBurstGap);
      }
    } on CameraException catch (e) {
      if (mounted) showNotice(context, _cameraMessage(e));
    } catch (e) {
      if (mounted) {
        showNotice(context,
            '${tr(zh: '连拍中断', en: 'The burst stopped')}: $e');
      }
    } finally {
      // Hand the metering back, so leaving the screen does not leave the
      // camera locked for the next app.
      try {
        await c.setFocusMode(FocusMode.auto);
        await c.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      _shooting = false;
      await _drainTeardown();
      if (mounted) setState(() {});
    }

    // The burst is a keeper unless the user said otherwise: these are the
    // originals, and the folder they live in is deleted the moment the frames
    // screen goes away.
    if (_keepOriginals && files.isNotEmpty) {
      final saved = await saveManyToPhotos(files);
      if (!mounted) return;
      if (saved.error != null) {
        showNotice(
          context,
          saved.error!,
          action: saved.permanentlyDenied
              ? SnackBarAction(
                  label: tr(zh: '去设置', en: 'Settings'),
                  onPressed: openSystemSettings)
              : null,
        );
      }
    }

    if (!mounted) return;
    if (files.length < kMinStackFramesUi) {
      await _discard(dir);
      if (!mounted) return;
      showNotice(
          context,
          tr(
            zh: '只拍到 ${files.length} 张,叠加至少需要 2 张。',
            en: 'Only ${files.length} frame(s) were captured; stacking needs at least two.',
          ));
      return;
    }
    final imported = await FrameImporter.fromPaths(files);
    if (!mounted) return;
    if (imported.frames.length < kMinStackFramesUi) {
      await _discard(dir);
      if (!mounted) return;
      showNotice(
          context,
          tr(
            zh: '拍下的照片读不出来,请改用「从相册选择」。',
            en: 'The captured photos could not be read — pick photos from the library instead.',
          ));
      return;
    }
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => FramesScreen(
        store: widget.store,
        frames: imported.frames,
        scratchDir: dir?.path,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c = _controller;
    final limit = widget.store.frameLimit;
    return PopScope(
      canPop: !_shooting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _shooting) setState(() => _stopRequested = true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr(zh: '连拍', en: 'Burst')),
          automaticallyImplyLeading: !_shooting,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: _preview(c),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr(zh: '拍几张', en: 'How many frames'),
                        style: text.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        // Counts above the tier limit stay on screen with a
                        // lock, rather than vanishing: a free user seeing a
                        // lone "4" chip has no way to learn that 8/16/32
                        // exist, and every other gate in the app explains
                        // itself through showProSheet.
                        for (final n in kBurstCounts)
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('$n'),
                                if (n > limit) ...[
                                  const SizedBox(width: 4),
                                  Icon(Icons.lock_outline,
                                      size: 14, color: cs.onSurfaceVariant),
                                ],
                              ],
                            ),
                            selected: _count == n,
                            showCheckmark: false,
                            onSelected: _shooting
                                ? null
                                : (_) {
                                    if (n > limit) {
                                      showProSheet(context,
                                          reason: tr(
                                            zh: '免费版一次最多叠 $kFreeFrameLimit 张,所以连拍也停在这里。Pro 之后一次可以连拍并叠加 $kProFrameLimit 张 —— 星轨的弧长和降噪的效果都直接跟张数走。',
                                            en: 'The free tier stacks $kFreeFrameLimit frames at a time, so the burst stops there too. With Pro you can shoot and stack $kProFrameLimit — both the length of a star trail and the amount of noise removed follow the frame count directly.',
                                          ));
                                      return;
                                    }
                                    setState(() => _count = n);
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        zh: '把手机架稳(靠着什么都行),按下之后对焦和曝光会锁住,$_count 张全部用同一组参数拍完。不能设置长曝光 —— 快门由系统决定。',
                        en: 'Brace the phone against something. Focus and exposure lock when you start, so all $_count frames are shot on one setting. It cannot set a long exposure — the shutter is the system\'s choice.',
                      ),
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _keepOriginals,
                      onChanged:
                          _shooting ? null : (v) => setState(() => _keepOriginals = v),
                      title: Text(tr(zh: '把原片存进相册', en: 'Keep the frames in Photos')),
                      subtitle: Text(
                        tr(
                          zh: '关掉的话,这组照片只在叠加期间存在,叠完就删。',
                          en: 'With this off the burst exists only for this stack and is deleted afterwards.',
                        ),
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 10),
                    PressScale(
                      enabled: c != null && !_shooting,
                      child: FilledButton(
                        onPressed: c == null || _shooting ? null : _shoot,
                        child: AnimatedSwitcher(
                          duration: animMs(context, 220),
                          child: Text(
                            key: ValueKey(_shooting ? _shot : -1),
                            _shooting
                                ? tr(
                                    zh: '正在拍 $_shot/$_count',
                                    en: 'Shooting $_shot of $_count')
                                : tr(zh: '开始连拍', en: 'Start the burst'),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: animMs(context, 220),
                      child: _shooting
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton(
                                onPressed: _stopRequested
                                    ? null
                                    : () => setState(() => _stopRequested = true),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48)),
                                child: Text(_stopRequested
                                    ? tr(zh: '正在停止…', en: 'Stopping…')
                                    : tr(zh: '停止', en: 'Stop')),
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(CameraController? c) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final error = _error;
    if (error != null) {
      return Container(
        color: cs.surfaceContainerHigh,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined,
                size: 40, color: AstroColors.of(context).bad),
            const SizedBox(height: 14),
            Text(error,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(height: 1.4)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_permanentlyDenied)
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                    onPressed: openSystemSettings,
                    child: Text(tr(zh: '去系统设置', en: 'Open settings')),
                  ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(96, 40)),
                  onPressed: _open,
                  child: Text(tr(zh: '再试一次', en: 'Try again')),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: cs.surfaceContainerHigh,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: c.value.previewSize?.height ?? 1,
            height: c.value.previewSize?.width ?? 1,
            child: CameraPreview(c),
          ),
        ),
        // A shutter flash on every frame: the only feedback that a shot
        // actually landed, since the preview itself does not change. Keyed on
        // the counter, so each shot builds a fresh tween that runs 1 → 0.
        if (_shot > 0)
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_shot),
              tween: Tween(begin: 1, end: 0),
              duration: animMs(context, 260),
              curve: Curves.easeOut,
              builder: (_, v, _) =>
                  Container(color: Colors.white.withValues(alpha: 0.45 * v)),
            ),
          ),
      ],
    );
  }
}
