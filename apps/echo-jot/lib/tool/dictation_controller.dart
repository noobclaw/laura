import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/l10n.dart';
import 'dictation.dart';
import 'dictation_language.dart';
import 'transcript_text.dart';

enum DictationState { idle, starting, listening, finishing }

/// Drives one dictation session: permission → on-device recognizer → live text.
///
/// Every failure path ends in a user-visible [message]; nothing fails silently
/// and there is no online fallback (see dictation.dart for why).
class DictationController extends ChangeNotifier {
  DictationController({DictationService? service})
      : _service = service ?? DictationService();

  final DictationService _service;

  static const int _levelBars = 27;

  DictationState _state = DictationState.idle;
  String _committed = '';
  String _partial = '';
  String? _message;
  bool _permissionPermanentlyDenied = false;
  DateTime? _startedAt;
  StreamSubscription<DictationEvent>? _sub;
  Completer<void>? _finalWait;
  String _language = DictationLanguage.effectiveTag;

  final List<double> _levels = List<double>.filled(_levelBars, 0);

  DictationState get state => _state;
  bool get listening =>
      _state == DictationState.listening || _state == DictationState.starting;

  /// Text finalised so far in this session.
  String get committedText => _committed;

  /// Committed text plus the recognizer's live guess for the current utterance.
  String get previewText => previewTranscript(_committed, _partial);

  /// Rolling loudness history (0..1) for the level meter.
  List<double> get levels => List.unmodifiable(_levels);

  /// Last user-facing message (permission denied, no language pack, …).
  String? get message => _message;

  bool get permissionPermanentlyDenied => _permissionPermanentlyDenied;

  DictationCapabilities? get capabilities => _service.capabilities;

  String get language => _language;

  /// Picked in the language sheet; takes effect from the next session.
  void setLanguage(String tag) {
    _language = tag;
    notifyListeners();
  }

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  Future<DictationCapabilities> probe() async {
    // Subscribing here (not in start()) means the native EventSink is attached
    // long before the first `start` call — the method and event channels are
    // independent, so a late subscription could miss the opening events.
    _ensureSubscribed();
    final caps = await _service.refreshCapabilities(
        languageTag: DictationLanguage.effectiveTag);
    notifyListeners();
    return caps;
  }

  void _ensureSubscribed() {
    _sub ??= _service.events().listen(_onEvent);
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }

