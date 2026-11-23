import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/review_prompt.dart';
import 'eta.dart';
import 'job_runner.dart';
import 'media.dart';
import 'models.dart';
import 'pixel_art.dart';
import 'pro.dart';
import 'result_screen.dart';
import 'store.dart';
import 'tiling.dart';
import 'upscaler.dart';

/// Configure and run one photo: preview, 2x/4x, denoise, the size/time
/// estimate, then the progress ring with ETA and cancel.
class LiftScreen extends StatefulWidget {
  const LiftScreen({
    super.key,
    required this.photo,
    required this.store,
    required this.runner,
  });

  final PickedPhoto photo;
  final PhotoLiftStore store;
  final LiftJobRunner runner;

  @override
  State<LiftScreen> createState() => _LiftScreenState();
}

enum _Phase { configure, running }

class _LiftScreenState extends State<LiftScreen> with SingleTickerProviderStateMixin {
  int _scale = 2;
  late DenoiseLevel _denoise = widget.store.defaultDenoise;
  _Phase _phase = _Phase.configure;
  UpscaleProgress _progress = const UpscaleProgress(done: 0, total: 1, stage: 'decode');
  DateTime? _startedAt;
  double _estimateSec = 0;
  Timer? _ticker;
  bool _cancelling = false;
  /// Drives the light band around the progress ring (one lap per cycle).
  /// Built in initState, not lazily: a `late final` initialiser would first
  /// run from dispose() when the user leaves the configure page without
  /// starting, and creating a Ticker from a deactivated element asserts.
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    // 2.4 s per lap: slow enough that the per-frame ring repaint does not
    // compete with the CPU-only engine for cores during a multi-minute run.
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  }

  IntSize get _fit => fitInput(widget.photo.width, widget.photo.height, _scale);
  IntSize get _outSize => IntSize(_fit.width * _scale, _fit.height * _scale);
  bool get _willDownscale =>
      _fit.width != widget.photo.width || _fit.height != widget.photo.height;

  @override
  void dispose() {
    _ticker?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  void _setPhase(_Phase phase) {
    _phase = phase;
    if (phase == _Phase.running) {
      if (!MediaQuery.disableAnimationsOf(context)) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  void _pickScale(int s) {
    if (s == 4 && !widget.store.pro) {
      showProSheet(context,
          reason: tr(zh: '4x 放大是 Pro 功能;免费版可用 2x。',
              en: '4x upscaling is a Pro feature; the free tier offers 2x.', zht: '4x 放大是 Pro 功能；免費版可用 2x。', ja: '4x 拡大は Pro の機能です。無料版は 2x まで使えます。', es: 'Ampliar 4x es una función Pro; la versión gratis ofrece 2x.', pt: 'Ampliar 4x é um recurso Pro; a versão grátis oferece 2x.', de: '4x-Vergrößerung ist eine Pro-Funktion; gratis gibt es 2x.', fr: 'L\'agrandissement 4x est une fonction Pro ; la version gratuite offre 2x.'));
      return;
    }
    setState(() => _scale = s);
  }

  Future<void> _start() async {
    // The Start button stays hit-testable while the options card fades out,
    // so a double tap used to launch a second run: it bounced off the native
    // "busy" guard and flipped the screen back to "configure" with the first
    // job still running underneath.
    if (_phase == _Phase.running) return;
    final store = widget.store;
    if (!store.canStart(scale: _scale)) {
      showProSheet(context,
          reason: tr(
              zh: '今天的 ${PhotoLiftStore.freeDailyLimit} 张免费额度已用完。明天再来,或升级 Pro 不限张数。',
              en: 'Today\'s ${PhotoLiftStore.freeDailyLimit} free photos are used up. Come back tomorrow, or go Pro for unlimited.', zht: '今天的 ${PhotoLiftStore.freeDailyLimit} 張免費額度已用完。明天再來，或升級 Pro 不限張數。', ja: '今日の無料枠（${PhotoLiftStore.freeDailyLimit} 枚）を使い切りました。明日またどうぞ。Pro なら枚数無制限です。', es: 'Ya usaste las ${PhotoLiftStore.freeDailyLimit} fotos gratis de hoy. Vuelve mañana o hazte Pro para no tener límite.', pt: 'As ${PhotoLiftStore.freeDailyLimit} fotos grátis de hoje acabaram. Volte amanhã ou seja Pro para não ter limite.', de: 'Die ${PhotoLiftStore.freeDailyLimit} Gratis-Fotos für heute sind aufgebraucht. Komm morgen wieder oder hol dir Pro für unbegrenzt viele.', fr: 'Les ${PhotoLiftStore.freeDailyLimit} photos gratuites du jour sont épuisées. Revenez demain ou passez à Pro pour l\'illimité.'));
      return;
    }
    setState(() {
      _setPhase(_Phase.running);
      _startedAt = DateTime.now();
      _estimateSec = store.estimateSeconds(_outSize.pixels, _scale);
      _progress = const UpscaleProgress(done: 0, total: 1, stage: 'decode');
      _cancelling = false;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final rec = await widget.runner.run(
        photo: widget.photo,
        scale: _scale,
        denoise: _denoise,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // Core action for the store-rating prompt (PLAN.md G8b-7): one photo
      // lifted successfully. Cancels and failures land in the handlers below.
      unawaited(ReviewPrompt.noteCoreAction());
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(record: rec, store: store, fresh: true),
      ));
    } on UpscaleCancelled {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _setPhase(_Phase.configure));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(zh: '已取消', en: 'Cancelled', zht: '已取消', ja: 'キャンセルしました', es: 'Cancelado', pt: 'Cancelado', de: 'Abgebrochen', fr: 'Annulé'))));
    } catch (e) {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _setPhase(_Phase.configure));
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(zh: '处理失败', en: 'Processing failed', zht: '處理失敗', ja: '処理に失敗しました', es: 'Falló el procesamiento', pt: 'Falha no processamento', de: 'Verarbeitung fehlgeschlagen', fr: 'Échec du traitement')),
          content: Text(describeUpscaleError(e)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(zh: '好', en: 'OK', zht: '好', ja: 'OK', es: 'OK', pt: 'OK', de: 'OK', fr: 'OK'))),
          ],
        ),
      );
    } finally {
      _ticker?.cancel();
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    await widget.runner.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final running = _phase == _Phase.running;
    return PopScope(
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && running) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(running
              ? tr(zh: '正在修复…', en: 'Restoring…', zht: '正在修復…', ja: '復元中…', es: 'Restaurando…', pt: 'Restaurando…', de: 'Wird restauriert …', fr: 'Restauration…')
              : tr(zh: '修复设置', en: 'Restore', zht: '修復設定', ja: '復元の設定', es: 'Restaurar', pt: 'Restaurar', de: 'Restaurieren', fr: 'Restaurer')),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              _Preview(photo: widget.photo),
              const SizedBox(height: 16),
              // configure <-> running: cross-fade with a small vertical slide,
              // not a hard swap.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(running),
                  child: running ? _buildProgress(context) : _buildOptions(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = widget.store;
    final eta = store.estimateSeconds(_outSize.pixels, _scale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(zh: '放大倍数', en: 'Upscale', zht: '放大倍數', ja: '拡大倍率', es: 'Ampliación', pt: 'Ampliação', de: 'Vergrößerung', fr: 'Agrandissement'), style: text.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: [
                    const ButtonSegment(value: 2, label: Text('2x')),
                    ButtonSegment(
                      value: 4,
                      label: const Text('4x'),
                      icon: store.pro ? null : const Icon(Icons.lock_outline, size: 16),
                    ),
                  ],
                  selected: {_scale},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _pickScale(s.first),
                ),
                const SizedBox(height: 18),
                Text(tr(zh: '降噪', en: 'Denoise', zht: '降噪', ja: 'ノイズ除去', es: 'Reducir ruido', pt: 'Reduzir ruído', de: 'Entrauschen', fr: 'Débruitage'), style: text.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<DenoiseLevel>(
                  segments: [
                    for (final d in DenoiseLevel.values)
                      ButtonSegment(value: d, label: Text(d.label)),
                  ],
                  selected: {_denoise},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _denoise = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    zh: '翻拍、扫描件、老手机照片多带噪点,建议「轻度」;非常脏的照片再用「强」。',
                    en: 'Scans, re-photographed prints and old phone shots are usually noisy — start with Light; use Strong only for very dirty photos.', zht: '翻拍、掃描檔、舊手機照片多帶雜訊，建議「輕度」；非常髒的照片再用「強」。', ja: 'スキャン画像・撮り直したプリント・昔のケータイ写真はノイズが多めです。まずは「弱」、汚れがひどい写真だけ「強」を使ってください。', es: 'Los escaneos, las fotos impresas fotografiadas y las de móviles antiguos suelen tener ruido: empieza con Suave y usa Fuerte solo en fotos muy sucias.', pt: 'Scans, fotos impressas refotografadas e fotos de celulares antigos costumam ter ruído — comece com Leve e use Forte só em fotos muito sujas.', de: 'Scans, abfotografierte Abzüge und alte Handyfotos rauschen meist – beginne mit Leicht und nimm Stark nur bei sehr verschmutzten Fotos.', fr: 'Les scans, tirages rephotographiés et photos d\'anciens téléphones sont souvent bruités — commencez par Léger et réservez Fort aux photos très sales.'),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.photo_size_select_large,
                  label: tr(zh: '输出尺寸', en: 'Output size', zht: '輸出尺寸', ja: '出力サイズ', es: 'Tamaño de salida', pt: 'Tamanho de saída', de: 'Ausgabegröße', fr: 'Taille de sortie'),
                  value: '${_outSize.width} × ${_outSize.height}',
                ),
                if (_willDownscale) ...[
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      zh: '原图较大,会先缩到 ${_fit.width} × ${_fit.height} 再放大,以免占满内存。',
                      en: 'The source is large; it is first reduced to ${_fit.width} × ${_fit.height} so the result fits in memory.', zht: '原圖較大，會先縮到 ${_fit.width} × ${_fit.height} 再放大，以免佔滿記憶體。', ja: '元画像が大きいため、メモリに収まるよう先に ${_fit.width} × ${_fit.height} に縮小します。', es: 'La imagen original es grande; primero se reduce a ${_fit.width} × ${_fit.height} para que el resultado quepa en memoria.', pt: 'A imagem original é grande; ela é reduzida primeiro para ${_fit.width} × ${_fit.height} para o resultado caber na memória.', de: 'Das Original ist groß; es wird zuerst auf ${_fit.width} × ${_fit.height} verkleinert, damit das Ergebnis in den Speicher passt.', fr: 'L\'original est grand ; il est d\'abord réduit à ${_fit.width} × ${_fit.height} pour que le résultat tienne en mémoire.'),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const Divider(height: 20),
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: tr(zh: '预计用时', en: 'Estimated time', zht: '預計用時', ja: '予想時間', es: 'Tiempo estimado', pt: 'Tempo estimado', de: 'Geschätzte Dauer', fr: 'Durée estimée'),
                  value: formatEta(eta),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        PressScale(
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.auto_awesome),
            label: Text(tr(zh: '开始修复', en: 'Restore', zht: '開始修復', ja: '復元する', es: 'Restaurar', pt: 'Restaurar', de: 'Restaurieren', fr: 'Restaurer')),
          ),
        ),
        if (!store.pro) ...[
          const SizedBox(height: 10),
          Text(
            tr(
              zh: '免费版结果角落带一个小小的 PixelLift 标签;Pro 去掉。',
              en: 'Free results carry a small PixelLift tag in the corner; Pro removes it.', zht: '免費版結果角落帶一個小小的 PixelLift 標籤；Pro 會去掉。', ja: '無料版の結果には隅に小さな PixelLift ロゴが入ります。Pro では入りません。', es: 'Los resultados gratis llevan una pequeña marca PixelLift en la esquina; Pro la quita.', pt: 'Os resultados grátis têm uma pequena marca PixelLift no canto; o Pro remove.', de: 'Gratis-Ergebnisse tragen ein kleines PixelLift-Zeichen in der Ecke; Pro entfernt es.', fr: 'Les résultats gratuits portent une petite marque PixelLift dans le coin ; Pro la retire.'),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final elapsed = _startedAt == null
        ? 0.0
        : DateTime.now().difference(_startedAt!).inMilliseconds / 1000.0;
    // Tile progress once inference starts; before that, time-based.
    final infer = _progress.stage != 'decode';
    final frac = infer
        ? (0.05 + 0.9 * _progress.fraction).clamp(0.0, 0.98)
        : (elapsed / math.max(_estimateSec, 1) * 0.05).clamp(0.0, 0.05);
    final remaining = infer && _progress.done > 0
        ? math.max(0.0, elapsed / _progress.fraction - elapsed)
        : math.max(0.0, _estimateSec - elapsed);
    final stageLabel = switch (_progress.stage) {
      'decode' => tr(zh: '读取照片…', en: 'Reading photo…', zht: '讀取照片…', ja: '写真を読み込み中…', es: 'Leyendo la foto…', pt: 'Lendo a foto…', de: 'Foto wird gelesen …', fr: 'Lecture de la photo…'),
      'encode' => tr(zh: '正在保存结果…', en: 'Saving the result…', zht: '正在儲存結果…', ja: '結果を保存中…', es: 'Guardando el resultado…', pt: 'Salvando o resultado…', de: 'Ergebnis wird gesichert …', fr: 'Enregistrement du résultat…'),
      _ => tr(zh: 'AI 放大中 ${_progress.done}/${_progress.total} 块',
          en: 'AI upscaling, tile ${_progress.done}/${_progress.total}', zht: 'AI 放大中 ${_progress.done}/${_progress.total} 塊', ja: 'AI拡大中 ${_progress.done}/${_progress.total} ブロック', es: 'Ampliando con IA, bloque ${_progress.done}/${_progress.total}', pt: 'Ampliando com IA, bloco ${_progress.done}/${_progress.total}', de: 'KI vergrößert, Kachel ${_progress.done}/${_progress.total}', fr: 'Agrandissement IA, bloc ${_progress.done}/${_progress.total}'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        child: Column(
          children: [
            // The ring: the fraction is tweened so tile-by-tile jumps glide,
            // a light band sweeps the filled arc, and the same pixel mosaic
            // as the home hero resolves inside it in step with progress.
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: frac),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => SizedBox(
                width: 172,
                height: 172,
                // Outer boundary: the sweeping band repaints every frame for
                // minutes; without it the whole Card (mosaic, texts, button)
                // would be redrawn at 60 fps alongside it.
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _sweep,
                    // Everything inside the ring only changes with [v] (the
                    // eased fraction) — passed as `child` so the band's
                    // ticks neither rebuild nor (inner boundary) repaint it.
                    child: RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipOval(
                              child: PixelResolve(
                                  progress: v, grid: 8, gap: 2, radius: 2.5, opacity: 0.85),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    cs.surfaceContainerHigh,
                                    cs.surfaceContainerHigh.withValues(alpha: 0.92),
                                    cs.surfaceContainerHigh.withValues(alpha: 0),
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                              ),
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${(v * 100).round()}%', style: text.displaySmall),
                                  Text(
                                    _progress.stage == 'encode'
                                        ? tr(zh: '快好了', en: 'almost done', zht: '快好了', ja: 'まもなく完了', es: 'ya casi', pt: 'quase pronto', de: 'fast fertig', fr: 'presque fini')
                                        : tr(zh: '剩余 ${formatEta(remaining)}',
                                            en: '${formatEta(remaining)} left', zht: '剩餘 ${formatEta(remaining)}', ja: '残り ${formatEta(remaining)}', es: 'quedan ${formatEta(remaining)}', pt: 'faltam ${formatEta(remaining)}', de: 'noch ${formatEta(remaining)}', fr: 'encore ${formatEta(remaining)}'),
                                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    builder: (context, child) => CustomPaint(
                      painter: LiftRingPainter(
                        fraction: v,
                        sweep: _sweep.isAnimating ? _sweep.value : -1,
                        track: cs.surfaceContainerHighest,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(stageLabel, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              tr(zh: '${_scale}x · ${_outSize.width} × ${_outSize.height} · 模型在本机运行',
                  en: '${_scale}x · ${_outSize.width} × ${_outSize.height} · running on this device', zht: '${_scale}x · ${_outSize.width} × ${_outSize.height} · 模型在本機執行', ja: '${_scale}x · ${_outSize.width} × ${_outSize.height} · 端末上で処理中', es: '${_scale}x · ${_outSize.width} × ${_outSize.height} · se ejecuta en este dispositivo', pt: '${_scale}x · ${_outSize.width} × ${_outSize.height} · rodando neste aparelho', de: '${_scale}x · ${_outSize.width} × ${_outSize.height} · läuft auf diesem Gerät', fr: '${_scale}x · ${_outSize.width} × ${_outSize.height} · sur cet appareil'),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              tr(zh: '处理期间请保持 PixelLift 在前台,屏幕不会自动熄灭',
                  en: 'Keep PixelLift open — the screen stays awake while it works', zht: '處理期間請保持 PixelLift 在前景，螢幕不會自動關閉', ja: '処理中は PixelLift を開いたままにしてください（画面は自動で消えません）', es: 'Mantén PixelLift abierta: la pantalla no se apaga mientras trabaja', pt: 'Mantenha o PixelLift aberto — a tela fica ligada enquanto ele trabalha', de: 'Lass PixelLift geöffnet – der Bildschirm bleibt währenddessen an', fr: 'Gardez PixelLift ouvert — l\'écran reste allumé pendant le traitement'),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancel,
              icon: const Icon(Icons.close),
              label: Text(_cancelling
                  ? tr(zh: '正在停止…', en: 'Stopping…', zht: '正在停止…', ja: '停止中…', es: 'Deteniendo…', pt: 'Parando…', de: 'Wird gestoppt …', fr: 'Arrêt…')
                  : tr(zh: '取消', en: 'Cancel', zht: '取消', ja: 'キャンセル', es: 'Cancelar', pt: 'Cancelar', de: 'Abbrechen', fr: 'Annuler')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.photo});
  final PickedPhoto photo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aspect = photo.width > 0 && photo.height > 0 ? photo.width / photo.height : 4 / 3;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspect.clamp(0.5, 2.0),
                  child: Image.file(File(photo.path),
                      fit: BoxFit.contain, cacheWidth: (screenW * dpr).round()),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${photo.width} × ${photo.height}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: text.bodyMedium)),
        Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
