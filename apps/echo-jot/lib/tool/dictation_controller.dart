import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/l10n.dart';
import 'dictation.dart';
import 'dictation_engine.dart';
import 'dictation_language.dart';
import 'transcript_text.dart';
import 'whisper_engine.dart';
import 'whisper_recorder.dart';

/// [transcribing] exists only for the Whisper engine: the recording has
/// stopped and whisper.cpp is turning it into text (progress in
/// [DictationController.progress]). The system engine never enters it.
enum DictationState { idle, starting, listening, finishing, transcribing }

/// Drives one dictation session: permission → engine → text.
///
/// Two engines share this state machine (see dictation_engine.dart):
///  - system: on-device recognizer, live partial/final events, no audio;
///  - whisper: `record` writes a 16 kHz WAV, whisper.cpp transcribes it after
///    stop, the WAV is deleted. The engine is fixed per session at [start].
///
/// Every failure path ends in a user-visible [message]; nothing fails silently
/// and there is no online fallback (see dictation.dart for why).
class DictationController extends ChangeNotifier {
  DictationController({
    DictationService? service,
    WhisperEngine? whisper,
    WhisperRecorder? recorder,
  })  : _service = service ?? DictationService(),
        _whisperOverride = whisper,
        _recorderOverride = recorder;

  final DictationService _service;
  final WhisperEngine? _whisperOverride;
  final WhisperRecorder? _recorderOverride;

  // Both are created on first use: the recorder touches the platform
  // channel in its constructor, which must not happen in tests or for a
  // user who never picks the Whisper engine.
  WhisperEngine? _whisper;
  WhisperRecorder? _recorder;
  WhisperEngine get _whisperEngine =>
      _whisper ??= _whisperOverride ?? WhisperEngine();
  WhisperRecorder get _whisperRecorder =>
      _recorder ??= _recorderOverride ?? WhisperRecorder();

  static const int _levelBars = 27;

  DictationState _state = DictationState.idle;
  DictationEngine _activeEngine = DictationEnginePref.current.value;
  String _committed = '';
  String _partial = '';
  String? _message;
  bool _permissionPermanentlyDenied = false;
  DateTime? _startedAt;
  StreamSubscription<DictationEvent>? _sub;
  Completer<void>? _finalWait;
  String _language = DictationLanguage.effectiveTag;

  // Whisper session state.
  String? _wavPath;
  double _progress = 0;
  int _chunk = 0;
  int _chunkCount = 0;
  bool _cancelRequested = false;
  Completer<String>? _transcribeDone;

  final List<double> _levels = List<double>.filled(_levelBars, 0);

  DictationState get state => _state;
  bool get listening =>
      _state == DictationState.listening || _state == DictationState.starting;
  bool get transcribing => _state == DictationState.transcribing;

  /// Anything but idle — the mic hero is occupied.
  bool get busy => _state != DictationState.idle;

  /// Engine of the running session, or the one the next session will use.
  DictationEngine get engine =>
      busy ? _activeEngine : DictationEnginePref.current.value;

  /// Whisper transcription progress, 0..1, with the chunk being worked on.
  double get progress => _progress;
  int get chunk => _chunk;
  int get chunkCount => _chunkCount;
  bool get cancelRequested => _cancelRequested;

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
    _activeEngine = DictationEnginePref.current.value;
    _message = null;
    _state = DictationState.starting;
    notifyListeners();

    if (_activeEngine == DictationEngine.whisper) {
      return _startWhisper(languageTag);
    }

    final wanted = languageTag ?? DictationLanguage.effectiveTag;
    final cached = _service.capabilities;
    final caps = (cached != null && _service.capabilitiesLanguage == wanted)
        ? cached
        : await _service.refreshCapabilities(languageTag: wanted);
    if (!caps.ready) {
      _fail(caps.platformSupported
          ? _msgNoOnDevice
          : tr(
              zh: '这台设备不支持设备端语音识别;可在设置里改用「Whisper 离线」引擎。',
              en: 'This device has no on-device speech recognition — switch to '
                  'the Whisper offline engine in Settings.',
            ));
      return false;
    }

    if (!await _ensureMicPermission(speech: true)) return false;

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

