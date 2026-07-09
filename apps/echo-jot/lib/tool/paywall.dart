import 'package:flutter/material.dart';

/// Free tier: this many notes. The unlock is a one-time purchase wired to
/// in_app_purchase before store submission; this build shows the paywall
/// with purchase disabled so the full flow is reviewable.
const int freeNoteLimit = 30;

/// Returns true if the user may create another note.
Future<bool> checkNoteQuota(BuildContext context, int noteCount) async {
  if (noteCount < freeNoteLimit) return true;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('解锁无限笔记'),
      content: const Text(
        '免费版最多保存 $freeNoteLimit 条笔记。\n\n'
        'Pro 一次买断:无限笔记 + 批量导出。\n'
        '(内购将在正式版开放,当前为体验版)',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  return false;
}
