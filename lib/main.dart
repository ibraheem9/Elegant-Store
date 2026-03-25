import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web is not supported: sqflite requires a native file system.
  if (kIsWeb) {
    runApp(const _WebNotSupportedApp());
    return;
  }

  // Initialize intl date formatting so DateFormat can be used anywhere in the app.
  await initializeDateFormatting('ar');
  Intl.defaultLocale = 'ar';

  // Initialize sqflite FFI for Desktop (Windows / Linux).
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize database.
  final dbService = DatabaseService();
  await dbService.initDatabase();

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => dbService),
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(dbService),
        ),
      ],
      child: const ElegantStoreApp(),
    ),
  );
}

class ElegantStoreApp extends StatelessWidget {
  const ElegantStoreApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elegant Store',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: Consumer<AuthService>(
        builder: (context, authService, _) {
          if (authService.isLoggedIn) {
            return const DashboardScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

/// Shown when the app is launched on the unsupported Web platform.
class _WebNotSupportedApp extends StatelessWidget {
  const _WebNotSupportedApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 64, color: Colors.orange),
                SizedBox(height: 16),
                Text(
                  'Web Not Supported',
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Elegant Store uses SQLite (sqflite) which requires a native '
                  'file system and cannot run in a web browser.\n\n'
                  'Please run on Android, iOS, Windows, macOS, or Linux.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
