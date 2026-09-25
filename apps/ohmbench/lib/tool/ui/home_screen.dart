import 'package:flutter/material.dart';

import '../../bench/words.dart';
import '../examples.dart';
import '../format.dart';
import '../pro.dart';
import '../schematic/document.dart';
import '../sim/simulation.dart';
import '../store.dart';
import 'brand.dart';
import 'editor_screen.dart';
import 'haptics.dart';
import 'lab_theme.dart';
import 'live_preview.dart';
import 'schematic_painter.dart';
import 'scope.dart';
import 'settings_screen.dart';
import 'trouble.dart';

/// The first screen is the bench itself: a rectifier running edge to edge,
/// then your circuits and the examples, with the two actions docked in the
/// thumb zone. No app bar, no cards (brief PLAN.md §十·五).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final ProjectStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectStore get store => widget.store;

  /// Ids fading out before they are removed from the store, so a deleted
  /// row leaves with an animation instead of vanishing.
  final Set<String> _leaving = {};

  /// Rows on screen at first paint do not animate in; only rows that
  /// arrive later (a duplicate, an undo) do.
  late final Set<String> _firstPaint = {for (final p in store.projects) p.id};

  static const String _heroId = 'rectifier';

  /// The hero's loop stops once it has scrolled off screen (第四节).
  final ScrollController _scroll = ScrollController();
  bool _heroVisible = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The hero is ~320 pt plus the status bar; past that it is gone.
      final visible = _scroll.offset < 360;
      if (visible != _heroVisible) setState(() => _heroVisible = visible);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  late final ExampleCircuit _heroExample =
      kExamples.firstWhere((e) => e.id == _heroId);
  late final SchematicDocument _heroDoc = _heroExample.build();

  Future<void> _open(Project project, {bool autoRun = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          EditorScreen(store: store, project: project, autoRun: autoRun),
    ));
    if (mounted) setState(() {});
  }

  void _openSettings() {
    BenchHaptics.select();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => OhmSettingsScreen(store: store),
    ));
  }

  Future<bool> _roomForAnother() async {
    if (!store.atProjectLimit) return true;
    await showProSheet(
      context,
      reason: tr(
        zh: '免费版保存 ${ProjectStore.freeProjects} 张电路图。解锁 Pro 可以不限数量地新建和复制。',
        en: 'The free version keeps ${ProjectStore.freeProjects} circuit. Pro lets you create and duplicate as many as you like.',
      ),
    );
    return false;
  }

  Future<void> _createBlank() async {
    if (!await _roomForAnother()) return;
    BenchHaptics.commit();
    final project = store.create(
        tr(zh: '新电路', en: 'New circuit'), const SchematicDocument());
    await _open(project);
  }

  /// Examples open as scratch circuits, already running: free to run and
  /// edit, saved only when the user asks for a copy.
  Future<void> _openExample(ExampleCircuit example) {
    BenchHaptics.select();
    return _open(store.scratch(example.title, example.build()),
        autoRun: true);
  }

  Future<void> _duplicate(Project project) async {
    if (!await _roomForAnother()) return;
    BenchHaptics.commit();
    store.duplicate(project, tr(zh: '副本', en: 'copy'));
  }

  Future<void> _rename(Project project) async {
    final name = await showRenameDialog(context, project.name);
    if (name != null) store.rename(project, name);
  }

  /// Deletes at once and offers Undo — no "are you sure" (F4).
  Future<void> _delete(Project project) async {
    final messenger = ScaffoldMessenger.of(context);
    final index = store.projects.indexOf(project);
    BenchHaptics.commit();
    setState(() => _leaving.add(project.id));
    await Future<void>.delayed(
        BenchMotion.of(context, BenchMotion.exit(BenchMotion.medium)));
    if (!mounted) return;
    _leaving.remove(project.id);
    store.delete(project);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: MediaQuery.accessibleNavigationOf(context)
            ? BenchMotion.undoWindow * 5
            : BenchMotion.undoWindow,
        content: Text(tr(
            zh: '已删除「${project.name}」', en: 'Deleted "${project.name}"')),
        action: SnackBarAction(
          label: tr(zh: '撤销', en: 'Undo'),
          onPressed: () {
            if (store.restore(project, index) || !mounted) return;
            // The free slot was taken meanwhile: say why nothing came back.
            showProSheet(
              context,
              reason: tr(
                zh: '「${project.name}」没能恢复:免费版只保存 ${ProjectStore.freeProjects} 张电路,这个位置已经被新电路占了。解锁 Pro 或删掉新电路后可再建。',
                en: '"${project.name}" could not come back: the free version keeps ${ProjectStore.freeProjects} circuit and a new one has taken the slot. Unlock Pro, or delete the new one.',
              ),
            );
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Bench.background,
      bottomNavigationBar: _Dock(onSettings: _openSettings, onNew: _createBlank),
      body: ListenableBuilder(
        listenable: Listenable.merge([store, store.storageTrouble]),
        builder: (context, _) {
          final trouble =
              store.storageTrouble.value != null || store.savingBlocked;
          return CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: TickerMode(
                  enabled: _heroVisible,
                  child: _BenchHero(
                    doc: _heroDoc,
                    title: _heroExample.title,
                    onOpen: () => _openExample(_heroExample),
                  ),
                ),
              ),
              if (trouble)
                SliverToBoxAdapter(
                  child: _TroubleBanner(
                    text: storageTroubleText(store.storageTrouble.value,
                        blocked: store.savingBlocked),
                  ),
                ),
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: tr(zh: '我的电路', en: 'Your circuits'),
                  trailing: store.pro
                      ? null
                      : _CountPill(
                          used: store.projects.length,
                          limit: ProjectStore.freeProjects,
                        ),
                ),
              ),
              if (store.projects.isEmpty)
                SliverToBoxAdapter(child: _EmptyLibrary(onNew: _createBlank))
              else
                SliverList.builder(
                  itemCount: store.projects.length,
                  itemBuilder: (context, i) {
                    final project = store.projects[i];
                    return _Appear(
                      key: ValueKey(project.id),
                      animateIn: !_firstPaint.contains(project.id),
                      leaving: _leaving.contains(project.id),
                      child: _ProjectRow(
                        project: project,
                        first: i == 0,
                        onOpen: () {
                          if (_leaving.contains(project.id)) return;
                          BenchHaptics.select();
                          _open(project);
                        },
                        onRename: () => _rename(project),
                        onDuplicate: () => _duplicate(project),
                        onDelete: () => _delete(project),
                      ),
                    );
                  },
                ),
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: tr(zh: '示例', en: 'Examples'),
                  caption: tr(
                    zh: '打开就在运行,改哪儿都行',
                    en: 'Each one opens already running. Change anything.',
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    BenchSpace.l, 0, BenchSpace.l, BenchSpace.xl),
                sliver: SliverToBoxAdapter(
                  child: _ExampleGrid(
                    examples: [
                      for (final e in kExamples)
                        if (e.id != _heroId) e,
                      _heroExample,
                    ],
                    onOpen: _openExample,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------- hero

/// The signature scene: a rectifier actually running, edge to edge — wires
/// tinted by their solved voltage, charge moving at the solved current, and
/// a strip of scope plus a readout tracking the capacitor. Tapping it opens
/// this very circuit, already running.
class _BenchHero extends StatelessWidget {
  const _BenchHero({
    required this.doc,
    required this.title,
    required this.onOpen,
  });

  final SchematicDocument doc;
  final String title;
  final VoidCallback onOpen;

  static final Expando<ScopeTrace> _traces = Expando();

  /// The capacitor's node: what the readout and the scope strip follow.
  String? _outNode(SimRun run) {
    for (final p in doc.parts) {
      if (p.kind == PartKind.capacitor) return run.nodeAt(p.pins.first);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Pressable(
      onTap: onOpen,
      label: tr(
          zh: '打开「$title」并运行', en: 'Open "$title" and run it'),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Bench.panelBorder)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: top + 320,
              child: ExcludeSemantics(
                child: ClipRect(
                  child: LivePreview(
                  doc: doc,
                  live: true,
                  margin: 1.3,
                  maxScale: 30,
                  footerHeight: 66,
                  headerHeight: top + 64,
                  footer: (run, sample) => _scope(run, sample),
                  overlay: (run, sample) =>
                      _TopRow(top: top, readout: _readout(run, sample)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  BenchSpace.l, BenchSpace.m, BenchSpace.l, BenchSpace.l),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(zh: '画出来,跑起来', en: 'Draw it. Run it.'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: BenchSpace.xs),
                        Text(
                          tr(
                            zh: '上面这块半波整流正在真算:颜色是电压,亮点是电流。',
                            en: 'This half-wave rectifier is really being solved: colour is voltage, the dots are current.',
                          ),
                          style: BenchType.bodyStyle(color: Bench.inkDim),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BenchSpace.m),
                  const _RunHint(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scope(SimRun run, int sample) {
    final node = _outNode(run);
    final values = node == null ? null : run.nodeSeries[node];
    if (values == null || values.isEmpty) return const SizedBox.shrink();
    final trace = _traces[run] ??=
        ScopeTrace(values: values, window: run.window, unit: 'V');
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BenchSpace.l, 0, BenchSpace.l, BenchSpace.m),
      child: SizedBox(
        height: 50,
        child: CustomPaint(painter: ScopePainter(trace: trace, cursor: sample)),
      ),
    );
  }

  String? _readout(SimRun run, int sample) {
    final node = _outNode(run);
    final values = node == null ? null : run.nodeSeries[node];
    if (values == null || values.isEmpty) return null;
    return formatSi(values[sample.clamp(0, values.length - 1)], 'V');
  }
}

/// Wordmark on the left, the live capacitor voltage on the right.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.top, required this.readout});

  final double top;
  final String? readout;

  @override
  Widget build(BuildContext context) {
    // The readout is a hero number: it may cap its growth at 1.5× (F10).
    final scaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            BenchSpace.l, top + BenchSpace.m, BenchSpace.l, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const OhmMark(size: 18),
            const SizedBox(width: BenchSpace.s),
            const OhmWordmark(size: BenchType.title),
            const SizedBox(width: BenchSpace.m),
            if (readout != null)
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    readout!,
                    textAlign: TextAlign.end,
                    textScaler: scaler,
                    style: BenchType.monoStyle(BenchType.display,
                        bold: true, color: Bench.positive),
                  ),
                  Text(
                    tr(zh: '电容电压', en: 'across C'),
                    textAlign: TextAlign.end,
                    textScaler: scaler,
                    style: BenchType.monoStyle(BenchType.label,
                        color: Bench.inkDim),
                  ),
                ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Run it" affordance on the hero: an outlined pill with a drawn play
/// glyph. The whole hero is the button; this only says so.
class _RunHint extends StatelessWidget {
  const _RunHint();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: BenchSpace.row),
        padding: const EdgeInsets.symmetric(horizontal: BenchSpace.l),
        decoration: BoxDecoration(
          borderRadius: BenchRadius.pillAll,
          border: Border.all(color: Bench.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BenchGlyph(GlyphKind.play, size: 14, color: Bench.charge),
            const SizedBox(width: BenchSpace.s),
            Text(tr(zh: '打开', en: 'Open'),
                style: BenchType.bodyStyle(weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- sections

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          BenchSpace.l, BenchSpace.xl, BenchSpace.l, BenchSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              ?trailing,
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: BenchSpace.xs),
            Text(caption!, style: BenchType.bodyStyle(color: Bench.inkDim)),
          ],
        ],
      ),
    );
  }
}

/// Free-tier usage as a gauge reading: "1 / 1".
class _CountPill extends StatelessWidget {
  const _CountPill({required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final full = used >= limit;
    // Never colour alone: the words say "full" too. Over the limit (Pro
    // lapsed, or created before the cap) reads as a count, not "2 / 1".
    final text = used > limit
        ? tr(zh: '$used 张 · 免费上限 $limit', en: '$used · free limit $limit')
        : full
            ? tr(zh: '$used / $limit · 已满', en: '$used / $limit · full')
            : '$used / $limit';
    return Tooltip(
      message: tr(zh: '免费版可保存的数量', en: 'Circuits the free version keeps'),
      child: Semantics(
        label: tr(
            zh: '已保存 $used 张,免费版上限 $limit 张',
            en: '$used of $limit free circuits saved'),
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: BenchSpace.m, vertical: BenchSpace.xs),
          decoration: BoxDecoration(
            borderRadius: BenchRadius.pillAll,
            border: Border.all(color: full ? Bench.warning : Bench.outline),
          ),
          child: Text(text,
              style: BenchType.monoStyle(BenchType.label,
                  color: full ? Bench.warning : Bench.inkDim)),
        ),
      ),
    );
  }
}

/// A saved circuit as one ruled row: its drawing, its name, its size.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.project,
    required this.first,
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Project project;
  final bool first;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final parts = project.partCount;
    final meta =
        '${tr(zh: '$parts 个元件', en: '$parts ${parts == 1 ? 'part' : 'parts'}')} · ${_ago(project.updated)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: first
              ? const BorderSide(color: Bench.panelBorder)
              : BorderSide.none,
          bottom: const BorderSide(color: Bench.panelBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onTap: onOpen,
              label: '${project.name}, $meta',
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    BenchSpace.l, BenchSpace.m, 0, BenchSpace.m),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      _Sheet(
                        width: 88,
                        height: 60,
                        child: project.document.isEmpty
                            ? const SizedBox.shrink()
                            : LivePreview(
                                doc: project.document,
                                showGrid: false,
                                margin: 1.0,
                                maxScale: 20,
                              ),
                      ),
                      const SizedBox(width: BenchSpace.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(project.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: BenchSpace.xs),
                            Text(meta,
                                style: BenchType.bodyStyle(
                                    color: Bench.inkDim,
                                    size: BenchType.label)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: tr(zh: '更多操作', en: 'More actions'),
            icon: const Icon(Icons.more_vert_rounded, color: Bench.inkDim),
            onSelected: (v) => switch (v) {
              'rename' => onRename(),
              'duplicate' => onDuplicate(),
              _ => onDelete(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'rename', child: Text(tr(zh: '重命名', en: 'Rename'))),
              PopupMenuItem(
                  value: 'duplicate',
                  child: Text(tr(zh: '复制一份', en: 'Duplicate'))),
              PopupMenuItem(
                value: 'delete',
                child: Text(tr(zh: '删除', en: 'Delete'),
                    style: const TextStyle(color: Bench.error)),
              ),
            ],
          ),
          const SizedBox(width: BenchSpace.xs),
        ],
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return tr(zh: '刚刚', en: 'just now');
    if (d.inHours < 1) {
      return tr(zh: '${d.inMinutes} 分钟前', en: '${d.inMinutes} min ago');
    }
    if (d.inDays < 1) return tr(zh: '${d.inHours} 小时前', en: '${d.inHours} h ago');
    if (d.inDays < 30) return tr(zh: '${d.inDays} 天前', en: '${d.inDays} d ago');
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// A small drawing sheet: the board colour, a hairline edge, radius 4.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, this.width, required this.height});

  final Widget child;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Bench.background,
        borderRadius: BenchRadius.smAll,
        border: Border.all(color: Bench.panelBorder),
      ),
      child: child,
    );
  }
}

