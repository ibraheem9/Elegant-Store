import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/models.dart';

class DatabaseService {
  static Database? _database;
  static const String dbName = 'elegant_store_v1000.db';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    String path;
    if (Platform.isWindows) {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final storeDirectory = Directory(join(documentsDirectory.path, 'ElegantStoreApp'));
      if (!await storeDirectory.exists()) await storeDirectory.create(recursive: true);
      path = join(storeDirectory.path, dbName);
    } else {
      path = join(await getDatabasesPath(), dbName);
    }

    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );

    // حقن البيانات فوراً وبشكل إجباري إذا كانت الجداول فارغة
    await _forcePopulateData(db);

    return db;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE, password TEXT, email TEXT, name TEXT, role TEXT, is_permanent_customer INTEGER DEFAULT 0, credit_limit REAL DEFAULT 0.0, phone TEXT, notes TEXT, balance REAL DEFAULT 0.0, created_at TEXT, deleted_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS payment_methods (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, type TEXT NOT NULL, description TEXT, is_active INTEGER DEFAULT 1)');
    await db.execute('CREATE TABLE IF NOT EXISTS invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER, invoice_date TEXT, amount REAL, payment_method_id INTEGER, payment_status TEXT, notes TEXT, created_at TEXT, updated_at TEXT, deleted_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, buyer_id INTEGER, invoice_id INTEGER, type TEXT, amount REAL, created_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, merchant_name TEXT, amount REAL, payment_source TEXT, payment_method_id INTEGER, notes TEXT, created_at TEXT, deleted_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS daily_statistics (id INTEGER PRIMARY KEY AUTOINCREMENT, statistic_date TEXT UNIQUE, yesterday_cash_in_box REAL, today_cash_in_box REAL, total_cash_debt_repayment REAL, total_app_debt_repayment REAL, total_cash_purchases REAL, total_app_purchases REAL, total_sales_cash REAL, total_sales_credit REAL, created_at TEXT)');
  }

  Future<void> _forcePopulateData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // 1. التأكد من وجود طرق الدفع
    final methodsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM payment_methods')) ?? 0;
    if (methodsCount == 0) {
      final methods = [
        {'name': 'كاش', 'type': 'cash'},
        {'name': 'Ibraheem App', 'type': 'app'},
        {'name': 'Hamoda App', 'type': 'app'},
        {'name': 'أجل (دين)', 'type': 'deferred'},
        {'name': 'رصيد المحفظة', 'type': 'credit_balance'},
      ];
      for (var m in methods) await db.insert('payment_methods', m);
    }

    // 2. التأكد من وجود الحسابات والزبائن
    final usersCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;
    if (usersCount == 0) {
      await db.insert('users', {'username': 'ibraheem', 'password': '123', 'name': 'إبراهيم عبد الهادي', 'role': 'SUPER_ADMIN', 'created_at': now});
      await db.insert('users', {'username': 'hamoda', 'password': '123', 'name': 'محمد ياغي (حمودة)', 'role': 'ACCOUNTANT', 'created_at': now});

      // زبائن تجريبيين
      await db.insert('users', {'username': 'c1', 'password': '123', 'name': 'أحمد محمود ياغي', 'role': 'CUSTOMER', 'is_permanent_customer': 1, 'credit_limit': 2000.0, 'balance': -500.0, 'phone': '0599111222', 'created_at': now});
      await db.insert('users', {'username': 'c2', 'password': '123', 'name': 'سارة إبراهيم', 'role': 'CUSTOMER', 'is_permanent_customer': 1, 'credit_limit': 500.0, 'balance': 300.0, 'phone': '0598333444', 'created_at': now});
    }
  }

  Future<User?> authenticate(String u, String p) async {
    final db = await database;
    final r = await db.query('users', where: 'username = ? AND password = ?', whereArgs: [u, p]);
    return r.isNotEmpty ? User.fromMap(r.first) : null;
  }

  Future<List<User>> getCustomers() async {
    final db = await database;
    final r = await db.query('users', where: "role = 'CUSTOMER'");
    return r.map((m) => User.fromMap(m)).toList();
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final db = await database;
    return (await db.query('payment_methods')).map((m) => PaymentMethod.fromMap(m)).toList();
  }

  Future<int> insertInvoice(Invoice inv) async {
    final db = await database;
    return await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('invoices', inv.toMap());
      await txn.insert('transactions', {'buyer_id': inv.userId, 'invoice_id': id, 'type': 'INVOICE_CHARGE', 'amount': inv.amount, 'created_at': now});
      await txn.rawUpdate('UPDATE users SET balance = balance - ? WHERE id = ?', [inv.amount, inv.userId]);
      return id;
    });
  }

  Future<List<Invoice>> getTodayInvoices() async {
    final db = await database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE i.created_at LIKE ? ORDER BY i.created_at DESC', ['$today%']);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getSalesStatsToday() async {
    final db = await database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final s = await db.rawQuery('SELECT SUM(amount) as t FROM invoices WHERE created_at LIKE ?', ['$today%']);
    return {'total_sales': (s.first['t'] as num?)?.toDouble() ?? 0.0, 'total_debt': 0.0, 'buyers_count': 0};
  }

  // --- دوال placeholders لمنع الأخطاء ---
  Future<List<Invoice>> getInvoices({DateTime? start, DateTime? end, String? query}) async {
    final db = await database;
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id ORDER BY i.created_at DESC');
    return r.map((m) => Invoice.fromMap(m)).toList();
  }
  Future<double> getCustomerDebt(int id) async => 0.0;
  Future<List<Invoice>> getCustomerInvoices(int id, {bool unpaidOnly = false}) async => [];
  Future<int> insertUser(User u, String p) async { final db = await database; var m = u.toMap(); m['password'] = p; m['role'] = 'CUSTOMER'; return await db.insert('users', m); }
  Future<Map<String, dynamic>> getGlobalStats() async => {'total_customers': 0, 'total_debts': 0.0, 'total_balances': 0.0, 'unpaid_non_permanent_count': 0};
  Future<void> addCredit(int id, double am, String n) async {}
  Future<Map<String, double>> getDetailedTodayStats() async => {};
  Future<Map<String, double>> getMonthlySales(int y, int m) async => {};
  Future<int> insertDailyStatistics(DailyStatistics s) async => 0;
  Future<DailyStatistics?> getTodayStatistics() async => null;
  Future<void> updateInvoice(Invoice i) async {}
  Future<int> insertPurchase(Purchase p) async => 0;
  Future<List<Purchase>> getTodayPurchases() async => [];
  Future<List<Purchase>> getPurchasesByMethod(String n) async => [];
}
