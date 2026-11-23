import 'dart:io';

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'job_runner.dart';
import 'lift_screen.dart';
import 'media.dart';
import 'models.dart';
import 'pixel_art.dart';
import 'pro.dart';
import 'result_screen.dart';
import 'store.dart';

/// Home: the hero "pick a photo" card, today's free allowance, and the grid
/// of photos already restored.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.runner});

  final PhotoLiftStore store;
  final LiftJobRunner runner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _picking = false;

  /// Mirror of `store.history` that the AnimatedGrid animates towards —
  /// the grid must be told about each insert / remove, not handed a new list.
  final List<LiftRecord> _shown = [];
  final GlobalKey<SliverAnimatedGridState> _gridKey = GlobalKey<SliverAnimatedGridState>();

  /// One thumbnail provider per record, plus a listener that keeps its
  /// decoded image alive while the tile is shown. The result screen's
  /// full-size before/after images push the small thumbnail out of the LRU
  /// image cache, and deleteRecord removes the file — so a fresh Image.file
  /// in the exit builder would reload from a deleted file and flash
  /// broken_image. The exit tile reuses this provider (still resolved) instead.
  final Map<String, _Thumb> _thumbs = {};

  @override
  void initState() {
    super.initState();
    _shown.addAll(widget.store.history);
    widget.store.addListener(_syncHistory);
  }

  @override
  void dispose() {
    widget.store.removeListener(_syncHistory);
    for (final t in _thumbs.values) {
      t.release();
    }
    _thumbs.clear();
    super.dispose();
  }

  ImageProvider _providerFor(LiftRecord r, BuildContext context) => ResizeImage(
      FileImage(File(widget.store.outputPath(r))),
      width: (140 * MediaQuery.devicePixelRatioOf(context)).round());

  /// Provider for a shown tile; pins its decoded image until the record goes.
  ImageProvider _thumbFor(LiftRecord r, BuildContext context) =>
      _thumbs.putIfAbsent(r.id, () => _Thumb(_providerFor(r, context))).provider;

  Duration get _gridDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 380);

  void _syncHistory() {
    if (!mounted) return;
    final next = widget.store.history;
    final grid = _gridKey.currentState;
    final changed = next.length != _shown.length ||
        Iterable<int>.generate(next.length).any((i) => next[i].id != _shown[i].id);
    if (!changed) return;
    if (grid == null) {
      // Grid not mounted yet (store still loading): just mirror.
      _shown
        ..clear()
        ..addAll(next);
      return;
    }
    final nextIds = {for (final r in next) r.id};
    for (var i = _shown.length - 1; i >= 0; i--) {
      final r = _shown[i];
      if (nextIds.contains(r.id)) continue;
      _shown.removeAt(i);
      final thumb = _thumbs.remove(r.id);
      grid.removeItem(
        i,
        (context, anim) => _HistoryTile(
          record: r,
          store: widget.store,
          animation: anim,
          // A tile never built (far off-screen) has nothing pinned; do not
          // start pinning for a record that is already gone.
          image: thumb?.provider ?? _providerFor(r, context),
          exiting: true,
        ),
        duration: _gridDuration,
      );
      // Keep the decoded thumbnail until the exit animation is over.
      Future<void>.delayed(
          _gridDuration + const Duration(milliseconds: 50), () => thumb?.release());
    }
    final shownIds = {for (final r in _shown) r.id};
    for (var i = 0; i < next.length; i++) {
      final r = next[i];
      if (shownIds.contains(r.id)) continue;
      _shown.insert(i, r);
      grid.insertItem(i, duration: _gridDuration);
    }
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final photo = await MediaBridge.pick();
      if (photo == null || !mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LiftScreen(photo: photo, store: widget.store, runner: widget.runner),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeUpscaleError(e))));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final text = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverList.list(
                children: [
                  _HeroCard(onPick: _pick, busy: _picking),
                  const SizedBox(height: 14),
                  _QuotaCard(store: store),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Text(tr(zh: '最近修复', en: 'Recent', zht: '最近修復', ja: '最近の復元', es: 'Recientes', pt: 'Recentes', de: 'Zuletzt', fr: 'Récents'), style: text.titleLarge),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _shown.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                                key: ValueKey(_shown.length),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('${_shown.length}',
                                    style: text.labelLarge?.copyWith(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: FontWeight.w700)),
                              ),
                      ),
                    ],
                  ),
                  // The empty state lives above the (then 0-item) grid so the
                  // grid stays mounted and the very first result animates in.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _shown.isEmpty
                        ? const _EmptyHistory(key: ValueKey('empty'))
                        : const SizedBox.shrink(key: ValueKey('grid')),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              sliver: SliverAnimatedGrid(
                key: _gridKey,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                initialItemCount: _shown.length,
                itemBuilder: (context, i, anim) => _HistoryTile(
                  record: _shown[i],
                  store: store,
                  animation: anim,
                  image: _thumbFor(_shown[i], context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The hero: rose→wine gradient, the tagline, and the signature
/// "pixels resolving" mosaic looping on the right. The CTA is a white pill
/// with press-scale feedback and an animated busy state.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onPick, required this.busy});
  final VoidCallback onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: heroGradient(cs),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFB8204F).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 12)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(zh: '让老照片\n重新清晰', en: 'Bring old\nphotos back', zht: '讓老照片\n重新清晰', ja: '古い写真を\nもう一度鮮明に', es: 'Devuelve la vida\na tus fotos', pt: 'Traga suas fotos\nantigas de volta', de: 'Alte Fotos\nwieder scharf', fr: 'Redonnez vie\nà vos photos'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr(zh: 'AI 放大 · 降噪 · 全程离线', en: 'AI upscale · denoise · fully offline', zht: 'AI 放大 · 降噪 · 全程離線', ja: 'AI拡大 · ノイズ除去 · 完全オフライン', es: 'IA: ampliar · reducir ruido · sin conexión', pt: 'IA: ampliar · reduzir ruído · offline', de: 'KI-Vergrößern · Entrauschen · offline', fr: 'IA : agrandir · débruiter · hors ligne'),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const SizedBox(
                width: 108,
                height: 108,
                // Own layer: the mosaic repaints every frame; the gradient
                // card, texts and button around it must not.
                child: ExcludeSemantics(
                    child: RepaintBoundary(child: PixelResolve(gap: 2.5, radius: 3.5))),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(tr(zh: '2x / 4x 放大', en: '2x / 4x upscale', zht: '2x / 4x 放大', ja: '2x / 4x 拡大', es: 'Ampliar 2x / 4x', pt: 'Ampliar 2x / 4x', de: '2x / 4x vergrößern', fr: 'Agrandir 2x / 4x')),
              _Pill(tr(zh: '照片不离开手机', en: 'Photos stay on device', zht: '照片不離開手機', ja: '写真は端末から出ません', es: 'Las fotos no salen del móvil', pt: 'As fotos ficam no celular', de: 'Fotos bleiben auf dem Gerät', fr: 'Les photos restent sur l\'appareil')),
              _Pill(tr(zh: '无订阅', en: 'No subscription', zht: '無訂閱', ja: 'サブスクなし', es: 'Sin suscripción', pt: 'Sem assinatura', de: 'Kein Abo', fr: 'Sans abonnement')),
            ],
          ),
          const SizedBox(height: 20),
          PressScale(
            enabled: !busy,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB8204F),
                  minimumSize: const Size(0, 54),
                ),
                onPressed: busy ? null : onPick,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                      child: busy
                          ? const SizedBox(
                              key: ValueKey('busy'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2))
                          : const Icon(Icons.add_photo_alternate_outlined,
                              key: ValueKey('idle'), size: 22),
                    ),
                    const SizedBox(width: 10),
                    // Flexible + scale-down: at large accessibility text
                    // sizes the label must shrink a little, not overflow
                    // the pill.
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: FittedBox(
                          key: ValueKey(busy),
                          fit: BoxFit.scaleDown,
                          child: Text(
                            busy
                                ? tr(zh: '正在打开相册…', en: 'Opening Photos…', zht: '正在開啟相簿…', ja: '写真を開いています…', es: 'Abriendo Fotos…', pt: 'Abrindo Fotos…', de: 'Fotos wird geöffnet …', fr: 'Ouverture de Photos…')
                                : tr(zh: '选择照片', en: 'Choose a photo', zht: '選擇照片', ja: '写真を選ぶ', es: 'Elegir una foto', pt: 'Escolher uma foto', de: 'Foto auswählen', fr: 'Choisir une photo'),
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.store});
  final PhotoLiftStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (store.pro) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium, color: kLiftGold),
          title: Text(tr(zh: 'Pro 已解锁', en: 'Pro unlocked', zht: 'Pro 已解鎖', ja: 'Pro 解除済み', es: 'Pro desbloqueado', pt: 'Pro desbloqueado', de: 'Pro freigeschaltet', fr: 'Pro débloqué'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(tr(zh: '不限张数 · 2x / 4x · 无标签', en: 'Unlimited · 2x / 4x · no tag', zht: '不限張數 · 2x / 4x · 無標籤', ja: '枚数無制限 · 2x / 4x · ロゴなし', es: 'Ilimitado · 2x / 4x · sin marca', pt: 'Ilimitado · 2x / 4x · sem marca', de: 'Unbegrenzt · 2x / 4x · ohne Zeichen', fr: 'Illimité · 2x / 4x · sans marque')),
        ),
      );
    }
    final remaining = store.remainingToday();
    final used = PhotoLiftStore.freeDailyLimit - remaining;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    remaining > 0
                        ? tr(zh: '今天还可免费修复 $remaining 张', en: '$remaining free photos left today', zht: '今天還可免費修復 $remaining 張', ja: '今日はあと $remaining 枚無料で復元できます', es: 'Te quedan $remaining fotos gratis hoy', pt: 'Restam $remaining fotos grátis hoje', de: 'Heute noch $remaining Fotos gratis', fr: 'Encore $remaining photos gratuites aujourd\'hui')
                        : tr(zh: '今天的免费额度已用完', en: 'Today\'s free photos are used up', zht: '今天的免費額度已用完', ja: '今日の無料枠は使い切りました', es: 'Ya usaste las fotos gratis de hoy', pt: 'As fotos grátis de hoje acabaram', de: 'Die Gratis-Fotos für heute sind aufgebraucht', fr: 'Les photos gratuites du jour sont épuisées'),
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < PhotoLiftStore.freeDailyLimit; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          width: 26,
                          height: 6,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: i < used ? cs.outlineVariant : cs.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const SizedBox(width: 6),
                      // Flexible: on a 360 px screen with large text the
                      // English label does not fit beside the bars; wrap
                      // rather than overflow.
                      Flexible(
                        child: Text(tr(zh: '免费版 2x · 带角标', en: 'Free: 2x · corner tag', zht: '免費版 2x · 帶角標', ja: '無料版：2x · ロゴ入り', es: 'Gratis: 2x · con marca', pt: 'Grátis: 2x · com marca', de: 'Gratis: 2x · mit Zeichen', fr: 'Gratuit : 2x · avec marque'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showProSheet(context),
              child: Text(tr(zh: '升级 Pro', en: 'Go Pro', zht: '升級 Pro', ja: 'Pro にアップグレード', es: 'Hazte Pro', pt: 'Seja Pro', de: 'Pro holen', fr: 'Passer à Pro')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // A tiny static mosaic, half-resolved: "this is what we do".
          SizedBox(
            width: 64,
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: kLiftWine.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: PixelResolve(progress: 0.55, grid: 6, gap: 1.5, radius: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(tr(zh: '还没有修复过的照片', en: 'Nothing restored yet', zht: '還沒有修復過的照片', ja: 'まだ復元した写真はありません', es: 'Aún no has restaurado nada', pt: 'Nada restaurado ainda', de: 'Noch nichts restauriert', fr: 'Rien de restauré pour l\'instant'),
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            tr(
              zh: '找一张模糊的翻拍或扫描老照片试试,\n通常一两分钟内就能看到前后对比。',
              en: 'Try a blurry scan or re-photographed print —\nyou\'ll usually see a before/after within a couple of minutes.', zht: '找一張模糊的翻拍或掃描老照片試試，\n通常一兩分鐘內就能看到前後對比。', ja: 'ぼやけたスキャン画像やプリントを撮った写真で試してみましょう。\nたいてい数分でビフォー・アフターが見られます。', es: 'Prueba con un escaneo borroso o una foto impresa fotografiada:\nnormalmente verás el antes/después en un par de minutos.', pt: 'Experimente um scan borrado ou uma foto impressa fotografada —\nnormalmente você vê o antes/depois em poucos minutos.', de: 'Probier einen unscharfen Scan oder einen abfotografierten Abzug –\nmeist siehst du Vorher/Nachher nach ein, zwei Minuten.', fr: 'Essayez un scan flou ou un tirage rephotographié —\nvous verrez l\'avant/après en général en quelques minutes.'),
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
          ),
        ],
      ),
    );
  }
}

/// A history thumbnail provider whose decoded image is pinned in the image
/// cache (a listener counts as a live reference) until [release].
class _Thumb {
  _Thumb(this.provider) {
    _stream = provider.resolve(ImageConfiguration.empty)..addListener(_listener);
  }

  final ImageProvider provider;
  late final ImageStream _stream;
  final ImageStreamListener _listener =
      ImageStreamListener((_, _) {}, onError: (_, _) {});

  void release() => _stream.removeListener(_listener);
}

/// One history cell. [animation] is the AnimatedGrid enter/exit progress: a
/// new result scales up from 0.6 and fades in; a deleted one shrinks away.
/// [exiting] tiles belong to a deleted record: should the image be gone
/// anyway they show a plain placeholder, never the broken-image icon.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.store,
    required this.animation,
    required this.image,
    this.exiting = false,
  });

  final LiftRecord record;
  final PhotoLiftStore store;
  final Animation<double> animation;
  final ImageProvider image;
  final bool exiting;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        // drive(): no CurvedAnimation to dispose on every build.
        scale: animation
            .drive(CurveTween(curve: Curves.easeOutBack))
            .drive(Tween<double>(begin: 0.6, end: 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ResultScreen(record: record, store: store, fresh: false),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: cs.surfaceContainerHighest),
                Image(
                  image: image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => exiting
                      ? const SizedBox.shrink()
                      : Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: kLiftGold,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${record.scale}x${record.engine == EngineKind.dartFallback ? ' ·' : ''}',
                      style: const TextStyle(
                          color: kLiftWine, fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