/// Nothing saved yet: the slot shows a faint ghost of the circuit that could
/// be here — drawn by the same painter as a real one — and the way to start.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onNew});

  final VoidCallback onNew;

  static final SchematicDocument _ghost =
      kExamples.firstWhere((e) => e.id == 'divider').build();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BenchSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: _Sheet(
              height: 112,
              child: LayoutBuilder(
                builder: (context, c) => CustomPaint(
                  size: c.biggest,
                  painter: SchematicPainter(
                    doc: _ghost,
                    view: CanvasView.fit(_ghost, c.biggest,
                        margin: 1.4, maxScale: 22),
                    showLabels: false,
                    markOpenPins: false,
                    opacity: 0.22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: BenchSpace.m),
          Text(tr(zh: '第一张电路会出现在这里', en: 'Your first circuit lands here'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: BenchSpace.xs),
          Text(
            tr(
              zh: '新建一张空白电路,或打开下面任意一个示例改起来。每一步都自动保存,关掉应用也不会丢。',
              en: 'Start a new circuit, or open any example below and change it. Every step saves itself, even if the app is closed.',
            ),
            style: BenchType.bodyStyle(color: Bench.inkDim),
          ),
          const SizedBox(height: BenchSpace.s),
          OutlinedButton(
            onPressed: onNew,
            child: Text(tr(zh: '新电路', en: 'New circuit')),
          ),
        ],
      ),
    );
  }
}