  /// Opens the system app-settings page so a permanently-denied microphone
  /// permission has a way out.
  Future<void> openSystemSettings() async {
    // A permanently denied microphone is fixed on the app's own permission
    // page; the voice-input page would send that user to the wrong place.
    if (_permissionPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    if (await _service.openSpeechSettings()) return;
    await openAppSettings();
  }

  /// True when the last failure is something the user fixes in system
  /// settings (permission, dictation switched off, missing language pack),
  /// so the UI can offer a "Settings" shortcut next to the message.
  bool get lastErrorNeedsSettings => _needsSettings;
  bool _needsSettings = false;

  /// Returns true when the session actually started listening.
  Future<bool> start({String? languageTag}) async {
    if (_state != DictationState.idle) return false;
    _message = null;
    _state = DictationState.starting;
    notifyListeners();

    final wanted = languageTag ?? DictationLanguage.effectiveTag;
    final cached = _service.capabilities;
    final caps = (cached != null && _service.capabilitiesLanguage == wanted)
        ? cached
        : await _service.refreshCapabilities(languageTag: wanted);
    if (!caps.ready) {
      _fail(caps.platformSupported
          ? _msgNoOnDevice
          : tr(
              zh: '这台设备不支持设备端语音识别,本版本暂无法听写。',
              en: 'This device has no on-device speech recognition, so dictation '
                  'is unavailable in this build.',
            ));
      return false;
    }

    if (!await _ensureMicPermission()) return false;

    _language = languageTag ?? DictationLanguage.effectiveTag;
    _committed = '';
    _partial = '';
    _levels.fillRange(0, _levels.length, 0);
    _ensureSubscribed();

    final err = await _service.start(languageTag: _language);
    if (err != null) {
      _fail(_withDetail(_messageFor(err), _service.lastStartDetail));
      return false;
    }
    if (_state != DictationState.starting) {
      // stop() (or a lifecycle change) landed while we were still starting up —
      // don't leave the native recognizer listening behind an idle UI.
      await _service.stop();
      _state = DictationState.idle;
      _startedAt = null;
      notifyListeners();
      return false;
    }
    _startedAt = DateTime.now();
    _state = DictationState.listening;
    notifyListeners();
    return true;
  }

  /// Stops listening and returns the finished note text (may be empty if the
  /// user said nothing).
  Future<String> stop() async {
    // Idle here usually means the native side failed mid-session: keep the
    // last partial too, it is real speech the user never saw committed.
    if (_state == DictationState.idle) {
      return finalizeTranscript(previewTranscript(_committed, _partial));
    }
    _state = DictationState.finishing;
    notifyListeners();

    // The recognizer delivers one last result after stopListening; give it a
    // moment, but never hang the UI on it.
    _finalWait = Completer<void>();
    await _service.stop();
    await _finalWait!.future
        .timeout(const Duration(milliseconds: 1200), onTimeout: () {});
    _finalWait = null;

    final text = finalizeTranscript(previewTranscript(_committed, _partial));
    _partial = '';
    _committed = text;
    _state = DictationState.idle;
    _startedAt = null;
    _levels.fillRange(0, _levels.length, 0);
    notifyListeners();
    return text;
  }

  /// Called when the app leaves the foreground: the recognizer cannot be
  /// trusted in the background, so finish honestly instead of pretending.
  Future<String?> stopForBackground() async {
    if (_state == DictationState.idle) return null;
    final text = await stop();
    _message = tr(
      zh: '应用切到后台,听写已结束并保存。',
      en: 'App left the foreground — dictation ended and was saved.',
    );
    notifyListeners();
    return text;
  }

  void _onEvent(DictationEvent e) {
    switch (e.type) {
      case DictationEventType.partial:
        _partial = e.text;
        notifyListeners();
      case DictationEventType.finalText:
        if (e.text.trim().isNotEmpty) {
          _committed = appendSegment(_committed, e.text);
        }
        _partial = '';
        if (_finalWait != null && !_finalWait!.isCompleted) {
          _finalWait!.complete();
        }
        notifyListeners();
      case DictationEventType.level:
        _pushLevel(e.level);
      case DictationEventType.status:
        // Deliberately NOT completing `_finalWait` on 'stopped': the native side
        // emits it as soon as stopListening() is called, while the last (and
        // best) utterance result arrives afterwards via `final`. Waiting for the
        // real result — or the timeout — is what keeps the last sentence.
        break;
      case DictationEventType.error:
        if (_finalWait != null && !_finalWait!.isCompleted) {
          _finalWait!.complete();
        }
        _needsSettings = e.code == DictationError.permission ||
            e.code == DictationError.onDeviceUnavailable ||
            e.code == DictationError.siriDisabled;
        _message = _withDetail(
            _messageFor(e.code ?? DictationError.unknown), e.text);
        // The native side has already torn the session down, so end ours too —
        // leaving the UI in "listening" would be a silent failure. `_startedAt`
        // is kept so the caller can still record how long the session ran and
        // save whatever was already transcribed.
        _state = DictationState.idle;
        notifyListeners();
    }
  }

  void _pushLevel(double db) {
    // The recognizer reports roughly -2 dB (silence) .. 10 dB (loud speech).
    final norm = ((db + 2) / 12).clamp(0.0, 1.0);
    _levels.removeAt(0);
    _levels.add(norm);
    notifyListeners();
  }

  Future<bool> _ensureMicPermission() async {
    PermissionStatus status;
    try {
      status = await Permission.microphone.status;
      if (!status.isGranted) status = await Permission.microphone.request();
      // iOS asks separately for speech recognition, on-device included.
      if (status.isGranted && DictationService.needsSpeechPermission) {
        var speech = await Permission.speech.status;
        if (!speech.isGranted) speech = await Permission.speech.request();
        if (!speech.isGranted && !speech.isLimited) status = speech;
      }
    } catch (e) {
      debugPrint('microphone permission check failed: $e');
      _fail(tr(
        zh: '无法检查麦克风权限,请在系统设置中确认。',
        en: 'Could not check the microphone permission — please check system '
            'settings.',
      ));
      return false;
    }
    if (status.isGranted || status.isLimited) {
      _permissionPermanentlyDenied = false;
      return true;
    }
    _permissionPermanentlyDenied = status.isPermanentlyDenied ||
        status.isRestricted ||
        // iOS never re-prompts after one refusal: Settings is the only way.
        DictationService.needsSpeechPermission;
    _fail(_permissionPermanentlyDenied
        ? tr(
            zh: '需要「麦克风」和「语音识别」两项权限才能听写,请到系统设置里为 EchoJot 开启。',
            en: 'Dictation needs both Microphone and Speech Recognition — '
                'enable them for EchoJot in Settings.',
          )
        : tr(
            zh: '需要麦克风权限才能听写。',
            en: 'Dictation needs the microphone permission.',
          ));
    return false;
  }

  void _fail(String message) {
    _needsSettings = message == _msgNoOnDevice ||
        message.contains('设置') ||
        message.contains('Settings');
    _message = message;
    _state = DictationState.idle;
    _startedAt = null;
    notifyListeners();
  }

  /// The native error text under the friendly message. Small, but it is the
  /// difference between "it says interrupted" and a fixable bug report.
  static String _withDetail(String message, String? detail) {
    final d = detail?.trim();
    if (d == null || d.isEmpty) return message;
    return '$message\n($d)';
  }

  static String get _msgNoOnDevice => noOnDeviceHelp;

  /// Where on-device recognition comes from differs by platform, and so does
  /// what the user can do about it. Android downloads language packs; iOS
  /// ships a fixed set of offline languages and the fix is to dictate in one
  /// of them. Sending an iPhone user to an Android settings path is worse
  /// than saying nothing.
  static String get noOnDeviceHelp => DictationService.needsSpeechPermission
      ? tr(
          zh: 'iPhone 上的离线识别还没就绪。请打开「设置 → 通用 → 键盘 → 启用听写」,'
              '并确认当前语言支持离线听写(简体中文、English、日本語、한국어 等;'
              '首次启用会下载一次语言资源)。为了保证声音不出手机,本应用不会改用联网识别。',
          en: 'Offline recognition is not ready on this iPhone. Turn on '
              'Settings → General → Keyboard → Enable Dictation and make sure '
              'the current language supports offline dictation (Chinese, '
              'English, Japanese, Korean, German, French, Spanish…; the first '
              'enable downloads the language once). This app will not switch '
              'to online recognition, so your voice stays on the phone.',
        )
      : tr(
          zh: '系统还没有可用的设备端语音识别语言包。请到「系统设置 → 系统 → 语言与输入法 → '
              '设备端语音识别」下载一个语言包后再回来——为了保证声音不出手机,'
              '本应用不会改用联网识别。',
          en: 'The system has no on-device speech language pack yet. Add one in '
              'Settings → System → Languages & input → On-device speech '
              'recognition, then come back — this app will not switch to online '
              'recognition, so your voice stays on the phone.',
        );

  static String _messageFor(DictationError e) => switch (e) {
        DictationError.permission => tr(
            zh: '需要麦克风权限才能听写。',
            en: 'Dictation needs the microphone permission.',
          ),
        DictationError.onDeviceUnavailable => _msgNoOnDevice,
        DictationError.siriDisabled => tr(
            zh: 'iPhone 的 Siri 是关着的,iOS 的离线听写引擎依赖它。请打开'
                '「设置 → Apple 智能与 Siri → Siri」后再试;听写内容仍只在本机处理。',
            en: 'Siri is switched off on this iPhone, and iOS runs its offline '
                'dictation engine through it. Turn on Settings → Apple '
                'Intelligence & Siri → Siri and try again; your speech is still '
                'processed on the phone only.',
          ),
        DictationError.recognizerFailed => tr(
            zh: '系统语音识别中断了,请重试。',
            en: 'The system recognizer stopped — please try again.',
          ),
        DictationError.noSpeech => tr(
            zh: '一直没听到语音,已结束听写。请确认麦克风没被其它应用占用、'
                '或换个安静一点的环境再试。',
            en: 'No speech was recognised, so dictation ended. Check that no other '
                'app is holding the microphone, then try again.',
          ),
        DictationError.unimplemented => tr(
            zh: '这个版本没装上听写模块(设备端识别桥接缺失),请重新安装应用。',
            en: 'This build is missing the dictation module (the on-device '
                'recognizer bridge is not registered) — please reinstall.',
          ),
        DictationError.unknown => tr(
            zh: '听写失败,请重试。',
            en: 'Dictation failed — please try again.',
          ),
      };

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
