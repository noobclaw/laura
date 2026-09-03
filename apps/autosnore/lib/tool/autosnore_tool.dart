import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'home_screen.dart';
import 'pro.dart';
import 'store.dart';
import 'tool_module.dart';

/// AutoSnore: offline snore recorder. The store is created once and shared
/// across every screen; everything the shell needs is behind [ToolModule].
class AutoSnoreTool extends ToolModule {
  AutoSnoreTool() {
    store.load();
  }

  final AutoSnoreStore store = AutoSnoreStore();

  @override
  Widget buildHome(BuildContext context) => HomeScreen(store: store);

  @override
  List<Widget> buildSettingsItems(BuildContext context) => [
        _SensitivityTile(store: store),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(tr(zh: '鼾声记录原理', en: 'How snore recording works')),
          subtitle: Text(tr(
            zh: '设备端分析声音响度,录音不出手机',
            en: 'Loudness analysed on-device — audio never leaves your phone',
          )),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const _HowItWorksPage(),
          )),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(
                store.pro ? Icons.verified : Icons.workspace_premium_outlined),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: Text(store.pro
                ? tr(zh: '感谢支持', en: 'Thanks for your support')
                : tr(
                    zh: '一次买断 · 无限历史 / 趋势 / 对比 / CSV 导出',
                    en: 'One-time · unlimited history / trends / comparison / CSV',
                  )),
            onTap: store.pro ? null : () => showProSheet(context),
          ),
        ),
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.pro
              ? const SizedBox.shrink()
              : ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
                  subtitle: Text(tr(
                    zh: '换机或重装后找回已购的 Pro',
                    en: 'Recover Pro after a reinstall or new device',
                  )),
                  onTap: () => PurchaseService.instance.restore(),
                ),
        ),
      ];
}

/// Sensitivity slider. Tracks the drag locally and only persists on release,
/// so a drag doesn't rewrite the whole session file on every tick.
class _SensitivityTile extends StatefulWidget {
  const _SensitivityTile({required this.store});
  final AutoSnoreStore store;

  @override
  State<_SensitivityTile> createState() => _SensitivityTileState();
}

class _SensitivityTileState extends State<_SensitivityTile> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final double value = _dragValue ?? widget.store.sensitivity;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune),
                  const SizedBox(width: 16),
                  Text(tr(zh: '检测灵敏度', en: 'Detection sensitivity'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text(
                    value < 0.34
                        ? tr(zh: '低', en: 'Low')
                        : value > 0.66
                            ? tr(zh: '高', en: 'High')
                            : tr(zh: '中', en: 'Medium'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              Slider(
                value: value,
                onChanged: (v) => setState(() => _dragValue = v),
                onChangeEnd: (v) {
                  widget.store.setSensitivity(v);
                  setState(() => _dragValue = null);
                },
              ),
              Text(
                tr(
                  zh: '越高越容易记录到轻微响声,越低越只记录明显打鼾。',
                  en: 'Higher catches faint sounds; lower records only clear snoring.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '鼾声记录原理', en: 'How it works'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          tr(
            zh: '记录时,AutoSnore 通过麦克风持续测量声音的响度(不保存任何音频),'
                '当响度明显高于房间的背景噪音并持续一小段时间,就记为一次「鼾声/响声」事件。\n\n'
                '早晨你会看到:整夜的鼾声次数、鼾声指数(每小时次数)、鼾声占比、'
                '最响时刻,以及一条整夜响度曲线。规律出现的响声更可能是持续打鼾,'
                '零散的更像偶发环境噪音。\n\n'
                '全程离线:应用没有网络权限,声音只在你的手机上分析,'
                '数据不会上传到任何服务器。\n\n'
                '这是一个记录与自我观察工具,不用于任何医疗诊断。持续打鼾或呼吸暂停请咨询医生。',
            en: 'While recording, AutoSnore continuously measures how loud the '
                'sound is through the microphone (no audio is ever saved). When '
                'the loudness rises clearly above the room\'s background noise '
                'for a short while, it is logged as one snore / noise event.\n\n'
                'In the morning you see: the number of snore events, the snore '
                'index (events per hour), the share of the night spent snoring, '
                'the loudest moment, and a loudness curve for the whole night. '
                'Rhythmic events are more likely real snoring; scattered ones '
                'are more likely occasional ambient noise.\n\n'
                'Fully offline: the app has no network permission, sound is '
                'analysed only on your phone, and nothing is uploaded to any '
                'server.\n\n'
                'This is a recording and self-observation tool, not for any '
                'medical diagnosis. See a doctor about persistent snoring or '
                'sleep apnea.',
          ),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

