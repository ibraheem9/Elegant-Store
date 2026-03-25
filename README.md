# Elegant Store - نظام إدارة متجر البيع بالتجزئة

نظام متكامل لإدارة عمليات البيع والمشتريات والديون لمتجر بيع بالتجزئة، مصمم ليعمل بدون إنترنت (Offline-first) مع إمكانية المزامنة لاحقاً.

---

A complete retail management system built with Flutter and SQLite. Works offline with complete functionality for sales, purchases, statistics, and customer management, with full Arabic RTL support.

## 🌟 المميزات (Features)

- ✅ **دعم كامل للغة العربية (Full Arabic RTL Support)**
- ✅ **إدارة الديون المتقدمة (Advanced Debt Management)** — credit limits, overdue alerts
- ✅ **إحصائيات دقيقة (Precise Daily Statistics)**
- ✅ **مراجعة المدفوعات (Payment Review)** — match payments across apps
- ✅ **أتمتة التواريخ (Date Automation)** — Arabic date/day auto-filled

## 🚀 حسابات تجريبية (Test Accounts)

كلمة المرور لجميع الحسابات: `123`

| Username | Role | Name |
|---|---|---|
| `hamoda` | محاسب | محمد ياغي (حمودة) |
| `eldaj` | محاسب | محمد عبد الهادي (الدج) |
| `ahmed_yaghi` | محاسب | أحمد ياغي |
| `ibrahim` | مدير | إبراهيم عبد الهادي |

## 🛠 التقنيات (Tech Stack)

- **Flutter 3.x** — cross-platform UI
- **SQLite (`sqflite` + `sqflite_common_ffi`)** — local offline database
- **Provider** — state management
- **Intl** — Arabic date formatting

## 📱 Platform Support

| Platform | Supported | Notes |
|---|---|---|
| Android | ✅ | Full support |
| iOS | ✅ | Full support |
| Windows | ✅ | Uses sqflite FFI |
| Linux | ✅ | Uses sqflite FFI |
| macOS | ✅ | Uses sqflite FFI |
| **Web** | ❌ | **Not supported** — sqflite requires a native file system. Running on Web will show a clear unsupported message. |

## ⚙️ كيفية التشغيل (How to Run)

### Prerequisites
- Flutter SDK ≥ 3.0 installed
- For Windows/Linux: no extra setup needed (sqflite FFI is bundled via `sqlite3_flutter_libs`)

### Steps
```bash
flutter pub get
flutter run                        # picks the connected device
flutter run -d windows             # Windows desktop
flutter run -d linux               # Linux desktop
flutter run -d android             # Android device/emulator
```

> ⚠️ `flutter run -d chrome` is **not supported** and will show an error screen.

## 🗄️ DB Setup & Troubleshooting

The database (`elegant_store.db`) is created automatically on first launch.  
In **debug mode**, the full DB path is printed to the console:
```
[DatabaseService] DB path: /data/user/0/com.example.elegant_store/databases/elegant_store.db
[DatabaseService] Database initialized successfully.
```

### Common Issues

| Problem | Solution |
|---|---|
| App crashes with `MissingPluginException` on desktop | Run `flutter pub get` and rebuild — `sqlite3_flutter_libs` must be resolved |
| Old schema / migration error | Delete the app data or uninstall and reinstall to let the DB recreate |
| "Database not found" on Windows | Ensure you run `flutter run -d windows`, not via web |
| Locale / DateFormat crash on startup | Fixed in this version — `initializeDateFormatting('ar')` is called in `main()` |

### Resetting the Database (Development)
Delete the app data from device settings, or on desktop delete the DB file printed to the console, then re-run the app. The database and seed data will be recreated automatically.

## 🖼️ Adding Your Logo

1. Place your logo file at: `assets/images/logo.png` (512×512 px recommended, PNG format)
2. The `LoginScreen` will automatically detect and use it. No code change needed.
3. If the file is missing, the app falls back to the default `Icons.store_rounded` icon.

> The `assets/images/` directory is already registered in `pubspec.yaml`.  
> A placeholder SVG (`assets/images/logo_placeholder.svg`) is included for reference.

## 📂 Project Structure

```
lib/
  main.dart           — app entry, intl init, platform guard, DI setup
  theme/
    app_theme.dart    — centralized Material 3 theme (colors, typography, shapes)
  models/
    models.dart       — data models (User, Invoice, Purchase, etc.)
  services/
    database_service.dart  — SQLite CRUD, seeding, logging
    auth_service.dart      — authentication
  screens/
    login_screen.dart      — responsive RTL login
    dashboard_screen.dart
    sales_screen.dart
    purchases_screen.dart
    statistics_screen.dart
    customers_screen.dart
    payments_screen.dart
assets/
  images/
    logo.png          — your logo (add this file)
    logo_placeholder.svg  — placeholder reference
```

---
**Built with Flutter | Powered by SQLite | Made with ❤️**
