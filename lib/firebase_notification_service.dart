// File: firebase_notification_service.dart
// خدمة Firebase Cloud Messaging للإشعارات الخلفية
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseNotificationService {
  static final FirebaseNotificationService _instance =
      FirebaseNotificationService._internal();
  factory FirebaseNotificationService() => _instance;
  FirebaseNotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // تهيئة خدمة Firebase Cloud Messaging
  Future<void> initialize() async {
    try {
      // طلب إذن الإشعارات
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );

      print('🔔 إذن الإشعارات: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // الحصول على FCM token
        String? token = await _firebaseMessaging.getToken();
        if (token != null) {
          print('📱 FCM Token: $token');
          await _saveFCMToken(token);
          await saveFCMTokenToDatabase(token);
        }

        // إعداد مراقبة تحديث FCM token
        _setupTokenRefresh();

        // إعداد معالجات الإشعارات
        _setupMessageHandlers();
      }
    } catch (e) {
      print('❌ خطأ في تهيئة Firebase Cloud Messaging: $e');
    }
  }

  // حفظ FCM token في SharedPreferences
  Future<void> _saveFCMToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      print('✅ تم حفظ FCM Token محلياً');
    } catch (e) {
      print('❌ خطأ في حفظ FCM Token محلياً: $e');
    }
  }

  // حفظ FCM token في قاعدة البيانات Firestore
  Future<void> saveFCMTokenToDatabase(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmToken': token,
              'lastTokenUpdate': FieldValue.serverTimestamp(),
              'deviceInfo': {
                'platform': 'android',
                'lastActive': FieldValue.serverTimestamp(),
              },
            });
        print('✅ تم حفظ FCM Token في قاعدة البيانات للمستخدم: ${user.uid}');
      } else {
        print('⚠️ لا يوجد مستخدم مسجل دخول');
      }
    } catch (e) {
      print('❌ خطأ في حفظ FCM Token في قاعدة البيانات: $e');
    }
  }

  // الحصول على FCM token المحفوظ
  Future<String?> getFCMToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('fcm_token');
    } catch (e) {
      print('❌ خطأ في الحصول على FCM Token: $e');
      return null;
    }
  }

  // إعداد مراقبة تحديث FCM token
  void _setupTokenRefresh() {
    _firebaseMessaging.onTokenRefresh.listen((newToken) async {
      print('🔄 تم تحديث FCM Token: $newToken');
      await _saveFCMToken(newToken);
      await saveFCMTokenToDatabase(newToken);
    });
  }

  // إعداد معالجات الرسائل
  void _setupMessageHandlers() {
    // معالج الرسائل في الخلفية (عندما يكون التطبيق مغلق)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // معالج الرسائل في المقدمة (عندما يكون التطبيق مفتوح)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 رسالة في المقدمة: ${message.notification?.title}');
      _handleForegroundMessage(message);
    });

    // معالج النقر على الإشعار
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('👆 تم النقر على الإشعار: ${message.notification?.title}');
      _handleNotificationTap(message);
    });

    // معالج الرسائل عند فتح التطبيق من إشعار
    _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('🚀 تم فتح التطبيق من إشعار: ${message.notification?.title}');
        _handleNotificationTap(message);
      }
    });
  }

  // معالج الرسائل في الخلفية
  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message,
  ) async {
    print('📱 رسالة في الخلفية: ${message.notification?.title}');
    // هنا يمكن إضافة معالجة إضافية للرسائل في الخلفية
  }

  // معالج الرسائل في المقدمة
  void _handleForegroundMessage(RemoteMessage message) {
    // يمكن إضافة معالجة خاصة للرسائل في المقدمة
    print('📱 تم استلام رسالة في المقدمة: ${message.notification?.body}');
  }

  // معالج النقر على الإشعار
  void _handleNotificationTap(RemoteMessage message) {
    final String? payload = message.data['payload'];
    print('🎯 معالجة النقر على الإشعار مع payload: $payload');

    // هنا يمكن إضافة التوجيه للصفحات المناسبة
    // بناءً على payload
  }

  // إرسال إشعار مجدول للمستخدمين (يتطلب خادم)
  Future<void> scheduleNotificationToUsers({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      // هذا يتطلب خادم لإرسال الإشعارات
      // يمكن إضافة API call هنا لإرسال الإشعارات
      print('📤 إرسال إشعار للمستخدمين: $title');

      // مثال على كيفية إرسال الإشعار عبر API
      // await _sendNotificationViaAPI(title, body, payload);
    } catch (e) {
      print('❌ خطأ في إرسال الإشعار: $e');
    }
  }

  // تسجيل المستخدم لتلقي إشعارات محددة
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      print('✅ تم الاشتراك في الموضوع: $topic');
    } catch (e) {
      print('❌ خطأ في الاشتراك في الموضوع: $e');
    }
  }

  // جلب جميع FCM tokens من قاعدة البيانات
  Future<List<String>> getAllFCMTokens() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('fcmToken', isNotEqualTo: null)
          .get();

      List<String> tokens = [];
      usersSnapshot.docs.forEach((doc) {
        final token = doc.data()['fcmToken'] as String?;
        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      });

      print('📊 تم جلب ${tokens.length} FCM token من قاعدة البيانات');
      return tokens;
    } catch (e) {
      print('❌ خطأ في جلب FCM tokens: $e');
      return [];
    }
  }

  // جلب FCM tokens لمستخدمين محددين
  Future<List<String>> getFCMTokensForUsers(List<String> userIds) async {
    try {
      List<String> tokens = [];

      for (String userId in userIds) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();

        if (userDoc.exists) {
          final token = userDoc.data()?['fcmToken'] as String?;
          if (token != null && token.isNotEmpty) {
            tokens.add(token);
          }
        }
      }

      print('📊 تم جلب ${tokens.length} FCM token للمستخدمين المحددين');
      return tokens;
    } catch (e) {
      print('❌ خطأ في جلب FCM tokens للمستخدمين: $e');
      return [];
    }
  }

  // إلغاء اشتراك المستخدم من موضوع
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      print('✅ تم إلغاء الاشتراك من الموضوع: $topic');
    } catch (e) {
      print('❌ خطأ في إلغاء الاشتراك من الموضوع: $e');
    }
  }
}

// معالج الرسائل في الخلفية (يجب أن يكون خارج الكلاس)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📱 رسالة في الخلفية: ${message.notification?.title}');
}
