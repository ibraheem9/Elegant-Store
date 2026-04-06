import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../models/models.dart';

class DatabaseService {
  static Database? _database;
  static const String dbName = 'elegant_store_v2002.db';

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
      final dbPath = await getDatabasesPath();
      path = join(dbPath, dbName);
    }

    final db = await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try { await db.execute('ALTER TABLE payment_methods ADD COLUMN sort_order INTEGER DEFAULT 0'); } catch (e) {}
        }
        if (oldVersion < 3) {
          try { await db.execute('ALTER TABLE users ADD COLUMN nickname TEXT'); } catch (e) {}
          try { await db.execute('ALTER TABLE users ADD COLUMN transfer_names TEXT'); } catch (e) {}
          try { await db.execute('ALTER TABLE users ADD COLUMN notes TEXT'); } catch (e) {}
        }
        if (oldVersion < 4) {
          try { await db.execute("ALTER TABLE invoices ADD COLUMN type TEXT DEFAULT 'SALE'"); } catch (e) {}
        }
      },
    );

    await _clearOldTransactionalData(db);
    
    return db;
  }

  Future<void> _clearOldTransactionalData(Database db) async {
    // هذه الدالة تضمن تنظيف البيانات الحركية فقط عند الحاجة
    // في بيئة الإنتاج، يفضل استدعاؤها يدوياً من الإعدادات
  }

  Future<void> _createTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, password TEXT NOT NULL, email TEXT, name TEXT NOT NULL, nickname TEXT, role TEXT NOT NULL, is_permanent_customer INTEGER DEFAULT 0, credit_limit REAL DEFAULT 0.0, phone TEXT, notes TEXT, transfer_names TEXT, balance REAL DEFAULT 0.0, created_at TEXT NOT NULL, deleted_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS payment_methods (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE NOT NULL, type TEXT NOT NULL, description TEXT, is_active INTEGER DEFAULT 1, sort_order INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, invoice_date TEXT NOT NULL, amount REAL NOT NULL, payment_method_id INTEGER, payment_status TEXT NOT NULL, type TEXT DEFAULT \'SALE\', notes TEXT, created_at TEXT NOT NULL, updated_at TEXT, deleted_at TEXT, FOREIGN KEY(user_id) REFERENCES users(id), FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, buyer_id INTEGER NOT NULL, invoice_id INTEGER, type TEXT NOT NULL, amount REAL NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(buyer_id) REFERENCES users(id), FOREIGN KEY(invoice_id) REFERENCES invoices(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, merchant_name TEXT NOT NULL, amount REAL NOT NULL, payment_source TEXT NOT NULL, payment_method_id INTEGER, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT, deleted_at TEXT, FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS daily_statistics (id INTEGER PRIMARY KEY AUTOINCREMENT, statistic_date TEXT UNIQUE NOT NULL, yesterday_cash_in_box REAL NOT NULL, today_cash_in_box REAL NOT NULL, total_cash_debt_repayment REAL NOT NULL, total_app_debt_repayment REAL NOT NULL, total_cash_purchases REAL NOT NULL, total_app_purchases REAL NOT NULL, total_sales_cash REAL NOT NULL, total_sales_credit REAL NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS edit_history (id INTEGER PRIMARY KEY AUTOINCREMENT, target_id INTEGER, target_type TEXT, field_name TEXT, old_value TEXT, new_value TEXT, edit_reason TEXT, created_at TEXT)');
  }

  Future<void> logEdit(int targetId, String type, String field, String oldVal, String newVal) async {
    final db = await database;
    await db.insert('edit_history', {'target_id': targetId, 'target_type': type, 'field_name': field, 'old_value': oldVal, 'new_value': newVal, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<List<Map<String, dynamic>>> getEditHistory(int targetId, String type) async {
    final db = await database;
    return await db.query('edit_history', where: 'target_id = ? AND target_type = ?', whereArgs: [targetId, type], orderBy: 'created_at DESC');
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final db = await database;
    final r = await db.query('payment_methods', where: 'is_active = 1', orderBy: 'sort_order ASC');
    return r.map((m) => PaymentMethod.fromMap(m)).toList();
  }
  
  Future<int> insertPaymentMethod(PaymentMethod m) async { 
    final db = await database; 
    final existing = await db.query('payment_methods', where: 'name = ?', whereArgs: [m.name]);
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;
      await db.update('payment_methods', {...m.toMap(), 'is_active': 1, 'id': id}, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    var map = m.toMap();
    if (m.sortOrder == 0) {
      final maxSort = Sqflite.firstIntValue(await db.rawQuery('SELECT MAX(sort_order) FROM payment_methods')) ?? 0;
      map['sort_order'] = maxSort + 1;
    }
    return await db.insert('payment_methods', map); 
  }
  
  Future<void> updatePaymentMethod(PaymentMethod m) async { 
    final db = await database; 
    await db.update('payment_methods', m.toMap(), where: 'id = ?', whereArgs: [m.id]); 
  }

  Future<void> deletePaymentMethod(int id) async { 
    final db = await database; 
    await db.update('payment_methods', {'is_active': 0}, where: 'id = ?', whereArgs: [id]); 
  }
  
  Future<void> updatePaymentMethodsOrder(List<PaymentMethod> methods) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < methods.length; i++) {
        await txn.update('payment_methods', {'sort_order': i}, where: 'id = ?', whereArgs: [methods[i].id]);
      }
    });
  }

  Future<User?> authenticate(String u, String p) async {
    final db = await database;
    final r = await db.query('users', where: 'username = ? AND password = ? AND deleted_at IS NULL', whereArgs: [u, p]);
    return r.isNotEmpty ? User.fromMap(r.first) : null;
  }
  
  Future<List<User>> getCustomers() async {
    final db = await database;
    final r = await db.query('users', where: "role = 'customer' COLLATE NOCASE AND deleted_at IS NULL");
    return r.map((m) => User.fromMap(m)).toList();
  }

  Future<int> insertUser(User u, String p) async { 
    final db = await database; 
    var map = u.toMap(); 
    map['password'] = p; 
    map['role'] = 'customer'; 
    return await db.insert('users', map); 
  }

  Future<void> updateUser(User newUser, User oldUser) async {
    final db = await database;
    if (newUser.name != oldUser.name) await logEdit(newUser.id!, 'USER', 'الاسم', oldUser.name, newUser.name);
    if (newUser.phone != oldUser.phone) await logEdit(newUser.id!, 'USER', 'الهاتف', oldUser.phone ?? '', newUser.phone ?? '');
    
    await db.update(
      'users', 
      {
        'name': newUser.name,
        'nickname': newUser.nickname,
        'phone': newUser.phone,
        'is_permanent_customer': newUser.isPermanentCustomer,
        'credit_limit': newUser.creditLimit,
        'balance': newUser.balance,
        'notes': newUser.notes,
        'transfer_names': newUser.transferNames,
      }, 
      where: 'id = ?', 
      whereArgs: [newUser.id]
    );
  }

  Future<bool> hasInvoices(int customerId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM invoices WHERE user_id = ? AND deleted_at IS NULL', [customerId])) ?? 0;
    return count > 0;
  }

  Future<void> softDeleteUser(int id) async {
    final db = await database;
    await db.update('users', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addCredit(int id, double am, String n) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert('transactions', {'buyer_id': id, 'type': 'DEPOSIT', 'amount': am, 'created_at': now});
      await txn.rawUpdate('UPDATE users SET balance = balance + ? WHERE id = ?', [am, id]);
    });
  }

  Future<int> insertInvoice(Invoice inv) async {
    final db = await database;
    return await db.transaction((txn) async {
      final id = await txn.insert('invoices', inv.toMap());
      await txn.rawUpdate('UPDATE users SET balance = balance - ? WHERE id = ?', [inv.amount, inv.userId]);
      return id;
    });
  }

  Future<List<Invoice>> getInvoices({DateTime? start, DateTime? end, String? query}) async {
    final db = await database;
    String where = 'i.deleted_at IS NULL';
    List<dynamic> args = [];
    if (start != null) { where += ' AND i.created_at >= ?'; args.add(start.toIso8601String()); }
    if (end != null) { where += ' AND i.created_at <= ?'; args.add(end.toIso8601String()); }
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.credit_limit as customer_limit, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at DESC', args);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getTodayInvoices() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.credit_limit as customer_limit, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE i.created_at LIKE ? AND i.deleted_at IS NULL ORDER BY i.created_at DESC', ['$today%']);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<List<Invoice>> getCustomerInvoices(int id, {bool unpaidOnly = false}) async {
    final db = await database;
    String where = 'i.user_id = ? AND i.deleted_at IS NULL';
    if (unpaidOnly) where += " AND i.payment_status = 'UNPAID'";
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.phone as phone, u.credit_limit as customer_limit, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at DESC', [id]);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<void> updateInvoice(Invoice i) async { final db = await database; await db.update('invoices', i.toMap(), where: 'id = ?', whereArgs: [i.id]); }

  Future<Map<String, double>> getDetailedTodayStats() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final appDebt = await db.rawQuery('SELECT SUM(i.amount) as t FROM invoices i JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE i.updated_at LIKE ? AND i.payment_status = \'paid\' AND pm.type = \'app\'', ['$today%']);
    final cashPurchases = await db.rawQuery('SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = \'CASH\'', ['$today%']);
    final appPurchases = await db.rawQuery('SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = \'APP\'', ['$today%']);
    return {
      'app_debt_repayment': (appDebt.first['t'] as num?)?.toDouble() ?? 0.0,
      'cash_purchases': (cashPurchases.first['t'] as num?)?.toDouble() ?? 0.0,
      'app_purchases': (appPurchases.first['t'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<Map<String, double>> getMonthlySales(int y, int m) async {
    final db = await database;
    final monthStr = '${y.toString()}-${m.toString().padLeft(2, '0')}';
    final r = await db.rawQuery('SELECT SUBSTR(created_at, 1, 10) as day, SUM(amount) as total FROM invoices WHERE created_at LIKE ? AND deleted_at IS NULL AND type = \'SALE\' GROUP BY day', ['$monthStr%']);
    Map<String, double> result = {};
    for (var row in r) { result[row['day'] as String] = (row['total'] as num).toDouble(); }
    return result;
  }

  Future<int> insertPurchase(Purchase p) async {
    final db = await database;
    return await db.insert('purchases', p.toMap());
  }

  Future<List<Purchase>> getTodayPurchases() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final r = await db.query('purchases', where: 'created_at LIKE ? AND deleted_at IS NULL', whereArgs: ['$today%'], orderBy: 'created_at DESC');
    return r.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<List<Purchase>> getPurchasesByMethod(int methodId) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final r = await db.query('purchases', where: 'payment_method_id = ? AND created_at LIKE ? AND deleted_at IS NULL', whereArgs: [methodId, '$today%'], orderBy: 'created_at DESC');
    return r.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getGlobalStats() async {
    final customers = await getCustomers();
    double totalDebts = 0, totalBalances = 0;
    int permanentCount = 0;
    
    for (var c in customers) { 
      if (c.balance < 0) totalDebts += c.balance.abs(); else totalBalances += c.balance; 
      // حساب الزبائن الدائمين (الذين لديهم سقف دين محدد أو غير محدود)
      if (c.isPermanentCustomer == 1) permanentCount++;
    }
    
    return {
      'total_customers': customers.length, 
      'total_debts': totalDebts, 
      'total_balances': totalBalances, 
      'permanent_count': permanentCount, // هذا هو المفتاح الذي كانت شاشة التقارير تفتقده
      'unpaid_non_permanent_count': 0
    };
  }

  Future<Map<String, dynamic>> getSalesStatsToday() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final s = await db.rawQuery('SELECT SUM(amount) as t FROM invoices WHERE created_at LIKE ? AND deleted_at IS NULL AND type = \'SALE\'', ['$today%']);
    return {'total_sales': (s.first['t'] as num?)?.toDouble() ?? 0.0, 'total_debt': 0.0, 'buyers_count': 0};
  }

  Future<DailyStatistics?> getTodayStatistics() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final r = await db.query('daily_statistics', where: 'statistic_date = ?', whereArgs: [today]);
    return r.isNotEmpty ? DailyStatistics.fromMap(r.first) : null;
  }

  Future<int> insertDailyStatistics(DailyStatistics s) async {
    final db = await database;
    return await db.insert('daily_statistics', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// تسجيل سحب نقدي من الصندوق كدين على المشتري
  Future<void> recordCashWithdrawal({
    required User customer,
    required double amount,
    String? notes,
    int? paymentMethodId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final dateStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now());
      
      // 1. إدراج فاتورة دين غير مدفوعة من نوع سحب
      await txn.insert('invoices', {
        'user_id': customer.id,
        'invoice_date': dateStr,
        'amount': amount,
        'payment_method_id': paymentMethodId,
        'payment_status': 'UNPAID',
        'type': 'WITHDRAWAL',
        'notes': 'سحب نقدي: ${notes ?? ""}',
        'created_at': now,
      });

      // 2. تحديث رصيد المستخدم (خصم المبلغ لزيادة الدين)
      await txn.rawUpdate('UPDATE users SET balance = balance - ? WHERE id = ?', [amount, customer.id!]);

      // 3. إدراج عملية شراء (سحب من الصندوق) لمطابقة الجرد اليومي
      await txn.insert('purchases', {
        'merchant_name': 'سحب نقدي: ${customer.name}',
        'amount': amount,
        'payment_source': 'CASH',
        'notes': 'سحب نقدي كدين للمشتري - ${notes ?? ""}',
        'created_at': now,
      });
    });
  }
}
