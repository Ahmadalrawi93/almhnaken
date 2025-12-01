// File: sound_service.dart
// خدمة الصوت للتنبيهات في اللعبة
import 'package:flutter/services.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  bool _isSoundEnabled = true;

  // تفعيل/إلغاء تفعيل الصوت
  void setSoundEnabled(bool enabled) {
    _isSoundEnabled = enabled;
  }

  bool get isSoundEnabled => _isSoundEnabled;

  // تشغيل صوت تنبيه بداية الدور - صوت أكثر وضوحاً
  Future<void> playTurnNotification() async {
    if (!_isSoundEnabled) return;

    try {
      // استخدام صوت alert بدلاً من click ليكون أكثر وضوحاً
      await SystemSound.play(SystemSoundType.alert);

      // إضافة تأخير قصير ثم تشغيل صوت إضافي للتأكيد
      await Future.delayed(const Duration(milliseconds: 200));
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      print('خطأ في تشغيل صوت تنبيه الدور: $e');
    }
  }

  // تشغيل صوت تنبيه انتهاء الدور - صوت مميز
  Future<void> playTurnEndNotification() async {
    if (!_isSoundEnabled) return;

    try {
      // تشغيل صوتين متتاليين لتنبيه انتهاء الدور
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 150));
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      print('خطأ في تشغيل صوت انتهاء الدور: $e');
    }
  }

  // تشغيل صوت نجاح
  Future<void> playSuccessSound() async {
    if (!_isSoundEnabled) return;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      print('خطأ في تشغيل صوت النجاح: $e');
    }
  }

  // تشغيل صوت خطأ
  Future<void> playErrorSound() async {
    if (!_isSoundEnabled) return;

    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      print('خطأ في تشغيل صوت الخطأ: $e');
    }
  }

  // تشغيل صوت انتقال بين المراحل
  Future<void> playTransitionSound() async {
    if (!_isSoundEnabled) return;

    try {
      // تشغيل صوت انتقال مميز
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 100));
      await SystemSound.play(SystemSoundType.alert);
      await Future.delayed(const Duration(milliseconds: 100));
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      print('خطأ في تشغيل صوت الانتقال: $e');
    }
  }
}
