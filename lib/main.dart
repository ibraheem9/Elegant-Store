import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/device_sync_service.dart';
import 'services/sync_manager.dart';
import 'services/license_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/license_gate_screen.dart';
import 'core/config/app_themes.dart';
import 'core/config/api_config.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String syncTaskName = "com.elegantstore.sync_task";

  @pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Platform.isWindows) return Future.value(true);

      final dbService = DatabaseService();
      final prefs = await SharedPreferences.getInstance();
      
      // Use new device sync service with proper baseUrl
      final dio = Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final token = prefs.getString('auth_token');
      if (token != null) {
        dio.options.headers['Authorization'] = 'Bearer $token';
      }
      
      final deviceSyncService = DeviceSyncService(
        dio: dio,
        authService: AuthService(dbService, SyncService(dbService, prefs)),
        databaseService: dbService,
      );
      
      await deviceSyncService.performFullSyncDefault();
      return Future.value(true);
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return Future.value(false);
    }
  });
}

void main() async {
  // Disable Impeller renderer to avoid Mali GPU allocator issues
  // This forces Skia rendering which is more compatible
  // See: https://github.com/flutter/flutter/issues/...
  // Impeller causes "Format allocation info not found" errors on Mali GPUs
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Note: For Android, Impeller can be disabled in AndroidManifest.xml or via native code
  // For now, we rely on the device's GPU compatibility

  // Initialize date formatting (fast, no network)
  try {
    await initializeDateFormatting('ar_SA', null);
  } catch (e) {
    debugPrint('initializeDateFormatting failed: $e');
  }
  
  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize database (local SQLite, should be fast)
  final dbService = DatabaseService();
  try {
    await dbService.initDatabase().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('initDatabase timed out');
        throw Exception('initDatabase timed out');
      },
    );
  } catch (e) {
    debugPrint('initDatabase failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  
  // Initialize Notifications (with timeout to prevent hang on Android)
  try {
    await NotificationService.init().timeout(
      const Duration(seconds: 5),
      onTimeout: () => debugPrint('NotificationService.init timed out, continuing...'),
    );
  } catch (e) {
    debugPrint('NotificationService.init failed: $e');
  }

  final syncService = SyncService(dbService, prefs);
  final authService = AuthService(dbService, syncService);
  
  // initSession with timeout to prevent splash screen hang
  try {
    await authService.initSession().timeout(
      const Duration(seconds: 8),
      onTimeout: () => debugPrint('initSession timed out, continuing with cached state...'),
    );
  } catch (e) {
    debugPrint('initSession failed: $e');
  }

  // Initialize Workmanager (Android background tasks) — fire-and-forget to avoid blocking
  if (!Platform.isWindows) {
    _initWorkmanager();
  }

  // Check license before showing the app
  final licenseResult = await LicenseService.instance.checkStoredLicense();

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => dbService),
        ChangeNotifierProvider<SyncService>(create: (_) => syncService),
        ChangeNotifierProvider<AuthService>(create: (_) => authService),
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
        // Add DeviceSyncService provider
        ProxyProvider<AuthService, DeviceSyncService>(
          update: (_, authService, __) {
            final dio = Dio(
              BaseOptions(
                baseUrl: ApiConfig.baseUrl,
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );
            final token = prefs.getString('auth_token');
            if (token != null) {
              dio.options.headers['Authorization'] = 'Bearer $token';
            }
            return DeviceSyncService(
              dio: dio,
              authService: authService,
              databaseService: dbService,
            );
          },
        ),
        // Add SyncManager provider
        ProxyProvider2<DeviceSyncService, DatabaseService, SyncManager>(
          update: (_, deviceSyncService, databaseService, __) {
            return SyncManager(
              deviceSyncService: deviceSyncService,
              databaseService: databaseService,
              syncInterval: const Duration(minutes: 15),
              maxRetries: 3,
            );
          },
        ),
      ],
      child: ElegantStoreApp(isLicensed: licenseResult.isValid),
    ),
  );
}

/// Initialize Workmanager in the background without blocking app startup.
void _initWorkmanager() {
  Future.microtask(() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: false,
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('Workmanager.initialize timed out');
      });

      await Workmanager().registerPeriodicTask(
        "1",
        syncTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('Workmanager.registerPeriodicTask timed out');
      });
    } catch (e) {
      debugPrint('Workmanager init failed: $e');
    }
  });
}

class ElegantStoreApp extends StatefulWidget {
  final bool isLicensed;
  const ElegantStoreApp({Key? key, required this.isLicensed}) : super(key: key);

  @override
  State<ElegantStoreApp> createState() => _ElegantStoreAppState();
}

class _ElegantStoreAppState extends State<ElegantStoreApp> {
  late bool _isLicensed;

  @override
  void initState() {
    super.initState();
    _isLicensed = widget.isLicensed;
  }

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
      home: _isLicensed
          ? const _AppHome()
          : LicenseGateScreen(
              onLicenseActivated: () => setState(() => _isLicensed = true),
            ),
    );
  }
}

/// Stateful home widget that ensures post-login side effects (sync, notifications)
/// are triggered exactly once per login session, not on every Consumer rebuild.
class _AppHome extends StatefulWidget {
  const _AppHome({Key? key}) : super(key: key);

  @override
  State<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<_AppHome> with WidgetsBindingObserver {
  bool _postLoginSyncTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _triggerPostLoginSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _triggerPostLoginSync() {
    if (_postLoginSyncTriggered) return;

    final authService = context.read<AuthService>();
    if (!authService.isLoggedIn) return;

    _postLoginSyncTriggered = true;

    // Trigger device sync
    Future.microtask(() async {
      try {
        final syncManager = context.read<SyncManager>();
        // Enable automatic sync (15 min interval)
        syncManager.enable();
        // Force immediate sync on login
        await syncManager.forceSyncNow();
      } catch (e) {
        debugPrint('Post-login sync failed: $e');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final authService = context.read<AuthService>();
      if (authService.isLoggedIn) {
        Future.microtask(() async {
          try {
            final syncManager = context.read<SyncManager>();
            // Ensure sync is enabled when app resumes
            if (!syncManager.isEnabled) {
              syncManager.enable();
            }
            // Force sync on app resume
            await syncManager.forceSyncNow();
          } catch (e) {
            debugPrint('App resume sync failed: $e');
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return authService.isLoggedIn ? const DashboardScreen() : const LoginScreen();
      },
    );
  }
}
