import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Why a platform channel instead of a bundled speech model:
///
/// The whole product promise is "your voice never leaves this phone". A bundled
/// whisper build would honour that, but every Flutter whisper plugin either
/// downloads its weights at runtime (network — the promise breaks) or needs an
/// NDK build we cannot verify here. Android since API 31 exposes the system's
/// *on-device* recognizer directly: `SpeechRecognizer.createOnDeviceSpeech-
/// Recognizer`, guaranteed by contract to run locally. No weights to ship, no
/// download, and the app still declares no INTERNET permission.
///
/// Consequence baked into the product (see PLAN.md §4): the system recognizer
/// only listens live, it cannot transcribe a saved file. So EchoJot dictates —
/// text appears while you speak — and never keeps an audio file. That is a
/// stronger privacy story, not a weaker one.
///
/// Honesty rule: if the system has no on-device recognizer (or no language
/// pack), we say so and stop. There is no cloud fallback path in this app.

/// What the platform can do right now. Everything is "unknown/unsupported" on
/// non-Android platforms and in tests — never a crash, never a silent cloud
/// fallback.
@immutable
class DictationCapabilities {
  const DictationCapabilities({
    required this.platformSupported,
    required this.onDeviceAvailable,
    this.installedLanguages = const <String>[],
    this.supportedLanguages = const <String>[],
    this.detail,
  });

  const DictationCapabilities.unsupported({this.detail})
      : platformSupported = false,
        onDeviceAvailable = false,
        installedLanguages = const <String>[],
        supportedLanguages = const <String>[];

  /// This build has a native implementation (Android today; iOS is v1.1).
  final bool platformSupported;

  /// The system offers on-device recognition — the only mode we ever use.
  final bool onDeviceAvailable;

  /// Language tags with an on-device pack already installed (Android 13+ can
  /// report this; older versions return an empty list = "unknown").
  final List<String> installedLanguages;

  /// Language tags the on-device recognizer could support once downloaded.
  final List<String> supportedLanguages;

  /// Diagnostic string for the settings screen (never shown as an error).
  final String? detail;

  bool get ready => platformSupported && onDeviceAvailable;

  DictationCapabilities copyWith({List<String>? installedLanguages}) =>
      DictationCapabilities(
        platformSupported: platformSupported,
        onDeviceAvailable: onDeviceAvailable,
        installedLanguages: installedLanguages ?? this.installedLanguages,
        supportedLanguages: supportedLanguages,
        detail: detail,
      );
}

/// One event from the native recognizer.
enum DictationEventType { status, partial, finalText, level, error }

@immutable
class DictationEvent {
  const DictationEvent(this.type, {this.text = '', this.level = 0, this.code});

  final DictationEventType type;

  /// Recognised text ([DictationEventType.partial] / [finalText]) or a status /
  /// error code name.
  final String text;

  /// Microphone loudness in dB as reported by the recognizer (roughly -2..10).
  final double level;

  /// Native error code, for mapping to a user-facing message.
  final DictationError? code;
}

/// Errors we translate into user-facing guidance. Anything we cannot classify
/// becomes [DictationError.unknown] — still shown, never swallowed.
enum DictationError {
  /// RECORD_AUDIO not granted.
  permission,

  /// No on-device recognizer / no language pack installed.
  onDeviceUnavailable,

  /// The recognizer service died or kept failing; the session was stopped.
  recognizerFailed,

  /// The engine kept returning "nothing recognised" — the session was ended
  /// instead of looping in silence.
  noSpeech,

  /// Native side missing (iOS build, unit test) — feature unavailable.
  unimplemented,

  unknown,
}

/// Client for the native on-device dictation bridge.
class DictationService {
  DictationService({
    MethodChannel? method,
    EventChannel? events,
  })  : _method = method ?? const MethodChannel(_methodChannelName),
        _events = events ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'echojot/dictation';
  static const _eventChannelName = 'echojot/dictation/events';

  final MethodChannel _method;
  final EventChannel _events;

