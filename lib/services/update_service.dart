import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.forceUpdate,
    this.message,
    this.storeUrl,
    required this.packageName,
  });

  final String latestVersion;
  final String currentVersion;
  final bool forceUpdate;
  final String? message;
  final String? storeUrl;
  final String packageName;

  String get effectiveStoreUrl {
    if (storeUrl != null && storeUrl!.isNotEmpty) {
      return storeUrl!;
    }
    return 'https://play.google.com/store/apps/details?id=$packageName';
  }
}

class UpdateService {
  UpdateService._internal();

  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() => _instance;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _configCollection = 'app_config';
  static const String _configDoc = 'version';
  static const String _latestVersionField = 'latestVersion';
  static const String _forceUpdateField = 'forceUpdate';
  static const String _messageField = 'updateMessage';
  static const String _storeUrlField = 'storeUrl';
  static const String _lastNotifiedKey = 'last_notified_version';

  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;

      final DocumentSnapshot<Map<String, dynamic>> configSnapshot =
          await _firestore.collection(_configCollection).doc(_configDoc).get();

      if (!configSnapshot.exists) {
        debugPrint('🔍 ملف إعدادات التحديث غير موجود في Firestore');
        return null;
      }

      final Map<String, dynamic>? data = configSnapshot.data();
      if (data == null) {
        return null;
      }

      final String? latestVersion = data[_latestVersionField] as String?;
      if (latestVersion == null || latestVersion.isEmpty) {
        return null;
      }

      final bool forceUpdate = data[_forceUpdateField] as bool? ?? false;
      final String? message = data[_messageField] as String?;
      final String? storeUrl = data[_storeUrlField] as String?;

      if (!_isNewerVersion(latestVersion, currentVersion)) {
        return null;
      }

      if (!forceUpdate) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? lastNotified = prefs.getString(_lastNotifiedKey);
        if (lastNotified == latestVersion) {
          return null;
        }
      }

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        forceUpdate: forceUpdate,
        message: message,
        storeUrl: storeUrl,
        packageName: packageInfo.packageName,
      );
    } catch (e) {
      debugPrint('❌ خطأ أثناء التحقق من التحديث: $e');
      return null;
    }
  }

  Future<void> markVersionAsNotified(String version) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastNotifiedKey, version);
  }

  bool _isNewerVersion(String latest, String current) {
    final List<int> latestParts = latest
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    final List<int> currentParts = current
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final int maxLength = latestParts.length > currentParts.length
        ? latestParts.length
        : currentParts.length;

    for (int i = 0; i < maxLength; i++) {
      final int latestValue = i < latestParts.length ? latestParts[i] : 0;
      final int currentValue = i < currentParts.length ? currentParts[i] : 0;

      if (latestValue > currentValue) {
        return true;
      } else if (latestValue < currentValue) {
        return false;
      }
    }

    return false;
  }
}
