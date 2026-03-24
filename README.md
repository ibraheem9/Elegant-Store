# Elegant Store - نظام إدارة متجر البيع بالتجزئة

نظام متكامل لإدارة عمليات البيع والمشتريات والديون لمتجر بيع بالتجزئة، مصمم ليعمل بدون إنترنت (Offline-first) مع إمكانية المزامنة لاحقاً.

---

A complete retail management system built with Flutter and SQLite. Works offline with complete functionality for sales, purchases, statistics, and customer management, now with full Arabic support and updated requirements.

## 🌟 المميزات الجديدة (New Features)

- ✅ **دعم كامل للغة العربية (Full Arabic Support)** - واجهة مستخدم RTL مصممة لتناسب احتياجات المستخدم العربي.
- ✅ **إدارة الديون المتقدمة (Advanced Debt Management)** - تتبع سقف الدين (Credit Limit) للزبائن الدائمين وتنبيهات عند الاقتراب منه.
- ✅ **إحصائيات دقيقة (Precise Statistics)** - حساب الدخل اليومي بناءً على معادلات محاسبية معتمدة في النظام.
- ✅ **مراجعة المدفوعات (Payment Review)** - شاشة مخصصة لمطابقة المدفوعات مع تطبيقات البنوك (إبراهيم، حمودة، إلخ).
- ✅ **أتمتة التواريخ (Date Automation)** - إدخال تلقائي لليوم والتاريخ بالتنسيق العربي (مثال: 21-03-2026 السبت).

## 🚀 الحسابات التجريبية (Test Accounts)

يمكنك استخدام الحسابات التالية لتجربة النظام (كلمة المرور لجميع الحسابات هي `123`):
- **المحاسبين (Accountants)**: `hamoda`, `eldaj`, `ahmed_yaghi`
- **المدير (Manager)**: `ibrahim`

## 🛠 التقنيات المستخدمة (Tech Stack)

- **Flutter**: لبناء واجهة المستخدم المتعددة المنصات.
- **SQLite (sqflite)**: لتخزين البيانات محلياً.
- **Provider**: لإدارة حالة التطبيق.
- **Intl**: للتعامل مع التواريخ واللغة العربية.

## 📂 هيكلية المشروع (Project Structure)

- `lib/models`: نماذج البيانات (User, Invoice, Purchase, etc).
- `lib/services`: خدمات قاعدة البيانات والتحقق من الهوية.
- `lib/screens`: شاشات التطبيق (البيع، الإحصائيات، الزبائن، إلخ).

## ⚙️ كيفية التشغيل (How to Run)

1. تأكد من تثبيت Flutter SDK.
2. `flutter pub get`
3. `flutter run`

---
تم التطوير وتحديث النظام بناءً على المتطلبات الجديدة لضمان أداء مهني وعالي الجودة.
**Built with Flutter | Powered by SQLite | Made with ❤️**
