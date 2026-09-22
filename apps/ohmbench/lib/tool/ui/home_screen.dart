import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../examples.dart';
import '../pro.dart';
import '../schematic/document.dart';
import '../store.dart';
import 'editor_screen.dart';
import 'lab_theme.dart';
import 'live_preview.dart';
import 'trouble.dart';

/// The library: a live bench up top, your circuits, and starter examples.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final ProjectStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ProjectStore get store => widget.store;

  /// Ids fading out before they are removed from the store, so a deleted
  /// card leaves the list with an animation instead of vanishing.
  final Set<String> _leaving = {};

  late final SchematicDocument _heroDoc =
      kExamples.firstWhere((e) => e.id == 'rectifier').build();

  Future<void> _open(Project project) async {
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => EditorScreen(store: store, project: project),
      transitionsBuilder: (_, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ));
    if (mounted) setState(() {});
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
    final project = store.create(
        tr(zh: '新电路', en: 'New circuit'), const SchematicDocument());
    await _open(project);
  }

  Future<void> _createFromExample(ExampleCircuit example) async {
    if (!await _roomForAnother()) return;
    final project = store.create(example.title, example.build());
    await _open(project);
  }

  Future<void> _duplicate(Project project) async {
    if (!await _roomForAnother()) return;
    store.duplicate(project, tr(zh: '副本', en: 'copy'));
  }

  Future<void> _rename(Project project) async {
    final name = await showRenameDialog(context, project.name);
    if (name != null) store.rename(project, name);
  }

  Future<void> _delete(Project project) async {
    final index = store.projects.indexOf(project);
    setState(() => _leaving.add(project.id));
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    _leaving.remove(project.id);
    store.delete(project);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(tr(zh: '已删除「${project.name}」', en: 'Deleted "${project.name}"')),
      action: SnackBarAction(
        label: tr(zh: '撤销', en: 'Undo'),
        onPressed: () => store.restore(project, index),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, store.storageTrouble]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        return CustomScrollView(
          slivers: [
            if (store.storageTrouble.value != null || store.savingBlocked)
              SliverToBoxAdapter(
                  child: _TroubleCard(
                      text: storageTroubleText(store.storageTrouble.value,
                          blocked: store.savingBlocked))),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _HeroBench(doc: _heroDoc, onNew: _createBlank),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(tr(zh: '我的电路', en: 'Your circuits'),
                        style: text.titleLarge),
                    const Spacer(),
                    if (!store.pro)
                      _CountChip(
                        label: '${store.projects.length} / ${ProjectStore.freeProjects}',
                        tooltip: tr(zh: '免费版可保存的数量', en: 'Circuits the free version keeps'),
                      ),
                  ],
                ),
              ),
            ),
            if (store.projects.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _EmptyLibrary(onNew: _createBlank),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: store.projects.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final project = store.projects[i];
                    return _Appear(
                      key: ValueKey(project.id),
                      leaving: _leaving.contains(project.id),
                      child: _ProjectCard(
                        project: project,
                        onOpen: () {
                          if (!_leaving.contains(project.id)) _open(project);
                        },
                        onRename: () => _rename(project),
                        onDuplicate: () => _duplicate(project),
                        onDelete: () => _delete(project),
                      ),
                    );
                  },
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 4),
              sliver: SliverToBoxAdapter(
                child: Text(tr(zh: '从示例开始', en: 'Start from an example'),
                    style: text.titleLarge),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Text(
                  tr(
                    zh: '每一个都能直接运行 —— 打开后按右下角的播放键',
                    en: 'Every one runs as-is — open it and press play',
                  ),
                  style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: kExamples.length,
                itemBuilder: (context, i) => _ExampleCard(
                  example: kExamples[i],
                  onTap: () => _createFromExample(kExamples[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The signature scene: a rectifier actually running on the bench — cyan
/// swelling and fading with the sine, charge pulsing through the diode.
class _HeroBench extends StatelessWidget {
  const _HeroBench({required this.doc, required this.onNew});

  final SchematicDocument doc;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: 252,
        decoration: const BoxDecoration(color: Bench.background),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 160,
              child: LivePreview(doc: doc, live: true, margin: 1.4, maxScale: 30),
            ),
            // Fade the bench into the caption area.
            const Positioned(
              left: 0,
              right: 0,
              top: 120,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000A1016), Bench.background],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(zh: '画出来,跑起来', en: 'Draw it. Run it.'),
                          style: const TextStyle(
                            color: Bench.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            zh: 'SPICE 同口径 · 全离线 · 作品丢不了',
                            en: 'SPICE-grade · fully offline · nothing lost',
                          ),
                          style: const TextStyle(
                              color: Bench.inkDim, fontSize: 13.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Bench.charge,
                      foregroundColor: const Color(0xFF2B2100),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onPressed: onNew,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr(zh: '新电路', en: 'New')),
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

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.tooltip});

  final String label;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }
}

/// Fade-and-rise on first appearance; fade-and-shrink while [leaving].
class _Appear extends StatefulWidget {
  const _Appear({super.key, required this.child, this.leaving = false});

  final Widget child;
  final bool leaving;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();

  @override
  void didUpdateWidget(covariant _Appear old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
              .animate(curved),
          child: widget.child,
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onOpen,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final parts = project.partCount;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 108,
                  height: 72,
                  child: project.document.isEmpty
                      ? const ColoredBox(
                          color: Bench.background,
                          child: Icon(Icons.grid_4x4_rounded,
                              color: Bench.gridDot, size: 30),
                        )
                      : LivePreview(
                          doc: project.document,
                          showGrid: false,
                          margin: 1.0,
                          maxScale: 20,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${tr(zh: '$parts 个元件', en: '$parts ${parts == 1 ? 'part' : 'parts'}')} · ${_ago(project.updated)}',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr(zh: '更多', en: 'More'),
                onSelected: (v) => switch (v) {
                  'rename' => onRename(),
                  'duplicate' => onDuplicate(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(tr(zh: '重命名', en: 'Rename')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'duplicate',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.copy_rounded),
                      title: Text(tr(zh: '复制', en: 'Duplicate')),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: cs.error),
                      title: Text(tr(zh: '删除', en: 'Delete'),
                          style: TextStyle(color: cs.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  cs.primary.withValues(alpha: 0.28),
                  cs.primary.withValues(alpha: 0.04),
                ]),
              ),
              child: Icon(Icons.electric_bolt_rounded, color: cs.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(zh: '还没有电路', en: 'No circuits yet'),
                      style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      zh: '开一张空白画布,或者挑下面一个示例改起来。每一步都自动保存。',
                      en: 'Open a blank bench, or pick an example below to modify. Every step saves itself.',
                    ),
                    style: text.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact),
                    onPressed: onNew,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr(zh: '空白画布', en: 'Blank bench')),
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

class _ExampleCard extends StatelessWidget {
  const _ExampleCard({required this.example, required this.onTap});

  final ExampleCircuit example;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: LivePreview(
                    doc: _docs[example.id] ??= example.build(),
                    margin: 1.2,
                    maxScale: 22,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(example.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(example.blurb,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final Map<String, SchematicDocument> _docs = {};
}

class _TroubleCard extends StatelessWidget {
  const _TroubleCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onErrorContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
