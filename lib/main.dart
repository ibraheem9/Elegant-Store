import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:window_manager/window_manager.dart';

import 'services/database_service.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'services/device_sync_service.dart';
import 'services/sync_manager.dart';
import 'services/license_service.dart';
import 'services/telemetry_service.dart';
import 'services/customer_tracking_service.dart';
import 'services/internal_resource_loader.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/license_gate_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/developer_management_screen.dart';
import 'screens/database_setup_screen.dart';
import 'core/config/app_themes.dart';
import 'core/config/api_config.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Import sync services for ChangeNotifierProvider (even if disabled)

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String syncTaskName = "com.abdelhadistore.sync_task";

  /* 
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
      
      final syncService = SyncService(dbService, prefs);
      final deviceSyncService = DeviceSyncService(
        dio: dio,
        authService: AuthService(dbService, syncService),
        databaseService: dbService,
      );
      
      // Push local changes first
      try {
        await syncService.performFullSync();
      } catch (e) {
        debugPrint('Background sync (push) failed: $e');
      }

      // Then pull updates
      await deviceSyncService.performFullSyncDefault();

      // Sync customer tracking data
      await CustomerTrackingService.instance.syncCustomerData();

      return Future.value(true);
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return Future.value(false);
    }
  });
}
*/

void main() async {
  // Disable Impeller renderer to avoid Mali GPU allocator issues
  // This forces Skia rendering which is more compatible
  // See: https://github.com/flutter/flutter/issues/...
  // Impeller causes "Format allocation info not found" errors on Mali GPUs
  WidgetsFlutterBinding.ensureInitialized();
  await _startApp();
}

Future<void> _startApp() async {
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

  final prefs = await SharedPreferences.getInstance();
  String? savedPath = prefs.getString('custom_database_path');

  bool dbExists = false;
  if (savedPath != null) {
    dbExists = File(savedPath).existsSync();
    if (dbExists) DatabaseService.setCustomPath(savedPath);
  } else if (Platform.isWindows) {
    final docs = await getApplicationDocumentsDirectory();
    final defaultPath = p.join(docs.path, 'AbdElhadiStoreApp', DatabaseService.dbName);
    dbExists = File(defaultPath).existsSync();
  } else {
    // Mobile: assume it's fine or will be created on open
    dbExists = true;
  }

  if (!dbExists && Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(800, 600),
      center: true,
      title: 'Abd Elhadi Store',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppThemes.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA')],
      locale: const Locale('ar', 'SA'),
      home: DatabaseSetupScreen(onSetupComplete: () => _startApp()),
    ));
    return;
  }
  
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      minimumSize: Size(800, 600),
      center: true,
      title: 'Abd Elhadi Store',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
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
  final telemetryService = TelemetryService(dbService);
  
  // initSession with timeout to prevent splash screen hang
  try {
    await authService.initSession().timeout(
      const Duration(seconds: 8),
      onTimeout: () => debugPrint('initSession timed out, continuing with cached state...'),
    );
    
    // Also check profile completion if logged in
    if (authService.isLoggedIn) {
      await telemetryService.checkProfileCompletion().timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint('checkProfileCompletion timed out'),
      );
    }
  } catch (e) {
    debugPrint('initSession/telemetry check failed: $e');
  }

  /* 
  // Initialize Workmanager (Android background tasks) — fire-and-forget to avoid blocking
  if (!Platform.isWindows) {
    _initWorkmanager();
  }
  */

  // Check license before showing the app
  final licenseResult = await LicenseService.instance.checkStoredLicense();

  // Initial integrity check (fire and forget)
  InternalResourceLoader.instance.loadResources();

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseService>(create: (_) => dbService),
        ChangeNotifierProvider<SyncService>(create: (_) => syncService),
        ChangeNotifierProvider<AuthService>(create: (_) => authService),
        ChangeNotifierProvider<ThemeNotifier>(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider<TelemetryService>(create: (_) => telemetryService),
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
        ProxyProvider3<DeviceSyncService, DatabaseService, SyncService, SyncManager>(
          update: (_, deviceSyncService, databaseService, syncService, __) {
            return SyncManager(
              deviceSyncService: deviceSyncService,
              databaseService: databaseService,
              syncService: syncService,
              syncInterval: const Duration(hours: 1),
              maxRetries: 3,
            );
          },
        ),
      ],
      child: AbdElhadiStoreApp(isLicensed: licenseResult.isValid),
    ),
  );
}

/*
/// Initialize Workmanager in the background without blocking app startup.
void _initWorkmanager() {
...
  });
}
*/

class AbdElhadiStoreApp extends StatefulWidget {
  final bool isLicensed;
  const AbdElhadiStoreApp({super.key, required this.isLicensed});

  @override
  State<AbdElhadiStoreApp> createState() => _AbdElhadiStoreAppState();
}

class _AbdElhadiStoreAppState extends State<AbdElhadiStoreApp> {
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
      title: 'Abd Elhadi Store',
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
  const _AppHome({super.key});

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
    
    // Integrity check on home initialization
    InternalResourceLoader.instance.loadResources();
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

    // Check if store profile is complete
    context.read<TelemetryService>().checkProfileCompletion();

    // We no longer trigger automatic sync on login as requested.
    // SyncManager is now manual.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Periodic integrity check on resume
      InternalResourceLoader.instance.loadResources();

      // Trigger tracking sync on resume to check for credential resets
      CustomerTrackingService.instance.syncCustomerData();

      final authService = context.read<AuthService>();
      if (authService.isLoggedIn) {
        // Refresh profile completion check on resume
        context.read<TelemetryService>().checkProfileCompletion();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, TelemetryService>(
      builder: (context, authService, telemetryService, _) {
        if (!authService.isLoggedIn) {
          // Reset sync trigger when logged out so it runs again on next login
          _postLoginSyncTriggered = false;
          return const LoginScreen();
        }

        // If logged in but sync not triggered yet, trigger it
        if (!_postLoginSyncTriggered) {
          // Use microtask to avoid calling notifyListeners during build
          Future.microtask(() => _triggerPostLoginSync());
        }

        if (authService.isDeveloper()) {
          // Import required for DeveloperManagementScreen if not already there
          return const DeveloperManagementScreen();
        }

        // If logged in, check if profile is complete (only for managers)
        // We only show setup screen if we are SURE it's not complete
        if (authService.isManager() && !telemetryService.isProfileComplete) {
          return const ProfileSetupScreen();
        }

        return const DashboardScreen();
      },
    );
  }
}
