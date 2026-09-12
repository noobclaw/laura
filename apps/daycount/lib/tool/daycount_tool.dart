import 'package:flutter/material.dart';

import '../core/day_change.dart';
import '../core/l10n.dart';
import '../core/purchase.dart';
import 'accent_ink.dart';
import 'event_detail.dart';
import 'event_edit.dart';
import 'hero_card.dart';
import 'models.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';
import 'widget_bridge.dart';

/// 倒数日 — offline countdown & anniversary tracker.
class DaycountTool extends ToolModule {
  DaycountTool() {
    // Every "N days" on screen is computed from DateTime.now() at build
    // time; without this an app left open overnight (or brought back from
    // the background the next morning) kept showing yesterday's numbers
    // and never told the home-screen widget to re-render either.
    dayChange
      ..start()
      ..addListener(() {
        store.touch();
        // Re-push, not just re-render: the *choice* of featured event is made
        // at push time, so once a one-off day has passed the widget must move
        // on to the next nearest one.
        WidgetBridge.push(store.events);
      });
    // Label templates are written in the app language; switching it must
    // reach the widget too.
    AppLanguage.override.addListener(() => WidgetBridge.push(store.events));
  }

  final EventStore store = EventStore()..load();
  final DayChangeNotifier dayChange = DayChangeNotifier();

  @override
  Widget buildHome(BuildContext context) => _HomeBody(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        // Renders nothing; surfaces store errors/pending/unlocked as snackbars.
        _ProTile(store: store),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => RestorePurchasesTile(pro: store.pro),
        ),
        ListTile(
          leading: const Icon(Icons.widgets_outlined),
          title: Text(tr(zh: '刷新桌面小组件', en: 'Refresh home-screen widget')),
          subtitle: Text(tr(zh: '把最近的日子同步到主屏小组件', en: 'Sync the nearest day to the widget')),
          onTap: () async {
            await WidgetBridge.push(store.events);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(zh: '已刷新小组件', en: 'Widget refreshed'))),
              );
            }
          },
        ),
      ];
}

class _ProTile extends StatelessWidget {
  const _ProTile({required this.store});
  final EventStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.pro) {
          return ListTile(
            leading: const Icon(Icons.verified, color: Colors.amber),
            title: Text(tr(zh: '已解锁 Pro', en: 'Pro unlocked')),
            subtitle: Text(tr(
              zh: '无限日子 · 全部主题色 · 感谢支持',
              en: 'Unlimited days · All theme colors · Thank you',
            )),
          );
        }
        return ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(tr(zh: '解锁 Pro（一次买断）', en: 'Unlock Pro (one-time purchase)')),
          subtitle: Text(tr(zh: '无限日子 + 全部主题色', en: 'Unlimited days + all theme colors')),
          // The store's own localized price, so nobody is quoted a currency
          // they will not be charged in.
          trailing: FilledButton.tonal(
            onPressed: () => showProSheet(context),
            child: const ProPriceText(fallback: r'$1.99'),
          ),
          onTap: () => showProSheet(context),
        );
      },
    );
  }
}

class _HomeBody extends StatefulWidget {
  const _HomeBody({required this.store});
  final EventStore store;

  @override
  State<_HomeBody> createState() => _HomeBodyState();
}

/// Home: the nearest day as a hero card, then every other day as an
/// animated list. The list is diffed against the store on every change so
/// adds slide in from below, deletes collapse, and a newly pinned day is
/// lifted out of its slot and re-inserted at the top instead of the whole
/// list hard-refreshing.
class _HomeBodyState extends State<_HomeBody> {
  EventStore get store => widget.store;

  static const Duration _rowAnim = Duration(milliseconds: 280);

  final GlobalKey<SliverAnimatedListState> _listKey =
      GlobalKey<SliverAnimatedListState>();
  CountdownEvent? _featured;
  final List<CountdownEvent> _rows = [];