  Future<bool> _startWhisper(String? languageTag) async {
    // Whisper needs the microphone only — no speech-recognition grant, that
    // one belongs to the system engine.
    if (!await _ensureMicPermission(speech: false)) return false;

    _language = languageTag ?? DictationLanguage.effectiveTag;
    _committed = '';
    _partial = '';
    _levels.fillRange(0, _levels.length, 0);
    _cancelRequested = false;
    _progress = 0;
    _chunk = 0;
    _chunkCount = 0;

    final String path;
    try {
      final tmp = await getTemporaryDirectory();
      path = '${tmp.path}/echojot_rec_${DateTime.now().microsecondsSinceEpoch}.wav';
      await _whisperRecorder.start(path, onLevel: _pushLevelDbfs);
    } catch (e) {
      debugPrint('whisper recorder start failed: $e');
      _fail(_withDetail(
        tr(
          zh: '麦克风没能启动,请确认没被其它应用占用后重试。',
          en: 'The microphone could not be started — check that no other app '
              'is using it, then try again.',
        ),
        '$e',
      ));
      return false;
    }
    if (_state != DictationState.starting) {
      await _whisperRecorder.cancel();
      _state = DictationState.idle;
      _startedAt = null;
      notifyListeners();
      return false;
    }
    _wavPath = path;
    _startedAt = DateTime.now();
    _state = DictationState.listening;
    notifyListeners();
    // Copy the model out of the bundle while the user is still talking so
    // the first transcription does not pay for it. Failures surface at stop.
    unawaited(_whisperEngine.ensureModel().then((_) {}, onError: (Object e) {
      debugPrint('whisper model prewarm failed: $e');
    }));
    return true;
  }

