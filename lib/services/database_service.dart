import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

class DatabaseService {
  static Database? _database;
  static const String dbName = 'elegant_store.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    if (kDebugMode) {
      debugPrint('[DatabaseService] DB path: $path');
    }

    final db = await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (kDebugMode) {
          debugPrint(
              '[DatabaseService] Upgrading DB from v$oldVersion to v$newVersion');
        }
        if (oldVersion < 2) {
          // Development upgrade: drop and recreate all tables.
          await db.execute('DROP TABLE IF EXISTS users');
          await db.execute('DROP TABLE IF EXISTS payment_methods');
          await db.execute('DROP TABLE IF EXISTS invoices');
          await db.execute('DROP TABLE IF EXISTS purchases');
          await db.execute('DROP TABLE IF EXISTS daily_statistics');
          await db.execute('DROP TABLE IF EXISTS customer_payments');
          await db.execute('DROP TABLE IF EXISTS debt_reminders');
          await _createTables(db, newVersion);
        }
      },
    );

    if (kDebugMode) {
      debugPrint('[DatabaseService] Database initialized successfully.');
    }

    _database = db;
    return db;
  }

  Future<void> _createTables(Database db, int version) async {
    if (kDebugMode) {
      debugPrint('[DatabaseService] Creating tables (v$version)…');
    }
    // Users table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        is_permanent_customer INTEGER DEFAULT 0,
        credit_limit REAL,
        created_at TEXT NOT NULL
      )
    ''');

    // Payment methods table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_methods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    // Invoices table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        invoice_date TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        payment_status TEXT NOT NULL,
        payment_method_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        edit_history TEXT,
        FOREIGN KEY(user_id) REFERENCES users(id),
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )
    ''');

    // Purchases table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method_id INTEGER,
        purchase_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )
    ''');

    // Daily statistics table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_statistics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        statistic_date TEXT UNIQUE NOT NULL,
        yesterday_cash_in_box REAL NOT NULL,
        today_cash_in_box REAL NOT NULL,
        total_cash_debt_repayment REAL NOT NULL,
        total_app_debt_repayment REAL NOT NULL,
        total_cash_purchases REAL NOT NULL,
        total_app_purchases REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Customer payments table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        invoice_id INTEGER,
        amount REAL NOT NULL,
        payment_method_id INTEGER,
        payment_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id),
        FOREIGN KEY(invoice_id) REFERENCES invoices(id),
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )
    ''');

    // Populate initial data
    await _populateInitialData(db);
  }

  Future<void> _populateInitialData(Database db) async {
    // Insert accountants and managers from docs
    final now = DateTime.now().toIso8601String();
    final users = [
      {
        'username': 'hamoda',
        'password': '123',
        'email': 'hamoda@store.com',
        'name': 'محمد ياغي (حمودة)',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': now,
      },
      {
        'username': 'eldaj',
        'password': '123',
        'email': 'eldaj@store.com',
        'name': 'محمد عبد الهادي (الدج)',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': now,
      },
      {
        'username': 'ahmed_yaghi',
        'password': '123',
        'email': 'ahmed@store.com',
        'name': 'أحمد ياغي',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': now,
      },
      {
        'username': 'ibrahim',
        'password': '123',
        'email': 'ibrahim@store.com',
        'name': 'إبراهيم عبد الهادي',
        'role': 'manager',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': now,
      },
      {
        'username': 'customer_test',
        'password': '123',
        'email': 'customer@store.com',
        'name': 'حسام',
        'role': 'customer',
        'is_permanent_customer': 1,
        'credit_limit': 100.0,
        'created_at': now,
      },
    ];

    for (var user in users) {
      await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Insert payment methods
    final paymentMethods = [
      {'name': 'كاش', 'type': 'cash', 'description': 'دفع نقدي', 'is_active': 1},
      {'name': 'تطبيق إبراهيم', 'type': 'app', 'description': 'تطبيق إبراهيم', 'is_active': 1},
      {'name': 'حمودة', 'type': 'app', 'description': 'تطبيق حمودة', 'is_active': 1},
      {'name': 'محمود', 'type': 'app', 'description': 'تطبيق محمود', 'is_active': 1},
      {'name': 'أحمد', 'type': 'app', 'description': 'تطبيق أحمد', 'is_active': 1},
      {'name': 'دج', 'type': 'app', 'description': 'تطبيق محمد عبد الهادي', 'is_active': 1},
      {'name': 'عمر', 'type': 'app', 'description': 'تطبيق عمر', 'is_active': 1},
      {'name': 'أجل (دين)', 'type': 'deferred', 'description': 'دين مؤجل', 'is_active': 1},
    ];

    for (var method in paymentMethods) {
      await db.insert('payment_methods', method, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  // User operations
  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final result = await db.query('users', where: 'username = ?', whereArgs: [username], limit: 1);
    return result.isNotEmpty ? User.fromMap(result.first) : null;
  }

  Future<User?> authenticate(String username, String password) async {
    final db = await database;
    final result = await db.query('users', where: 'username = ? AND password = ?', whereArgs: [username, password], limit: 1);
    return result.isNotEmpty ? User.fromMap(result.first) : null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final result = await db.query('users');
    return result.map((map) => User.fromMap(map)).toList();
  }

  Future<List<User>> getCustomers() async {
    final db = await database;
    final result = await db.query('users', where: 'role = ?', whereArgs: ['customer']);
    return result.map((map) => User.fromMap(map)).toList();
  }

  Future<int> insertUser(User user, String password) async {
    final db = await database;
    var map = user.toMap();
    map['password'] = password;
    return await db.insert('users', map);
  }

  Future<void> updateUser(User user) async {
    final db = await database;
    await db.update('users', user.toMap(), where: 'id = ?', whereArgs: [user.id]);
  }

  // Invoice operations
  Future<int> insertInvoice(Invoice invoice) async {
    final db = await database;
    return await db.insert('invoices', invoice.toMap());
  }

  Future<void> updateInvoice(Invoice invoice) async {
    final db = await database;
    await db.update('invoices', invoice.toMap(), where: 'id = ?', whereArgs: [invoice.id]);
  }

  Future<List<Invoice>> getInvoicesByUserId(int userId) async {
    final db = await database;
    final result = await db.query('invoices', where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC');
    return result.map((map) => Invoice.fromMap(map)).toList();
  }

  Future<List<Invoice>> getTodayInvoices() async {
    final db = await database;
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final result = await db.query('invoices', where: "invoice_date LIKE ?", whereArgs: ['$today%'], orderBy: 'created_at DESC');
    return result.map((map) => Invoice.fromMap(map)).toList();
  }

  // Purchase operations
  Future<int> insertPurchase(Purchase purchase) async {
    final db = await database;
    return await db.insert('purchases', purchase.toMap());
  }

  Future<List<Purchase>> getTodayPurchases() async {
    final db = await database;
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final result = await db.query('purchases', where: "purchase_date LIKE ?", whereArgs: ['$today%'], orderBy: 'created_at DESC');
    return result.map((map) => Purchase.fromMap(map)).toList();
  }

  // Payment method operations
  Future<List<PaymentMethod>> getPaymentMethods() async {
    final db = await database;
    final result = await db.query('payment_methods', where: 'is_active = ?', whereArgs: [1]);
    return result.map((map) => PaymentMethod.fromMap(map)).toList();
  }

  // Statistics operations
  Future<int> insertDailyStatistics(DailyStatistics stats) async {
    final db = await database;
    return await db.insert('daily_statistics', stats.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DailyStatistics?> getTodayStatistics() async {
    final db = await database;
    final today = DateFormat('dd-MM-yyyy').format(DateTime.now());
    final result = await db.query('daily_statistics', where: 'statistic_date = ?', whereArgs: [today], limit: 1);
    return result.isNotEmpty ? DailyStatistics.fromMap(result.first) : null;
  }

  // Debt calculation
  Future<double> getCustomerDebt(int userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM invoices WHERE user_id = ? AND payment_status = ?',
      [userId, 'pending'],
    );
    final totalInvoices = (result.first['total'] as num?)?.toDouble() ?? 0.0;
    
    final paymentResult = await db.rawQuery(
      'SELECT SUM(amount) as total FROM customer_payments WHERE user_id = ?',
      [userId],
    );
    final totalPayments = (paymentResult.first['total'] as num?)?.toDouble() ?? 0.0;
    
    return totalInvoices - totalPayments;
  }
}
