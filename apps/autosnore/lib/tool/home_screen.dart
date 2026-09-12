import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'recording_screen.dart';
import 'report_screen.dart';
import 'pro.dart';
import 'store.dart';
import 'ui_common.dart';
import 'wave_painter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store});

  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (store.recoveredOnLaunch) {
          // A night that was being recorded when the app died has just been
          // promoted from its last checkpoint. Say so once.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            store.acknowledgeRecovery();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              duration: const Duration(seconds: 6),
              content: Text(tr(
                zh: '上次记录没有正常结束,已按最后一次保存的进度找回,标为「提前结束」。',
                en: 'The last night did not end normally; it was restored from its last checkpoint and marked "ended early".',
              )),
            ));
          });
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StartCard(store: store),
            const SizedBox(height: 20),
            if (store.sessions.isNotEmpty) ...[
              Text(tr(zh: '记录', en: 'Nights'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _NightList(sessions: store.visibleSessions, store: store),
              if (store.atFreeLimit)
                // The history gate itself: tappable, opens the Pro sheet
                // (a plain caption here was the one free-tier wall that
                // dead-ended without a way to unlock).
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(store.hiddenSessionCount > 0
                        ? tr(
                            zh: '还有 ${store.hiddenSessionCount} 晚在 Pro 里',
                            en: '${store.hiddenSessionCount} more night(s) in Pro',
                          )
                        : tr(zh: '保存全部历史', en: 'Keep every night')),
                    subtitle: Text(tr(
                      zh: '免费版显示最近 ${AutoSnoreStore.freeSessionLimit} 晚,解锁 Pro 查看全部历史。',
                      en: 'Free shows the last ${AutoSnoreStore.freeSessionLimit} nights — '
                          'unlock Pro for full history.',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showProSheet(
                      context,
                      reason: tr(
                        zh: '免费版只显示最近 ${AutoSnoreStore.freeSessionLimit} 晚,更早的记录都还在,Pro 可以全部查看。',
                        en: 'The free tier shows the last ${AutoSnoreStore.freeSessionLimit} nights; older ones are kept and Pro shows them all.',
                      ),
                    ),
                  ),
                ),
            ] else ...[
              const SizedBox(height: 24),
              EmptyState(
                icon: Icons.bedtime_outlined,
                title: tr(zh: '今晚开始第一次记录', en: 'Record your first night'),
                body: tr(
                  zh: '把手机放在床头、接通电源,点上方开始。早晨你会看到一份鼾声报告 🌙',
                  en: 'Put the phone by your bed, keep it charging, and tap above. '
                      'A snore report will be waiting in the morning 🌙',
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The hero: a breathing loudness waveform with the mic at its heart.
///
/// Signature motion — one 4-second cycle drives everything: the wave swells
/// and settles, the ripples drift, and two rings leave the mic button and
/// fade at the same tempo. Pressing scales the whole card down a hair.
class _StartCard extends StatefulWidget {
  const _StartCard({required this.store});
  final AutoSnoreStore store;

  @override
  State<_StartCard> createState() => _StartCardState();
}

class _StartCardState extends State<_StartCard>
    with SingleTickerProviderStateMixin {
  static const Duration _cycle = Duration(seconds: 4);

  late final AnimationController _breath =
      AnimationController(vsync: this, duration: _cycle);
  bool _pressed = false;
  bool _motionOn = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = !reduceMotion(context);
    if (on != _motionOn || (on && !_breath.isAnimating)) {
      _motionOn = on;
      if (on) {
        _breath.repeat();
      } else {
        _breath
          ..stop()
          ..value = 0.25; // hold at a gentle half-inhale
      }
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  /// First night only: the three things that decide whether the recording
  /// survives until morning, said before the user commits — not discovered
  /// at 06:00 from a report that stopped at 00:47.
  Future<void> _startNight(BuildContext context) async {
    final store = widget.store;
    if (!store.briefingSeen) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _Briefing(),
      );
      if (go != true || !context.mounted) return;
      store.markBriefingSeen();
    }
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecordingScreen(store: store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final SleepSession? last =
        widget.store.sessions.isEmpty ? null : widget.store.sessions.first;
    // The sub-line is the card's "state": first night vs. a history. It
    // cross-fades rather than snapping when the first report lands.
    final String subline = last == null
        ? tr(zh: '整夜离线记录鼾声 · 零联网', en: 'Record all night · fully offline')
        : tr(
            zh: '上次 ${formatShortDate(last.startMs)} · 评分 ${last.score} · ${bandLabel(last.band)}',
            en: 'Last ${formatShortDate(last.startMs)} · score ${last.score} · ${bandLabel(last.band)}',
          );

    return Semantics(
      button: true,
      label: tr(zh: '开始记录', en: 'Start recording'),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () => _startNight(context),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 248,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    NightPalette.nightHighest,
                    NightPalette.nightLow,
                  ],
                ),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.18),
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The breathing wave, isolated in its own layer so the
                  // 60 fps repaint never touches the text above it.
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (context, _) => CustomPaint(
                        painter: BreathingWavePainter(
                          breath: _breath.value,
                          drift: _breath.value * 2 * math.pi,
                          color: NightPalette.plumLight,
                          glowColor: NightPalette.plum,
                          centerY: 0.36,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _MicCore(breath: _breath),
                      const SizedBox(height: 2),
                      Text(
                        tr(zh: '开始记录', en: 'Start recording'),
                        style: text.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          subline,
                          key: ValueKey(subline),
                          style: text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mic button at the centre of the wave: a moon-yellow core (the one
/// yellow on this screen) with two ripple rings leaving it on the breath.
class _MicCore extends StatelessWidget {
  const _MicCore({required this.breath});
  final Animation<double> breath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: breath,
              builder: (context, _) => CustomPaint(
                size: const Size(150, 150),
                painter: RipplePainter(
                  t: breath.value,
                  color: NightPalette.moon,
                  innerRadius: 34,
                  reach: 36,
                ),
              ),
            ),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFFFFE59A), NightPalette.moon],
              ),
              boxShadow: [
                BoxShadow(
                  color: NightPalette.moon.withValues(alpha: 0.45),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.mic_rounded,
                size: 32, color: NightPalette.nightLowest),
          ),
        ],
      ),
    );
  }
}

/// History list with real enter/exit motion: a new night slides in from the
/// top, a deleted one collapses away. Diffs the incoming list by id against
/// what is on screen, so the store can stay a plain sorted list.
class _NightList extends StatefulWidget {
  const _NightList({required this.sessions, required this.store});
  final List<SleepSession> sessions;
  final AutoSnoreStore store;

  @override
  State<_NightList> createState() => _NightListState();
}

class _NightListState extends State<_NightList> {
  final GlobalKey<AnimatedListState> _key = GlobalKey<AnimatedListState>();
  late final List<SleepSession> _items =
      List<SleepSession>.from(widget.sessions);

  @override
  void didUpdateWidget(covariant _NightList old) {
    super.didUpdateWidget(old);
    _sync(widget.sessions);
  }

  void _sync(List<SleepSession> next) {
    final animate = !reduceMotion(context);
    final Duration d = animate
        ? const Duration(milliseconds: 320)
        : Duration.zero;
    // Removals first (walk backwards so indices stay valid).
    for (int i = _items.length - 1; i >= 0; i--) {
      final s = _items[i];
      if (next.any((n) => n.id == s.id)) continue;
      _items.removeAt(i);
      _key.currentState?.removeItem(
        i,
        (context, anim) => _slide(anim, _NightTile(session: s, store: widget.store)),
        duration: d,
      );
    }
    // Then insertions, in target order.
    for (int i = 0; i < next.length; i++) {
      final n = next[i];
      final int at = _items.indexWhere((s) => s.id == n.id);
      if (at == i) {
        _items[i] = n; // same slot, refreshed data
        continue;
      }
      if (at >= 0) {
        // Order changed (rare): move without ceremony.
        _items.removeAt(at);
        _key.currentState?.removeItem(at, (_, _) => const SizedBox.shrink(),
            duration: Duration.zero);
      }
      _items.insert(i, n);
      _key.currentState?.insertItem(i, duration: d);
    }
  }

  Widget _slide(Animation<double> anim, Widget child) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.35),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _key,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      initialItemCount: _items.length,
      itemBuilder: (context, i, anim) =>
          _slide(anim, _NightTile(session: _items[i], store: widget.store)),
    );
  }
}

