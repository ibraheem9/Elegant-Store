import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
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
        daily_cash_income REAL NOT NULL,
        total_cash_debt_repayment REAL NOT NULL,
        total_app_debt_repayment REAL NOT NULL,
        total_cash_purchases REAL NOT NULL,
        total_app_purchases REAL NOT NULL,
        total_purchases REAL NOT NULL,
        total_daily_sales REAL NOT NULL,
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

    // Debt reminders table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS debt_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        debt_amount REAL NOT NULL,
        reminder_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    ''');

    // Populate initial data
    await _populateInitialData(db);
  }

  Future<void> _populateInitialData(Database db) async {
    // Check if data already exists
    final userCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM users'),
    );

    if (userCount! > 0) return;

    // Insert users
    final users = [
      {
        'username': 'hamoda',
        'email': 'hamoda@store.com',
        'name': 'Hamoda Ahmed',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'eldaj',
        'email': 'eldaj@store.com',
        'name': 'El Daj',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'ahmed_yaghi',
        'email': 'ahmed@store.com',
        'name': 'Ahmed Yaghi',
        'role': 'accountant',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'ibrahim_manager',
        'email': 'ibrahim@store.com',
        'name': 'Ibrahim Manager',
        'role': 'manager',
        'is_permanent_customer': 0,
        'credit_limit': null,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'customer_hassan',
        'email': 'hassan@customer.com',
        'name': 'Hassan',
        'role': 'customer',
        'is_permanent_customer': 1,
        'credit_limit': 100.0,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'customer_ali',
        'email': 'ali@customer.com',
        'name': 'Ali',
        'role': 'customer',
        'is_permanent_customer': 1,
        'credit_limit': 150.0,
        'created_at': DateTime.now().toIso8601String(),
      },
      {
        'username': 'customer_fatima',
        'email': 'fatima@customer.com',
        'name': 'Fatima',
        'role': 'customer',
        'is_permanent_customer': 1,
        'credit_limit': 200.0,
        'created_at': DateTime.now().toIso8601String(),
      },
    ];

    for (var user in users) {
      await db.insert('users', user);
    }

    // Insert payment methods
    final paymentMethods = [
      {
        'name': 'كاش',
        'type': 'cash',
        'description': 'دفع نقدي',
        'is_active': 1,
      },
      {
        'name': 'تطبيق الراجحي',
        'type': 'app',
        'description': 'تطبيق البنك الراجحي',
        'is_active': 1,
      },
      {
        'name': 'تطبيق الأهلي',
        'type': 'app',
        'description': 'تطبيق البنك الأهلي',
        'is_active': 1,
      },
      {
        'name': 'تطبيق الرياض',
        'type': 'app',
        'description': 'تطبيق بنك الرياض',
        'is_active': 1,
      },
      {
        'name': 'تطبيق الإنماء',
        'type': 'app',
        'description': 'تطبيق بنك الإنماء',
        'is_active': 1,
      },
      {
        'name': 'تطبيق الفرنسي',
        'type': 'app',
        'description': 'تطبيق البنك الفرنسي',
        'is_active': 1,
      },
      {
        'name': 'أمازون',
        'type': 'app',
        'description': 'محفظة أمازون',
        'is_active': 1,
      },
      {
        'name': 'أجل',
        'type': 'deferred',
        'description': 'دفع مؤجل',
        'is_active': 1,
      },
    ];

    for (var method in paymentMethods) {
      await db.insert('payment_methods', method);
    }

    // Insert sample invoices
    await db.insert('invoices', {
      'user_id': 5,
      'invoice_date': DateTime.now().toIso8601String(),
      'amount': 100.0,
      'notes': 'فاتورة اختبار',
      'payment_status': 'pending',
      'payment_method_id': 1,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.insert('invoices', {
      'user_id': 6,
      'invoice_date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      'amount': 150.0,
      'notes': 'فاتورة سابقة',
      'payment_status': 'paid',
      'payment_method_id': 2,
      'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    });
  }

  // User operations
  Future<User?> getUserByUsername(String username) async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );
    return result.isNotEmpty ? User.fromMap(result.first) : null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await database;
    final result = await db.query('users');
    return result.map((map) => User.fromMap(map)).toList();
  }

  Future<List<User>> getCustomers() async {
    final db = await database;
    final result = await db.query(
      'users',
      where: 'role = ?',
      whereArgs: ['customer'],
    );
    return result.map((map) => User.fromMap(map)).toList();
  }

  // Invoice operations
  Future<int> insertInvoice(Invoice invoice) async {
    final db = await database;
    return await db.insert('invoices', invoice.toMap());
  }

  Future<List<Invoice>> getInvoices() async {
    final db = await database;
    final result = await db.query('invoices', orderBy: 'created_at DESC');
    return result.map((map) => Invoice.fromMap(map)).toList();
  }

  Future<List<Invoice>> getTodayInvoices() async {
    final db = await database;
    final today = DateTime.now().toString().split(' ')[0];
    final result = await db.query(
      'invoices',
      where: "DATE(created_at) = ?",
      whereArgs: [today],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => Invoice.fromMap(map)).toList();
  }

  Future<List<Invoice>> getPendingInvoices() async {
    final db = await database;
    final result = await db.query(
      'invoices',
      where: 'payment_status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => Invoice.fromMap(map)).toList();
  }

  Future<void> updateInvoiceStatus(int id, String status) async {
    final db = await database;
    await db.update(
      'invoices',
      {'payment_status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Purchase operations
  Future<int> insertPurchase(Purchase purchase) async {
    final db = await database;
    return await db.insert('purchases', purchase.toMap());
  }

  Future<List<Purchase>> getPurchases() async {
    final db = await database;
    final result = await db.query('purchases', orderBy: 'created_at DESC');
    return result.map((map) => Purchase.fromMap(map)).toList();
  }

  Future<List<Purchase>> getTodayPurchases() async {
    final db = await database;
    final today = DateTime.now().toString().split(' ')[0];
    final result = await db.query(
      'purchases',
      where: "DATE(created_at) = ?",
      whereArgs: [today],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => Purchase.fromMap(map)).toList();
  }

  // Payment method operations
  Future<List<PaymentMethod>> getPaymentMethods() async {
    final db = await database;
    final result = await db.query(
      'payment_methods',
      where: 'is_active = ?',
      whereArgs: [1],
    );
    return result.map((map) => PaymentMethod.fromMap(map)).toList();
  }

  // Statistics operations
  Future<int> insertDailyStatistics(DailyStatistics stats) async {
    final db = await database;
    return await db.insert('daily_statistics', stats.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DailyStatistics?> getTodayStatistics() async {
    final db = await database;
    final today = DateTime.now().toString().split(' ')[0];
    final result = await db.query(
      'daily_statistics',
      where: 'statistic_date = ?',
      whereArgs: [today],
      limit: 1,
    );
    return result.isNotEmpty ? DailyStatistics.fromMap(result.first) : null;
  }

  // Customer debt operations
  Future<double> getCustomerDebt(int userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM invoices WHERE user_id = ? AND payment_status = ?',
      [userId, 'pending'],
    );
    return result.isNotEmpty ? (result.first['total'] as num?)?.toDouble() ?? 0.0 : 0.0;
  }

  // Customer payment operations
  Future<int> insertCustomerPayment(CustomerPayment payment) async {
    final db = await database;
    return await db.insert('customer_payments', payment.toMap());
  }

  Future<List<CustomerPayment>> getCustomerPayments(int userId) async {
    final db = await database;
    final result = await db.query(
      'customer_payments',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => CustomerPayment.fromMap(map)).toList();
  }

  // Debt reminder operations
  Future<int> insertDebtReminder(DebtReminder reminder) async {
    final db = await database;
    return await db.insert('debt_reminders', reminder.toMap());
  }

  Future<List<DebtReminder>> getDebtReminders() async {
    final db = await database;
    final result = await db.query('debt_reminders', orderBy: 'created_at DESC');
    return result.map((map) => DebtReminder.fromMap(map)).toList();
  }

  // Close database
  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
}
