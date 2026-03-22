# Elegant Store - Flutter Retail Management App

A complete retail management system built with Flutter and SQLite. Works offline with complete functionality for sales, purchases, statistics, and customer management.

## Features

✅ **Complete Offline Functionality** - No internet required  
✅ **SQLite Database** - 7 tables with full schema  
✅ **7 Test Accounts** - Ready to use immediately  
✅ **Sales Management** - Create and track invoices  
✅ **Purchase Tracking** - Record supplier purchases  
✅ **Daily Statistics** - Cash flow tracking  
✅ **Customer Management** - View profiles and debt  
✅ **Payment Processing** - Mark invoices as paid  
✅ **Arabic Support** - Full RTL text support  
✅ **Material Design 3** - Modern UI  

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── models.dart          # All data models
├── services/
│   ├── database_service.dart # SQLite operations
│   └── auth_service.dart    # Authentication
└── screens/
    ├── login_screen.dart
    ├── dashboard_screen.dart
    ├── sales_screen.dart
    ├── statistics_screen.dart
    ├── purchases_screen.dart
    ├── customers_screen.dart
    └── payments_screen.dart
```

## Test Accounts

### Accountants
- Username: `hamoda`
- Username: `eldaj`
- Username: `ahmed_yaghi`

### Manager
- Username: `ibrahim_manager`

### Customers
- Username: `customer_hassan` (Credit: 100 ₪)
- Username: `customer_ali` (Credit: 150 ₪)
- Username: `customer_fatima` (Credit: 200 ₪)

**Password**: `demo` (or any value)

## Database Schema

### Tables
1. **users** - User accounts and roles
2. **payment_methods** - 8 payment options
3. **invoices** - Sales transactions
4. **purchases** - Supplier purchases
5. **daily_statistics** - Financial summaries
6. **customer_payments** - Payment records
7. **debt_reminders** - Debt tracking

## Getting Started

### Prerequisites
- Flutter 3.0+
- Dart 3.0+
- Android Studio (for Android development)
- Xcode (for iOS development)
- Visual Studio (for Windows development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/elegant_store_flutter.git
   cd elegant_store_flutter
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

## Building for Different Platforms

### Android (APK)

1. **Debug APK**
   ```bash
   flutter build apk --debug
   ```
   Output: `build/app/outputs/flutter-apk/app-debug.apk`

2. **Release APK**
   ```bash
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`

3. **Install on device**
   ```bash
   flutter install
   ```

### Windows (EXE)

1. **Build Windows app**
   ```bash
   flutter build windows --release
   ```
   Output: `build/windows/runner/Release/elegant_store.exe`

2. **Run directly**
   ```bash
   flutter run -d windows
   ```

### macOS (DMG)

1. **Build macOS app**
   ```bash
   flutter build macos --release
   ```

### iOS (IPA)

1. **Build iOS app**
   ```bash
   flutter build ios --release
   ```

## Database Location

### Android
```
/data/data/com.elegant.store/databases/elegant_store.db
```

### Windows
```
C:\Users\[YourUsername]\AppData\Local\elegant_store\elegant_store.db
```

### macOS
```
~/Library/Application Support/elegant_store/elegant_store.db
```

### iOS
```
Documents/elegant_store.db
```

## Dependencies

- **sqflite** - SQLite database
- **path_provider** - File system access
- **provider** - State management
- **google_fonts** - Typography
- **intl** - Internationalization
- **fl_chart** - Charts and graphs
- **shared_preferences** - Local storage
- **table_calendar** - Calendar widget
- **pdf** - PDF generation
- **printing** - Print functionality

## Features Detailed

### Dashboard
- Overview of pending invoices
- Total pending amount
- Customer count
- Today's sales and purchases

### Sales Screen
- Create new invoices
- Select customer
- Choose payment method
- Add notes
- View today's invoices
- Track payment status

### Statistics Screen
- Daily cash flow tracking
- Calculate daily income
- Financial summaries
- Cash box management

### Purchases Screen
- Record supplier purchases
- Select payment method
- View today's purchases
- Track purchase totals

### Customers Screen
- View all customers
- Display customer debt
- Check credit limits
- Purchase history

### Payments Screen
- View pending invoices
- Mark invoices as paid
- Track payment status
- Daily payment summary

## Development

### Running in Debug Mode
```bash
flutter run
```

### Running with specific device
```bash
flutter devices  # List available devices
flutter run -d <device-id>
```

### Building and running release
```bash
flutter run --release
```

## Troubleshooting

### App won't start
1. Run `flutter clean`
2. Run `flutter pub get`
3. Run `flutter run`

### Database errors
1. Delete app data
2. Restart the app
3. Database will reinitialize

### Build errors
1. Run `flutter doctor` to check setup
2. Install missing dependencies
3. Run `flutter clean` and rebuild

## Performance Tips

- Use release builds for production
- Close other apps when running
- Ensure sufficient disk space
- Keep Flutter SDK updated

## Future Enhancements

- [ ] API integration with Laravel backend
- [ ] Cloud backup and sync
- [ ] Advanced reporting
- [ ] Multi-user support
- [ ] Real-time notifications
- [ ] Expense tracking
- [ ] Inventory management
- [ ] Multi-language support

## License

MIT License - See LICENSE file for details

## Support

For issues and questions:
1. Check this README
2. Review troubleshooting section
3. Check Flutter documentation
4. Open an issue on GitHub

## Contributing

Contributions are welcome! Please follow these steps:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

**Built with Flutter | Powered by SQLite | Made with ❤️**
