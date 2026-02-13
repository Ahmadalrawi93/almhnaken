# إعداد Firebase لـ iOS

## خطوات مهمة قبل التشغيل:

### 1. إضافة ملف GoogleService-Info.plist

يجب إضافة ملف `GoogleService-Info.plist` من Firebase Console إلى مجلد `ios/Runner/`.

**كيفية الحصول على الملف:**
1. افتح [Firebase Console](https://console.firebase.google.com/)
2. اختر مشروعك (almhanken)
3. اضغط على أيقونة iOS لإضافة تطبيق iOS
4. أدخل Bundle ID: `com.example.almhnaken` (أو Bundle ID الخاص بك)
5. حمّل ملف `GoogleService-Info.plist`
6. ضع الملف في `ios/Runner/GoogleService-Info.plist`

**ملاحظة:** تأكد من أن Bundle ID في Xcode يطابق Bundle ID في Firebase.

### 2. التحقق من Bundle Identifier

تأكد من أن Bundle Identifier في Xcode يطابق ما هو مسجل في Firebase:
- افتح `ios/Runner.xcodeproj` في Xcode
- اختر Runner target
- في تبويب General، تحقق من Bundle Identifier

### 3. تثبيت CocoaPods

بعد إضافة ملف GoogleService-Info.plist، قم بتشغيل:

```bash
cd ios
pod install
cd ..
```

### 4. بناء التطبيق

```bash
flutter clean
flutter pub get
flutter run
```

## المتطلبات المكتملة:

✅ إصدار iOS الأدنى: 13.0
✅ أذونات الكاميرا ومعرض الصور
✅ أذونات الإشعارات
✅ إعدادات Firebase في AppDelegate.swift
✅ إعدادات Background Modes للإشعارات

