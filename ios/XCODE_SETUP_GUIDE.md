# دليل إعداد Xcode للتشغيل لأول مرة على iOS

## ⚠️ خطوات مهمة جداً قبل التشغيل:

### 1. فتح المشروع في Xcode

```bash
cd ios
open Runner.xcworkspace
```

**مهم:** استخدم `Runner.xcworkspace` وليس `Runner.xcodeproj`

---

### 2. إصلاح Bundle Identifier (مهم جداً!)

**المشكلة الحالية:**
- Bundle ID في المشروع: `com.example.almhnaken`
- Bundle ID في Firebase: `com.alrawi.almhnaken`

**الحل:**

1. في Xcode، اختر **Runner** من القائمة الجانبية
2. اختر **Runner** target (ليس RunnerTests)
3. اذهب إلى تبويب **General**
4. في قسم **Identity**، غيّر **Bundle Identifier** إلى:
   ```
   com.alrawi.almhnaken
   ```
5. كرر نفس الخطوة لـ **RunnerTests** target:
   - Bundle Identifier: `com.alrawi.almhnaken.RunnerTests`

---

### 3. إضافة ملف GoogleService-Info.plist للمشروع

1. في Xcode، انقر بزر الماوس الأيمن على مجلد **Runner** (في القائمة الجانبية)
2. اختر **Add Files to "Runner"...**
3. ابحث عن ملف `GoogleService-Info.plist` في مجلد `ios/Runner/`
4. تأكد من:
   - ✅ **Copy items if needed** (غير مفعّل - الملف موجود بالفعل)
   - ✅ **Add to targets: Runner** (مفعّل)
5. اضغط **Add**

---

### 4. إعداد Signing & Capabilities

1. اختر **Runner** target
2. اذهب إلى تبويب **Signing & Capabilities**
3. في قسم **Signing**:
   - ✅ فعّل **Automatically manage signing**
   - اختر **Team** الخاص بك (Apple Developer Account)
   - إذا لم يكن لديك حساب، ستحتاج إلى:
     - إنشاء Apple ID مجاني
     - أو الاشتراك في Apple Developer Program ($99/سنة)

---

### 5. التحقق من Deployment Target

1. في تبويب **General**
2. تأكد من أن **iOS Deployment Target** هو **13.0** أو أعلى
3. إذا كان أقل، غيّره إلى **13.0**

---

### 6. إضافة Capabilities (إن لزم الأمر)

1. في تبويب **Signing & Capabilities**
2. اضغط **+ Capability**
3. أضف:
   - ✅ **Push Notifications** (للإشعارات)
   - ✅ **Background Modes** (تم إضافتها تلقائياً)

---

### 7. اختيار الجهاز/المحاكي

1. في شريط الأدوات العلوي في Xcode
2. اختر جهاز iOS أو محاكي من القائمة المنسدلة
3. للاختبار السريع، استخدم محاكي iPhone

---

### 8. بناء وتشغيل التطبيق

**الطريقة الأولى: من Xcode**
1. اضغط **⌘ + R** (أو زر Play)
2. انتظر حتى يتم البناء والتشغيل

**الطريقة الثانية: من Terminal (أسهل)**
```bash
cd /Users/ahmadsalim/devloper/almhnaken/almhnaken
flutter run
```

---

## ✅ قائمة التحقق النهائية:

- [ ] تم فتح `Runner.xcworkspace` في Xcode
- [ ] Bundle Identifier تم تغييره إلى `com.alrawi.almhnaken`
- [ ] ملف `GoogleService-Info.plist` تم إضافته للمشروع
- [ ] Signing تم إعداده (Team محدد)
- [ ] iOS Deployment Target = 13.0
- [ ] تم اختيار جهاز/محاكي
- [ ] التطبيق يعمل بدون أخطاء

---

## 🚨 حل المشاكل الشائعة:

### خطأ: "No signing certificate found"
**الحل:** 
- تأكد من تسجيل الدخول إلى Apple ID في Xcode
- Preferences → Accounts → أضف Apple ID

### خطأ: "GoogleService-Info.plist not found"
**الحل:**
- تأكد من إضافة الملف للمشروع في Xcode
- تأكد من أن الملف موجود في `ios/Runner/`

### خطأ: "Bundle identifier mismatch"
**الحل:**
- تأكد من أن Bundle ID في Xcode يطابق Bundle ID في Firebase
- يجب أن يكون: `com.alrawi.almhnaken`

---

## 📝 ملاحظات مهمة:

1. **للتطوير والاختبار:** يمكنك استخدام Apple ID مجاني
2. **للنشر على App Store:** تحتاج Apple Developer Program ($99/سنة)
3. **للتشغيل على جهاز حقيقي:** تحتاج إلى تسجيل الجهاز في Apple Developer Portal