class _ExampleGrid extends StatelessWidget {
  const _ExampleGrid({required this.examples, required this.onOpen});

  final List<ExampleCircuit> examples;
  final ValueChanged<ExampleCircuit> onOpen;

  static final Map<String, SchematicDocument> _docs = {};

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < examples.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: BenchSpace.l));
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _tile(examples[i])),
          const SizedBox(width: BenchSpace.m),
          Expanded(
            child: i + 1 < examples.length
                ? _tile(examples[i + 1])
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _tile(ExampleCircuit e) => Builder(
        builder: (context) => Pressable(
          onTap: () => onOpen(e),
          label: '${e.title}. ${e.blurb}',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sheet(
                  height: 96,
                  child: LivePreview(
                    doc: _docs[e.id] ??= e.build(),
                    margin: 1.2,
                    maxScale: 22,
                  ),
                ),
                const SizedBox(height: BenchSpace.s),
                Text(e.title,
                    style: BenchType.bodyStyle(weight: FontWeight.w600)),
                const SizedBox(height: BenchSpace.xs),
                Text(e.blurb,
                    style: BenchType.bodyStyle(
                        color: Bench.inkDim, size: BenchType.label)),
              ],
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------- dock

/// The thumb-zone bar: settings on the left, "New circuit" on the right.
class _Dock extends StatelessWidget {
  const _Dock({required this.onSettings, required this.onNew});

  final VoidCallback onSettings;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Bench.backgroundTop,
        border: Border(top: BorderSide(color: Bench.panelBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              BenchSpace.s, BenchSpace.s, BenchSpace.l, BenchSpace.s),
          child: Row(
            children: [
              IconButton(
                tooltip: tr(zh: '设置', en: 'Settings'),
                icon: const Icon(Icons.tune_rounded, color: Bench.ink),
                onPressed: onSettings,
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: BenchSpace.xl, vertical: BenchSpace.m),
                  ),
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr(zh: '新电路', en: 'New circuit')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TroubleBanner extends StatelessWidget {
  const _TroubleBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
            BenchSpace.l, BenchSpace.l, BenchSpace.l, 0),
        padding: const EdgeInsets.all(BenchSpace.m),
        decoration: BoxDecoration(
          color: Bench.errorContainer,
          borderRadius: BenchRadius.smAll,
          border: Border.all(color: Bench.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Bench.onErrorContainer, size: 20),
            const SizedBox(width: BenchSpace.s),
            Expanded(
              child: Text(text,
                  style: BenchType.bodyStyle(color: Bench.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Size-and-fade in when a row arrives after first paint; out while
/// [leaving]. Collapses to an instant change under reduce motion.
class _Appear extends StatefulWidget {
  const _Appear({
    super.key,
    required this.child,
    this.leaving = false,
    this.animateIn = true,
  });

  final Widget child;
  final bool leaving;
  final bool animateIn;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, value: widget.animateIn ? 0 : 1);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _c, curve: BenchMotion.enter);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value < 1 && !_c.isAnimating && !widget.leaving) {
      _c.animateTo(1, duration: BenchMotion.of(context, BenchMotion.medium));
    }
  }

  @override
  void didUpdateWidget(covariant _Appear old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _c.animateBack(0,
          duration: BenchMotion.of(
              context, BenchMotion.exit(BenchMotion.medium)));
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _curve, child: widget.child),
    );
  }
}