  /// Ids whose row badge has already rolled its count in. A row that is
  /// lifted out and re-inserted (pin, edit, midnight) is a new element, and
  /// without this its number would count up from zero all over again.
  final Set<String> _rolled = {};

  @override
  void initState() {
    super.initState();
    _fill();
    store.addListener(_sync);
  }

  @override
  void dispose() {
    store.removeListener(_sync);
    super.dispose();
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Non-animated snapshot (first load, or while the list is not mounted).
  void _fill() {
    if (!store.loaded) return;
    final items = sortedEvents(store.events, DateTime.now());
    _featured = items.firstOrNull;
    _rows
      ..clear()
      ..addAll(items.skip(1));
  }

  void _sync() {
    if (!store.loaded) return;
    final list = _listKey.currentState;
    if (list == null) {
      setState(_fill);
      return;
    }
    final items = sortedEvents(store.events, DateTime.now());
    final featured = items.firstOrNull;
    final rows = items.skip(1).toList();
    final d = _reduceMotion ? Duration.zero : _rowAnim;

    // 1. Rows that are gone: remove from the end so indices stay valid.
    final keep = {for (final e in rows) e.id};
    for (var i = _rows.length - 1; i >= 0; i--) {
      if (keep.contains(_rows[i].id)) continue;
      final gone = _rows.removeAt(i);
      list.removeItem(i, (_, anim) => _row(gone, anim, hero: false),
          duration: d);
    }
    // 2. Walk the target order; anything out of place is lifted out and
    //    re-inserted at its new slot (pin/unpin, a date edit, midnight).
    for (var i = 0; i < rows.length; i++) {
      final want = rows[i];
      if (i < _rows.length && _rows[i].id == want.id) continue;
      final j = _rows.indexWhere((e) => e.id == want.id);
      if (j >= 0) {
        final moved = _rows.removeAt(j);
        list.removeItem(j, (_, anim) => _row(moved, anim, hero: false),
            duration: d);
      }
      _rows.insert(i, want);
      list.insertItem(i, duration: d);
    }
    setState(() => _featured = featured);
  }

  Future<void> _addEvent() async {
    if (store.atLimit) {
      _showLimitDialog();
      return;
    }
    final draft = await Navigator.of(context).push<EventDraft>(
      MaterialPageRoute(builder: (_) => EventEditPage(pro: store.pro)),
    );
    if (draft != null) {
      store.add(
        title: draft.title,
        date: draft.date,
        emoji: draft.emoji,
        colorValue: draft.colorValue,
        pinned: draft.pinned,
        yearlyRepeat: draft.yearlyRepeat,
        note: draft.note,
      );
    }
  }

  void _showLimitDialog() {
    // The Pro sheet explains the cap and shows the store price; the unlock
    // arrives on the purchase stream and flips the flag via main.dart's
    // onUnlocked.
    showProSheet(
      context,
      reason: tr(
        zh: '免费版最多记录 ${EventStore.freeLimit} 个日子,你已经用满了。',
        en: 'The free version keeps up to ${EventStore.freeLimit} days — you have filled it.',
      ),
    );
  }

  void _open(CountdownEvent e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDetailPage(store: store, eventId: e.id),
      ),
    );
  }

  /// One list row with its enter/exit transition: slides up and fades in,
  /// collapses on the way out (the same animation run backwards).
  Widget _row(CountdownEvent e, Animation<double> anim, {required bool hero}) {
    final rollIn = _rolled.add(e.id);
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero)
              .animate(curved),
          child: _EventCard(
            event: e,
            hero: hero,
            rollIn: rollIn,
            onTap: () => _open(e),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    final now = DateTime.now();
    return Scaffold(
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : featured == null
              ? const _EmptyState()
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                      sliver: SliverToBoxAdapter(
                        child: FeaturedCard(
                          event: featured,
                          status: statusOf(featured, now),
                          progress: progressOf(featured, now),
                          onTap: () => _open(featured),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
                      sliver: SliverAnimatedList(
                        key: _listKey,
                        initialItemCount: _rows.length,
                        itemBuilder: (context, i, anim) => i < _rows.length
                            ? _row(_rows[i], anim, hero: true)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: PressScale(
        scale: 0.94,
        child: FloatingActionButton.extended(
          onPressed: _addEvent,
          icon: const Icon(Icons.add),
          label: Text(tr(zh: '添加日子', en: 'Add a day')),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BirdMark(size: 112),
              const SizedBox(height: 22),
              Text(tr(zh: '还没有日子', en: 'No days yet'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                tr(
                  zh: '点击右下角「添加日子」，记录生日、纪念日、\n考试倒计时……并放上桌面小组件。',
                  en: 'Tap "Add a day" to track birthdays, anniversaries,\nexam countdowns… and put them on your widget.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onTap,
    this.hero = true,
    this.rollIn = true,
  });
  final CountdownEvent event;
  final VoidCallback onTap;

  /// False for the snapshot rendered while a row animates out, so the same
  /// emoji Hero tag never exists twice on the page.
  final bool hero;

  /// Whether the day badge counts up from zero (first appearance only).
  final bool rollIn;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final s = statusOf(event, now);
    final progress = progressOf(event, now);
    final color = event.color;
    final ink = onColorFor(color);
    final label = s.isToday
        ? tr(zh: '就是今天', en: 'Today!')
        : (s.isFuture ? tr(zh: '还有', en: 'in') : tr(zh: '已过去', en: 'past'));

    final emoji = Text(event.emoji, style: const TextStyle(fontSize: 26));
    final cs = Theme.of(context).colorScheme;

    return PressScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        // Flat tile with a faint wash of the event's own accent — reads as a
        // premium countdown card rather than a generic list row. A 6% wash is
        // invisible on a dark surface, so the tint is stronger there.
        color: color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.07),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: hero
                      ? Hero(
                          tag: emojiHeroTag(event),
                          child: Material(
                            type: MaterialType.transparency,
                            child: emoji,
                          ),
                        )
                      : emoji,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (event.pinned)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.push_pin, size: 15, color: cs.onSurfaceVariant),
                            ),
                          Expanded(
                            child: Text(
                              event.title.isEmpty ? tr(zh: '未命名', en: 'Untitled') : event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.target.year}-${_two(s.target.month)}-${_two(s.target.day)} ${weekdayLabel(s.target)}'
                        '${event.yearlyRepeat ? ' · ${tr(zh: '每年', en: 'yearly')}' : ''}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: color.withValues(alpha: 0.15),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _DayBadge(label: label, status: s, ink: ink, rollIn: rollIn),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// The "in 42 days" badge on a list row. Its 10–11px labels are small text,
/// so the whole badge sits on the accent's small-text surface (the dark band
/// on a mid-tone accent, the accent itself on a light one). Reads as one
/// phrase to assistive tech.
class _DayBadge extends StatelessWidget {
  const _DayBadge({
    required this.label,
    required this.status,
    required this.ink,
    this.rollIn = true,
  });
  final String label;
  final EventStatus status;
  final AccentInk ink;

  /// Count up from zero on first appearance; later builds start on the value.
  final bool rollIn;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fg = ink.fg;
    final days = status.absDays.toDouble();
    return MergeSemantics(
      child: Semantics(
        label: eventCountPhrase(status),
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minWidth: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ink.small,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
              const SizedBox(height: 1),
              if (status.isToday)
                Text(
                  '🎉',
                  style: TextStyle(fontSize: 30, height: 1.05, color: fg),
                )
              else
                // The count rolls up to its value instead of snapping in.
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: rollIn ? 0 : days, end: days),
                  duration:
                      reduce ? Duration.zero : const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '${v.round()}',
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: fg,
                    ),
                  ),
                ),
              if (!status.isToday)
                Text(tr(zh: '天', en: 'days'),
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