  /// Stops listening and returns the finished note text (may be empty if the
  /// user said nothing). For the Whisper engine this includes the
  /// transcription, so it can take a while — watch [state] / [progress].
  Future<String> stop() async {
    if (_activeEngine == DictationEngine.whisper &&
        _state != DictationState.idle) {
      return _stopWhisper();
    }
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

  Future<String> _stopWhisper() async {
    // A second stop while transcribing simply waits for the first.
    if (_state == DictationState.transcribing && _transcribeDone != null) {
      return _transcribeDone!.future;
    }
    _state = DictationState.finishing;
    notifyListeners();

    if (_wavPath == null) {
      // Stopped while start() was still setting the recorder up (the app
      // went to the background mid-start): nothing was recorded, so there
      // is nothing to transcribe and no error to show.
      await _whisperRecorder.cancel();
      _state = DictationState.idle;
      _startedAt = null;
      _levels.fillRange(0, _levels.length, 0);
      notifyListeners();
      return '';
    }
    final path = await _whisperRecorder.stop() ?? _wavPath;
    _levels.fillRange(0, _levels.length, 0);
    final done = _transcribeDone = Completer<String>();
    _state = DictationState.transcribing;
    _progress = 0;
    _chunk = 0;
    _chunkCount = 0;
    notifyListeners();

    var text = '';
    try {
      if (path == null) {
        throw WhisperEngineException(WhisperFailure.audioUnreadable,
            detail: 'recorder returned no file');
      }
      final result = await _whisperEngine.transcribeWav(
        path,
        languageTag: _language,
        onProgress: (p, c, n) {
          _progress = p;
          _chunk = c;
          _chunkCount = n;
          notifyListeners();
        },
        isCancelled: () => _cancelRequested,
      );
      text = result.text;
      if (!result.completed) {
        _message = tr(
          zh: '已提前结束转写,保留了已转好的部分。',
          en: 'Transcription was ended early; the part already transcribed '
              'was kept.',
        );
      }
    } on WhisperEngineException catch (e) {
      text = e.partialText;
      _needsSettings = false;
      _message = _withDetail(_messageForWhisper(e.kind), e.detail);
    } catch (e) {
      debugPrint('whisper transcription failed: $e');
      _needsSettings = false;
      _message = _withDetail(
          tr(zh: 'Whisper 转写失败,请重试。', en: 'Whisper transcription failed — please try again.'),
          '$e');
    } finally {
      // The recording is a temp file for the engine only — never kept.
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      _wavPath = null;
      _state = DictationState.idle;
      _startedAt = null;
      _progress = 0;
      _transcribeDone = null;
      notifyListeners();
    }
    final out = finalizeTranscript(text);
    _committed = out;
    done.complete(out);
    return out;
  }

  /// Asks the Whisper transcription to stop after the chunk in progress;
  /// what is already transcribed is kept. No-op for the system engine.
  void cancelTranscription() {
    if (_state != DictationState.transcribing || _cancelRequested) return;
    _cancelRequested = true;
    notifyListeners();
  }

  /// Called when the app leaves the foreground: the recognizer cannot be
  /// trusted in the background, so finish honestly instead of pretending.
  /// A Whisper transcription already running is left to finish — it needs no
  /// microphone and the note is saved when it completes.
  Future<String?> stopForBackground() async {
    if (_state == DictationState.idle ||
        _state == DictationState.transcribing) {
      return null;
    }
    final text = await stop();
    _message = tr(
      zh: '应用切到后台,听写已结束并保存。',
      en: 'App left the foreground — dictation ended and was saved.',
    );
    notifyListeners();
    return text;
  }

  /// Frees the Whisper model parked in native memory when the app is idle in
  /// the background (it stays loaded between sessions for speed otherwise).
  Future<void> releaseWhisperIfIdle() async {
    if (_state != DictationState.idle) return;
    await _whisper?.release();
  }

  void _onEvent(DictationEvent e) {
    // The native recognizer only emits during a system session; anything
    // arriving while Whisper owns the microphone is stale and must not
    // touch this session's state.
    if (_activeEngine == DictationEngine.whisper && busy) return;
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
    _pushNorm(((db + 2) / 12).clamp(0.0, 1.0));
  }

  void _pushLevelDbfs(double dbfs) {
    // `record` reports peak dBFS: about -50 in a quiet room, -10 for speech
    // close to the phone, 0 = clipping.
    final v = dbfs.isFinite ? dbfs : -60.0;
    _pushNorm(((v + 50) / 45).clamp(0.0, 1.0));
  }

  void _pushNorm(double norm) {
    _levels.removeAt(0);
    _levels.add(norm);
    notifyListeners();
  }

  Future<bool> _ensureMicPermission({required bool speech}) async {
    PermissionStatus status;
    try {
      status = await Permission.microphone.status;
      if (!status.isGranted) status = await Permission.microphone.request();
      // iOS asks separately for speech recognition, on-device included —
      // only the system engine uses that API.
      if (status.isGranted && speech && DictationService.needsSpeechPermission) {
        var speechStatus = await Permission.speech.status;
        if (!speechStatus.isGranted) {
          speechStatus = await Permission.speech.request();
        }
        if (!speechStatus.isGranted && !speechStatus.isLimited) {
          status = speechStatus;
        }
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
    final both = speech && DictationService.needsSpeechPermission;
    _fail(_permissionPermanentlyDenied
        ? (both
            ? tr(
                zh: '需要「麦克风」和「语音识别」两项权限才能听写,请到系统设置里为 EchoJot 开启。',
                en: 'Dictation needs both Microphone and Speech Recognition — '
                    'enable them for EchoJot in Settings.',
              )
            : tr(
                zh: '需要麦克风权限才能听写,请到系统设置里为 EchoJot 开启。',
                en: 'Dictation needs the microphone — enable it for EchoJot '
                    'in Settings.',
              ))
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
  /// than saying nothing. Either way the Whisper engine is the way out that
  /// needs no system change at all.
  static String get noOnDeviceHelp => DictationService.needsSpeechPermission
      ? tr(
          zh: 'iPhone 上的系统离线识别还没就绪。请打开「设置 → 通用 → 键盘 → 启用听写」,'
              '并确认当前语言支持离线听写(简体中文、English、日本語、한국어 等;'
              '首次启用会下载一次语言资源)。或者改用「Whisper 离线」引擎——它随应用自带模型,'
              '不依赖这些系统设置。为了保证声音不出手机,本应用不会改用联网识别。',
          en: 'The system\'s offline recognition is not ready on this iPhone. '
              'Turn on Settings → General → Keyboard → Enable Dictation and make '
              'sure the current language supports offline dictation (Chinese, '
              'English, Japanese, Korean, German, French, Spanish…; the first '
              'enable downloads the language once). Or switch to the Whisper '
              'offline engine — it ships its own model and needs none of those '
              'settings. This app will not switch to online recognition, so your '
              'voice stays on the phone.',
        )
      : tr(
          zh: '系统还没有可用的设备端语音识别语言包。请到「系统设置 → 系统 → 语言与输入法 → '
              '设备端语音识别」下载一个语言包后再回来;或者改用「Whisper 离线」引擎——'
              '它随应用自带模型,不需要系统语言包。为了保证声音不出手机,本应用不会改用联网识别。',
          en: 'The system has no on-device speech language pack yet. Add one in '
              'Settings → System → Languages & input → On-device speech '
              'recognition, then come back — or switch to the Whisper offline '
              'engine, which ships its own model and needs no language pack. '
              'This app will not switch to online recognition, so your voice '
              'stays on the phone.',
        );

  static String _messageFor(DictationError e) => switch (e) {
        DictationError.permission => tr(
            zh: '需要麦克风权限才能听写。',
            en: 'Dictation needs the microphone permission.',
          ),
        DictationError.onDeviceUnavailable => _msgNoOnDevice,
        DictationError.siriDisabled => tr(
            zh: 'iPhone 的 Siri 是关着的,iOS 的离线听写引擎依赖它。请打开'
                '「设置 → Apple 智能与 Siri → Siri」后再试,或在设置里改用「Whisper 离线」引擎;'
                '听写内容仍只在本机处理。',
            en: 'Siri is switched off on this iPhone, and iOS runs its offline '
                'dictation engine through it. Turn on Settings → Apple '
                'Intelligence & Siri → Siri and try again, or switch to the '
                'Whisper offline engine in Settings; your speech is still '
                'processed on the phone only.',
          ),
        DictationError.recognizerFailed => tr(
            zh: '系统语音识别中断了,请重试;反复出现可在设置里改用「Whisper 离线」引擎。',
            en: 'The system recognizer stopped — please try again. If it keeps '
                'happening, switch to the Whisper offline engine in Settings.',
          ),
        DictationError.noSpeech => tr(
            zh: '一直没听到语音,已结束听写。请确认麦克风没被其它应用占用、'
                '或换个安静一点的环境再试。',
            en: 'No speech was recognised, so dictation ended. Check that no other '
                'app is holding the microphone, then try again.',
          ),
        DictationError.unimplemented => tr(
            zh: '这个版本没装上系统听写模块(设备端识别桥接缺失),请重新安装应用,'
                '或在设置里改用「Whisper 离线」引擎。',
            en: 'This build is missing the system dictation module (the on-device '
                'recognizer bridge is not registered) — reinstall, or switch to '
                'the Whisper offline engine in Settings.',
          ),
        DictationError.unknown => tr(
            zh: '听写失败,请重试。',
            en: 'Dictation failed — please try again.',
          ),
      };

  static String _messageForWhisper(WhisperFailure f) => switch (f) {
        WhisperFailure.modelUnavailable => tr(
            zh: 'Whisper 模型没能加载(应用包可能不完整)。请重新安装应用;'
                '在此之前可在设置里改用「系统识别」引擎。',
            en: 'The Whisper model could not be loaded (the app package may be '
                'incomplete). Please reinstall; until then, switch to the '
                'System recognizer engine in Settings.',
          ),
        WhisperFailure.audioTooShort => tr(
            zh: '录音太短(不到 1 秒),这条没有保存。',
            en: 'The recording was too short (under 1 second) — no note saved.',
          ),
        WhisperFailure.audioUnreadable => tr(
            zh: '录音文件读不出来,这条没有保存。请确认手机有剩余空间后重试。',
            en: 'The recording could not be read — no note saved. Check free '
                'space on the phone and try again.',
          ),
        WhisperFailure.transcriptionFailed => tr(
            zh: 'Whisper 转写失败,请重试。',
            en: 'Whisper transcription failed — please try again.',
          ),
      };

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    unawaited(_recorder?.dispose());
    super.dispose();
  }
}