  DictationCapabilities? _caps;

  /// Cached capabilities; call [refreshCapabilities] to re-probe (the user may
  /// have installed a language pack while the app was in the background).
  DictationCapabilities? get capabilities => _caps;

  Future<DictationCapabilities> refreshCapabilities() async {
    if (!_isAndroid) {
      return _caps = const DictationCapabilities.unsupported(
        detail: 'no native on-device recognizer on this platform',
      );
    }
    try {
      final raw = await _method.invokeMapMethod<String, Object?>('capabilities');
      if (raw == null) {
        return _caps = const DictationCapabilities.unsupported(
          detail: 'capabilities returned null',
        );
      }
      return _caps = DictationCapabilities(
        platformSupported: true,
        onDeviceAvailable: raw['onDevice'] == true,
        installedLanguages: _stringList(raw['installedLanguages']),
        supportedLanguages: _stringList(raw['supportedLanguages']),
        detail: raw['detail'] as String?,
      );
    } on MissingPluginException {
      return _caps = const DictationCapabilities.unsupported(
        detail: 'dictation channel not registered',
      );
    } catch (e) {
      debugPrint('dictation capabilities failed: $e');
      return _caps = DictationCapabilities.unsupported(detail: '$e');
    }
  }

  /// Start listening. [languageTag] defaults to the device locale; the native
  /// side only ever creates an on-device recognizer.
  ///
  /// Returns null on success, or the reason it could not start.
  Future<DictationError?> start({String? languageTag}) async {
    try {
      await _method.invokeMethod<void>('start', <String, Object?>{
        'language': languageTag ?? deviceLanguageTag,
      });
      return null;
    } on MissingPluginException {
      return DictationError.unimplemented;
    } on PlatformException catch (e) {
      return _errorFromCode(e.code);
    } catch (e) {
      debugPrint('dictation start failed: $e');
      return DictationError.unknown;
    }
  }

  /// Stop listening and let the recognizer finalise what it has.
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('dictation stop failed: $e');
    }
  }

  /// Native event stream. Errors on the channel are surfaced as
  /// [DictationEventType.error] events rather than stream errors, so the UI
  /// only ever has one thing to listen to.
  Stream<DictationEvent> events() {
    return _events.receiveBroadcastStream().map(_decode).handleError(
      (Object e) {
        debugPrint('dictation event stream error: $e');
      },
    ).where((e) => e != null).cast<DictationEvent>();
  }

  static DictationEvent? _decode(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    switch (type) {
      case 'partial':
        return DictationEvent(DictationEventType.partial,
            text: (raw['text'] as String?) ?? '');
      case 'final':
        return DictationEvent(DictationEventType.finalText,
            text: (raw['text'] as String?) ?? '');
      case 'level':
        return DictationEvent(DictationEventType.level,
            level: (raw['db'] as num?)?.toDouble() ?? 0);
      case 'status':
        return DictationEvent(DictationEventType.status,
            text: (raw['value'] as String?) ?? '');
      case 'error':
        return DictationEvent(
          DictationEventType.error,
          text: (raw['message'] as String?) ?? '',
          code: _errorFromCode(raw['code'] as String?),
        );
      default:
        return null;
    }
  }

  static DictationError _errorFromCode(String? code) => switch (code) {
        'permission' => DictationError.permission,
        'on_device_unavailable' => DictationError.onDeviceUnavailable,
        'recognizer_failed' => DictationError.recognizerFailed,
        'no_speech' => DictationError.noSpeech,
        _ => DictationError.unknown,
      };

  static List<String> _stringList(Object? raw) => raw is List
      ? raw.whereType<String>().toList(growable: false)
      : const <String>[];

  static bool get _isAndroid {
    // Platform throws in a pure-Dart test environment on some hosts; guard it.
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// e.g. "zh-CN", "en-US" — what the system recognizer expects.
  static String get deviceLanguageTag {
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode;
    return country == null || country.isEmpty
        ? locale.languageCode
        : '${locale.languageCode}-$country';
  }
}
