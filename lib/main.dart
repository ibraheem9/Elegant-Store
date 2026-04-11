import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'core/config/app_themes.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar_SA', null);
  
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbService = DatabaseService();
  await dbService.initDatabase();
  
  // Initialize Notifications
  await NotificationService.init();

  final authService = AuthService(dbService);
  await authService.initSession(); // Restore session before UI loads

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => dbService),
        ChangeNotifierProvider<AuthService>(create: (_) => authService),
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
      ],
      child: const ElegantStoreApp(),
    ),
  );
}

class ElegantStoreApp extends StatelessWidget {
  const ElegantStoreApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    
    // Check for notifications after app load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.scheduleDailyCheck(context.read<DatabaseService>());
    });

    return MaterialApp(
      title: 'Elegant Store',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeNotifier.themeMode,
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA')],
      locale: const Locale('ar', 'SA'),
      home: Consumer<AuthService>(
        builder: (context, authService, _) {
          if (authService.isLoggedIn) return const DashboardScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}
