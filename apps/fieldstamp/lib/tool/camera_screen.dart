import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'geo_format.dart';
import 'models.dart';
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
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) setState(() => _cameraError = 'No camera found on this device');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      if (mounted) setState(() => _cameraError = null);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Camera unavailable: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
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
      final stamped = await burnWatermark(bytes, _watermarkFor(reading));
      final photo = await widget.store
          .saveCapture(stamped, reading, widget.store.currentProjectId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(photo == null
            ? 'Could not save photo'
            : reading.hasFix
                ? 'Saved with GPS stamp'
                : 'Saved — no GPS fix yet'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

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
              FilledButton.tonal(
                onPressed: _initCamera,
                child: const Text('Retry'),
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
                      formatLatLon(r.latitude, r.longitude, store.coordFormat),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                  if (acc.isNotEmpty)
                    Text(acc,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Alt ${formatAltitude(r.altitude, store.altUnit)}   '
                'Bearing ${formatHeading(r.heading)}   '
                '${formatTimestamp(r.time)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              if (widget.sensors.locationError != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.sensors.locationError!,
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontSize: 11),
                ),
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
              const ListTile(
                title: Text('Project / work order',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                    ? 'New project'
                    : 'New project (Pro)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!store.pro) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Multiple projects are a Pro feature. Unlock in Settings.'),
                    ));
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
      title: const Text('New project'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'e.g. 12 Elm St inspection',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Create')),
      ],
    ),
  );
}
