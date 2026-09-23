import '../../bench/words.dart';

/// One sentence for a storage problem reported by `ProjectStore`.
String storageTroubleText(String? kind, {required bool blocked}) {
  if (blocked || kind == 'load') {
    return tr(
      zh: '读取已保存的电路时出错。为了不覆盖它们,本次暂停保存 —— 请重启应用。',
      en: 'Your saved circuits could not be read. Saving is paused so nothing is overwritten — please restart the app.',
    );
  }
  return switch (kind) {
    'corrupt' => tr(
        zh: '保存文件已损坏,原文件已改名留档(.corrupt-…),没有被覆盖。本次从空白开始。',
        en: 'The save file was damaged. It was kept aside as a .corrupt-… backup, not overwritten, and the app started empty.',
      ),
    'skipped' => tr(
        zh: '有电路无法读取,已原样保留在文件里,不会被删除。',
        en: 'Some circuits could not be read. They are kept in the file untouched, not deleted.',
      ),
    _ => tr(
        zh: '保存失败(存储空间满或不可用)。改动还在内存里,继续编辑会自动重试。',
        en: 'Saving failed (storage full or unavailable). Your changes are still in memory and will be retried as you edit.',
      ),
  };
}
