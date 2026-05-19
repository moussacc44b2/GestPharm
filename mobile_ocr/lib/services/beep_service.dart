import 'package:flutter/services.dart';

class BeepService {
  static const _channel = MethodChannel('com.example.mobile_ocr/beep');

  /// Play a high-performance system beep sound natively.
  static Future<void> play() async {
    try {
      await _channel.invokeMethod('playSuccess');
    } on PlatformException catch (e) {
      print('Failed to play beep: ${e.message}');
    }
  }

  /// Play a highly prominent, positive confirmation scan sound.
  static Future<void> playSuccess() async {
    try {
      await _channel.invokeMethod('playSuccess');
    } on PlatformException catch (e) {
      print('Failed to play success beep: ${e.message}');
    }
  }

  /// Play a prominent, distinct warning beep for failures (out of stock, not found).
  static Future<void> playError() async {
    try {
      await _channel.invokeMethod('playError');
    } on PlatformException catch (e) {
      print('Failed to play error beep: ${e.message}');
    }
  }
}
