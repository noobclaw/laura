import '../i18n/txt.dart';

/// One sentence for a storage problem reported by `ProjectStore`.
String storageTroubleText(String? kind, {required bool blocked}) {
  if (blocked || kind == 'load') {
    return Txt.savedCircuitsCouldNot;
  }
  return switch (kind) {
    'corrupt' => Txt.saveFileDamagedKept,
    'skipped' => Txt.someCircuitsCouldNot,
    _ => Txt.savingFailedStorageFull,
  };
}