class _NightTile extends StatelessWidget {
  const _NightTile({required this.session, required this.store});
  final SleepSession session;
  final AutoSnoreStore store;

  @override
  Widget build(BuildContext context) {
    final color = bandColor(session.band);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.18),
          child: Text('${session.score}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(
            '${formatShortDate(session.startMs)} · ${bandLabel(session.band)}'),
        subtitle: Text(tr(
          zh: '${session.snoreCount} 次鼾声 · ${formatDuration(session.durationMs)}',
          en: '${session.snoreCount} snores · ${formatDuration(session.durationMs)}',
        )),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReportScreen(session: session, store: store),
        )),
        onLongPress: () => _confirmDelete(context),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '删除这一晚?', en: 'Delete this night?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              store.deleteSession(session.id);
              Navigator.of(ctx).pop();
            },
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
  }
}

/// The pre-flight briefing shown once before the first night.
class _Briefing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    Widget item(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(body,
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(zh: '睡前三件事', en: 'Three things before you sleep'),
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                zh: '做到了,早上的报告才是完整的一夜。',
                en: 'Do these and the morning report covers the whole night.',
              ),
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            item(
              Icons.power_outlined,
              tr(zh: '插上电', en: 'Plug it in'),
              tr(
                zh: '整夜采麦会耗电,别让手机半夜关机。',
                en: 'Listening all night uses battery; do not let the phone die at 3 am.',
              ),
            ),
            item(
              ios ? Icons.lock_outline : Icons.brightness_high_outlined,
              ios
                  ? tr(zh: '可以锁屏', en: 'You can lock the screen')
                  : tr(zh: '屏幕会保持常亮', en: 'The screen stays on'),
              ios
                  ? tr(
                      zh: '记录在后台继续。把手机屏幕朝下放在床头即可。',
                      en: 'Recording continues in the background. Just put the phone face down on the nightstand.',
                    )
                  : tr(
                      zh: '安卓没有后台录音,App 会锁住屏幕不熄。把亮度调到最低,屏幕朝下放。',
                      en: 'Android cannot record in the background, so the app keeps the screen awake. Turn brightness down and put it face down.',
                    ),
            ),
            item(
              Icons.do_not_disturb_on_outlined,
              ios
                  ? tr(zh: '开勿扰', en: 'Turn on Do Not Disturb')
                  : tr(zh: '别切走、开勿扰', en: 'Stay in the app, turn on Do Not Disturb'),
              ios
                  ? tr(
                      zh: '来电会打断录音,通话结束后自动继续。',
                      en: 'A call interrupts the recording; it resumes when the call ends.',
                    )
                  : tr(
                      zh: '切到别的 App 或接电话都会结束今晚的记录(已录部分会保留)。',
                      en: 'Switching apps or taking a call ends the night (what was recorded is kept).',
                    ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr(zh: '知道了,开始记录', en: 'Got it, start recording')),
            ),
          ],
        ),
      ),
    );
  }
}
