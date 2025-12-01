# إعداد سريع للبانرات - خطوة بخطوة

## الخطوة 1: افتح Firebase Console
1. اذهب إلى [Firebase Console](https://console.firebase.google.com/)
2. اختر مشروعك
3. من القائمة الجانبية، اضغط على **Firestore Database**

---

## الخطوة 2: إنشاء Collection
1. اضغط على **Start collection** (أو **Add collection** إذا كان لديك collections موجودة)
2. أدخل اسم الـ Collection: **`banners`**
3. اضغط **Next**

---

## الخطوة 3: إضافة أول بانر

### املأ الحقول كالتالي:

**Document ID:** اتركه فارغاً ليتم إنشاؤه تلقائياً

**Field 1:**
- Field name: `imageUrl`
- Field type: `string`
- Field value: رابط الصورة (مثال: `https://your-image-url.com/banner1.jpg`)

**Field 2:**
- Field name: `linkUrl`
- Field type: `string`
- Field value: رابط Instagram أو أي رابط آخر (مثال: `https://www.instagram.com/yourpage/`)

**Field 3:**
- Field name: `order`
- Field type: `number`
- Field value: `1`

**Field 4:**
- Field name: `isActive`
- Field type: `boolean`
- Field value: `true` (مفعّل) ✅

**اضغط Save**

---

## الخطوة 4: إضافة المزيد من البانرات

كرر الخطوة 3 لإضافة حتى **5 بانرات**، مع تغيير:
- `order` إلى 2، 3، 4، 5 لكل بانر
- `imageUrl` لكل بانر
- `linkUrl` حسب احتياجك (يمكن تركه فارغاً)

---

## الخطوة 5: رفع الصور (اختياري - إذا أردت استخدام Firebase Storage)

### 1. رفع الصورة:
1. من Firebase Console، اذهب إلى **Storage**
2. اضغط **Upload file**
3. اختر صورة البانر من جهازك
4. بعد الرفع، اضغط على الصورة
5. انسخ **Download URL**

### 2. استخدام الرابط:
- الصق الرابط في حقل `imageUrl` في Firestore

---

## الخطوة 6: اختبار البانرات

1. افتح التطبيق على هاتفك
2. ستظهر البانرات في أسفل الشاشة الرئيسية
3. اضغط على أي بانر للانتقال إلى الرابط

---

## نموذج JSON سريع للنسخ واللصق

إذا كنت تريد إضافة البانرات عبر Firebase CLI أو REST API:

```json
{
  "banners": {
    "banner1": {
      "imageUrl": "https://example.com/banner1.jpg",
      "linkUrl": "https://www.instagram.com/yourpage/",
      "order": 1,
      "isActive": true
    },
    "banner2": {
      "imageUrl": "https://example.com/banner2.jpg",
      "linkUrl": "https://www.facebook.com/yourpage/",
      "order": 2,
      "isActive": true
    },
    "banner3": {
      "imageUrl": "https://example.com/banner3.jpg",
      "linkUrl": "https://wa.me/9647xxxxxxxxx",
      "order": 3,
      "isActive": true
    },
    "banner4": {
      "imageUrl": "https://example.com/banner4.jpg",
      "linkUrl": "",
      "order": 4,
      "isActive": true
    },
    "banner5": {
      "imageUrl": "https://example.com/banner5.jpg",
      "linkUrl": "https://your-website.com",
      "order": 5,
      "isActive": true
    }
  }
}
```

---

## تذكير: Firestore Rules

تأكد من أن Firestore Rules تسمح بقراءة البانرات:

```javascript
match /banners/{bannerId} {
  allow read: if true;  // السماح للجميع بالقراءة
  allow write: if false; // منع الكتابة من التطبيق
}
```

---

## 🎉 انتهى!

الآن يمكنك تغيير البانرات من Firebase بدون الحاجة لإعادة بناء التطبيق!

