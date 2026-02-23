import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:llamadart_chat_example/models/chat_settings.dart';
import 'package:llamadart_chat_example/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsService context size', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('preserves explicit auto context size from storage', () async {
      SharedPreferences.setMockInitialValues({'context_size': 0});

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.contextSize, 0);
    });

    test('defaults tool calling to disabled', () async {
      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.toolsEnabled, isFalse);
    });

    test('defaults preferred backend to auto', () async {
      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.preferredBackend, GpuBackend.auto);
    });

    test('falls back to auto for invalid backend index', () async {
      SharedPreferences.setMockInitialValues({'preferred_backend': 999});

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.preferredBackend, GpuBackend.auto);
    });

    test('falls back to defaults for invalid log level indices', () async {
      SharedPreferences.setMockInitialValues({
        'log_level': 999,
        'native_log_level': -1,
      });

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.logLevel, LlamaLogLevel.none);
      expect(settings.nativeLogLevel, LlamaLogLevel.warn);
    });

    test('normalizes invalid legacy context size values', () async {
      SharedPreferences.setMockInitialValues({'context_size': 128});

      final service = SettingsService();
      final settings = await service.loadSettings();

      expect(settings.contextSize, 4096);
    });

    test('saves zero context size for auto mode', () async {
      final service = SettingsService();
      const settings = ChatSettings(contextSize: 0);

      await service.saveSettings(settings);
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getInt('context_size'), 0);
    });
  });
}
