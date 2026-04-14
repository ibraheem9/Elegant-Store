import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'core/config/app_themes.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String syncTaskName = "com.elegantstore.sync_task";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Platform.isWindows) return Future.value(true);

      final dbService = DatabaseService();
      final prefs = await SharedPreferences.getInstance();
      final syncService = SyncService(dbService, prefs);
      
      await syncService.performFullSync();
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar_SA', null);
  
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final dbService = DatabaseService();
  await dbService.initDatabase();
  final prefs = await SharedPreferences.getInstance();
  
  // Initialize Notifications
  await NotificationService.init();

  final syncService = SyncService(dbService, prefs);
  final authService = AuthService(dbService, syncService);
  await authService.initSession();

  if (!Platform.isWindows) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    
    await Workmanager().registerPeriodicTask(
      "1",
      syncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => dbService),
        ChangeNotifierProvider<SyncService>(create: (_) => syncService),
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
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (authService.isLoggedIn && authService.currentUser != null) {
               // 1. Fix local data ownership before sync
               await context.read<DatabaseService>().fixLocalDataOwnership(authService.currentUser!);

               // 2. Schedule notifications
               NotificationService.scheduleDailyCheck(context.read<DatabaseService>());

               // 3. Trigger initial sync
               context.read<SyncService>().performFullSync(isInitialSync: true).catchError((e) {
                 debugPrint('Initial sync failed: $e');
               });
            }
          });

          if (authService.isLoggedIn) return const DashboardScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}
