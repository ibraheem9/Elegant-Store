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
      version: 15,
      onCreate: (db, version) async {
        await _createTables(db);
        await _createTriggers(db);
        await _seedInitialData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Force refresh triggers to fix replacement bugs
        await db.execute('DROP TRIGGER IF EXISTS trg_invoice_insert');
        await db.execute('DROP TRIGGER IF EXISTS trg_invoice_update');
        await db.execute('DROP TRIGGER IF EXISTS trg_invoice_delete');
        
        await _createTriggers(db);
        await recalculateAllBalances(db);
      },
    );

    return db;
  }

  Future<void> _createTriggers(Database db) async {
    // Template with placeholders that are absolutely unique and won't match partial strings
    const String insertSql = "(CASE WHEN new.type IN ('SALE', 'WITHDRAWAL') THEN (new.amount - new.paid_amount) WHEN new.type = 'DEPOSIT' THEN (-new.amount) ELSE 0 END)";
    const String oldSql = "(CASE WHEN old.type IN ('SALE', 'WITHDRAWAL') THEN (old.amount - old.paid_amount) WHEN old.type = 'DEPOSIT' THEN (-old.amount) ELSE 0 END)";
    const String updateNewSql = "(CASE WHEN new.type IN ('SALE', 'WITHDRAWAL') THEN (new.amount - new.paid_amount) WHEN new.type = 'DEPOSIT' THEN (-new.amount) ELSE 0 END)";

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_invoice_insert AFTER INSERT ON invoices
      WHEN (new.deleted_at IS NULL)
      BEGIN
        UPDATE users SET balance = balance + $insertSql
        WHERE id = new.user_id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_invoice_update AFTER UPDATE ON invoices
      BEGIN
        UPDATE users SET balance = balance - $oldSql
        WHERE id = old.user_id AND old.deleted_at IS NULL;
        
        UPDATE users SET balance = balance + $updateNewSql
        WHERE id = new.user_id AND new.deleted_at IS NULL;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS trg_invoice_delete AFTER DELETE ON invoices
      BEGIN
        UPDATE users SET balance = balance - $oldSql
        WHERE id = old.user_id AND old.deleted_at IS NULL;
      END;
    ''');
  }

  Future<void> recalculateAllBalances([Database? dbInstance]) async {
    final db = dbInstance ?? await database;
    await db.transaction((txn) async {
      await txn.rawUpdate("UPDATE users SET balance = 0.0 WHERE role = 'customer'");
      await txn.rawUpdate('''
        UPDATE users SET balance = (
          SELECT COALESCE(SUM(
            CASE 
              WHEN type IN ('SALE', 'WITHDRAWAL') THEN (amount - paid_amount)
              WHEN type = 'DEPOSIT' THEN (-amount)
              ELSE 0 
            END
          ), 0)
          FROM invoices 
          WHERE user_id = users.id AND deleted_at IS NULL
        )
        WHERE role = 'customer'
      ''');
    });
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().toIso8601String();
    final users = await db.query('users', where: 'username = ?', whereArgs: ['admin']);
    if (users.isEmpty) {
      await db.insert('users', {'username': 'admin', 'password': '123', 'name': 'المدير العام', 'role': 'SUPER_ADMIN', 'created_at': now, 'balance': 0.0});
    }
    final accountants = await db.query('users', where: 'username = ?', whereArgs: ['accountant']);
    if (accountants.isEmpty) {
      await db.insert('users', {'username': 'accountant', 'password': '123', 'name': 'المحاسب', 'role': 'ACCOUNTANT', 'created_at': now, 'balance': 0.0});
    }
    final developers = await db.query('users', where: 'username = ?', whereArgs: ['dev']);
    if (developers.isEmpty) {
      await db.insert('users', {'username': 'dev', 'password': 'dev', 'name': 'Developer (Reset)', 'role': 'DEVELOPER', 'created_at': now, 'balance': 0.0});
    }

    final saleMethods = await db.query('payment_methods', where: 'category = ?', whereArgs: ['SALE']);
    if (saleMethods.isEmpty) {
      final initialSaleMethods = [
        {'name': 'نقدي (كاش)', 'type': 'cash', 'sort_order': 1},
        {'name': 'تطبيق بنكي', 'type': 'app', 'sort_order': 2},
        {'name': 'دين (أجل)', 'type': 'deferred', 'sort_order': 3},
        {'name': 'غير مدفوع', 'type': 'unpaid', 'sort_order': 4},
        {'name': 'رصيد المحفظة', 'type': 'credit_balance', 'sort_order': 5},
      ];
      for (var m in initialSaleMethods) {
        await db.insert('payment_methods', {'name': m['name'], 'type': m['type'], 'category': 'SALE', 'sort_order': m['sort_order'], 'is_active': 1});
      }
    }

    final purchaseMethods = await db.query('payment_methods', where: 'category = ?', whereArgs: ['PURCHASE']);
    if (purchaseMethods.isEmpty) {
      final initialPurchaseMethods = [
        {'name': 'كاش من الصندوق', 'type': 'cash', 'sort_order': 1},
        {'name': 'دفع عبر التطبيق', 'type': 'app', 'sort_order': 2},
      ];
      for (var m in initialPurchaseMethods) {
        await db.insert('payment_methods', {'name': m['name'], 'type': m['type'], 'category': 'PURCHASE', 'sort_order': m['sort_order'], 'is_active': 1});
      }
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, password TEXT NOT NULL, email TEXT, name TEXT NOT NULL, nickname TEXT, role TEXT NOT NULL, is_permanent_customer INTEGER DEFAULT 0, credit_limit REAL DEFAULT 0.0, phone TEXT, notes TEXT, transfer_names TEXT, balance REAL DEFAULT 0.0, created_at TEXT NOT NULL, deleted_at TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS payment_methods (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL, category TEXT DEFAULT \'SALE\', description TEXT, is_active INTEGER DEFAULT 1, sort_order INTEGER DEFAULT 0)');
    await db.execute('CREATE TABLE IF NOT EXISTS invoices (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, invoice_date TEXT NOT NULL, amount REAL NOT NULL, paid_amount REAL DEFAULT 0.0, payment_method_id INTEGER, payment_status TEXT NOT NULL, type TEXT DEFAULT \'SALE\', notes TEXT, created_at TEXT NOT NULL, updated_at TEXT, deleted_at TEXT, FOREIGN KEY(user_id) REFERENCES users(id), FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, buyer_id INTEGER NOT NULL, invoice_id INTEGER, type TEXT NOT NULL, amount REAL NOT NULL, used_amount REAL DEFAULT 0.0, payment_method_id INTEGER, notes TEXT, created_at TEXT NOT NULL, FOREIGN KEY(buyer_id) REFERENCES users(id), FOREIGN KEY(invoice_id) REFERENCES invoices(id), FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, merchant_name TEXT NOT NULL, amount REAL NOT NULL, payment_source TEXT NOT NULL, payment_method_id INTEGER, notes TEXT, created_at TEXT NOT NULL, updated_at TEXT, deleted_at TEXT, FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id))');
    await db.execute('CREATE TABLE IF NOT EXISTS daily_statistics (id INTEGER PRIMARY KEY AUTOINCREMENT, statistic_date TEXT UNIQUE NOT NULL, yesterday_cash_in_box REAL NOT NULL, today_cash_in_box REAL NOT NULL, total_cash_debt_repayment REAL NOT NULL, total_app_debt_repayment REAL NOT NULL, total_cash_purchases REAL NOT NULL, total_app_purchases REAL NOT NULL, total_sales_cash REAL NOT NULL, total_sales_credit REAL NOT NULL, created_at TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS edit_history (id INTEGER PRIMARY KEY AUTOINCREMENT, target_id INTEGER, target_type TEXT, field_name TEXT, old_value TEXT, new_value TEXT, edit_reason TEXT, created_at TEXT)');
  }

  String normalizeArabic(String text) {
    String normalized = text;
    normalized = normalized.replaceAll(RegExp(r'[أإآا]'), 'ا');
    normalized = normalized.replaceAll(RegExp(r'[ة]'), 'ه');
    normalized = normalized.replaceAll(RegExp(r'[ىيئ]'), 'ي');
    return normalized.toLowerCase().trim();
  }

  Future<User?> authenticate(String username, String password) async {
    final db = await database;
    final r = await db.query('users', where: 'username = ? AND password = ?', whereArgs: [username, password]);
    if (r.isNotEmpty) return User.fromMap(r.first);
    return null;
  }

  Future<List<User>> getCustomers() async {
    final db = await database;
    final r = await db.query('users', where: "role = 'customer' AND deleted_at IS NULL");
    return r.map((m) => User.fromMap(m)).toList();
  }

  Future<int> insertUser(User u, String p) async { 
    final db = await database; 
    var map = u.toMap(); map['password'] = p; map['role'] = 'customer'; 
    return await db.insert('users', map); 
  }
  Future<void> updateUser(User newUser, User oldUser) async {
    final db = await database;
    await db.update('users', {'name': newUser.name, 'nickname': newUser.nickname, 'phone': newUser.phone, 'is_permanent_customer': newUser.isPermanentCustomer, 'credit_limit': newUser.creditLimit, 'notes': newUser.notes, 'transfer_names': newUser.transferNames}, where: 'id = ?', whereArgs: [newUser.id]);
  }
  Future<void> softDeleteUser(int id) async {
    final db = await database;
    await db.update('users', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }
  Future<bool> hasInvoices(int customerId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM invoices WHERE user_id = ? AND deleted_at IS NULL', [customerId])) ?? 0;
    return count > 0;
  }

  Future<void> addCredit({required int userId, required double amount, String? notes, required int paymentMethodId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final dateStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now());
      final invId = await txn.insert('invoices', {'user_id': userId, 'invoice_date': dateStr, 'amount': amount, 'paid_amount': amount, 'payment_status': 'PAID', 'payment_method_id': paymentMethodId, 'type': 'DEPOSIT', 'notes': 'دفع مقدم (إيداع رصيد): ${notes ?? ""}', 'created_at': now});
      await txn.insert('transactions', {'buyer_id': userId, 'invoice_id': invId, 'type': 'DEPOSIT', 'amount': amount, 'used_amount': 0.0, 'payment_method_id': paymentMethodId, 'notes': notes, 'created_at': now});
    });
  }

  Future<int> insertInvoice(Invoice inv) async {
    final db = await database;
    return await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      String methodType = 'unpaid';
      if (inv.paymentMethodId != null) {
        final pm = await txn.query('payment_methods', columns: ['type'], where: 'id = ?', whereArgs: [inv.paymentMethodId]);
        if (pm.isNotEmpty) methodType = pm.first['type'] as String;
      }
      double totalToPay = inv.amount;
      double amountFromBalance = 0;
      final user = await txn.query('users', columns: ['balance'], where: 'id = ?', whereArgs: [inv.userId]);
      double currentBalance = (user.first['balance'] as num).toDouble();
      if (currentBalance < 0 && inv.type == 'SALE') {
        final deposits = await txn.query('transactions', where: "buyer_id = ? AND type = 'DEPOSIT' AND amount > used_amount", whereArgs: [inv.userId], orderBy: 'created_at ASC');
        for (var d in deposits) {
          if (totalToPay <= 0) break;
          double depositId = (d['id'] as num).toDouble();
          double available = (d['amount'] as num).toDouble() - (d['used_amount'] as num).toDouble();
          double deduction = (totalToPay > available) ? available : totalToPay;
          await txn.rawUpdate('UPDATE transactions SET used_amount = used_amount + ? WHERE id = ?', [deduction, depositId]);
          amountFromBalance += deduction;
          totalToPay -= deduction;
        }
      }
      String finalStatus = inv.paymentStatus;
      double finalPaidAmount = amountFromBalance;
      if (methodType == 'cash' || methodType == 'app') {
        finalPaidAmount = inv.amount; 
        finalStatus = 'PAID';
      } else {
        if (totalToPay <= 0) {
          finalStatus = 'PAID';
          finalPaidAmount = inv.amount;
        } else if (amountFromBalance > 0) {
          finalStatus = 'PARTIAL';
        }
      }
      return await txn.insert('invoices', {...inv.toMap(), 'paid_amount': finalPaidAmount, 'payment_status': finalStatus, 'updated_at': now});
    });
  }

  Future<void> updateInvoice(Invoice inv) async {
    final db = await database;
    await db.update('invoices', inv.toMap(), where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> updateInvoiceWithLog({required Invoice oldInv, required Invoice newInv, required String reason}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.update('invoices', {...newInv.toMap(), 'updated_at': now}, where: 'id = ?', whereArgs: [newInv.id]);
      if (oldInv.amount != newInv.amount) {
        await txn.insert('edit_history', {'target_id': newInv.id, 'target_type': 'INVOICE', 'field_name': 'amount', 'old_value': oldInv.amount.toString(), 'new_value': newInv.amount.toString(), 'edit_reason': reason, 'created_at': now});
      }
    });
  }

  Future<void> logEdit(int targetId, String type, String field, String oldVal, String newVal) async {
    final db = await database;
    await db.insert('edit_history', {'target_id': targetId, 'target_type': type, 'field_name': field, 'old_value': oldVal, 'new_value': newVal, 'created_at': DateTime.now().toIso8601String()});
  }

  Future<void> processBulkPayment({required int userId, required double amountPaid, required int paymentMethodId, String? notes}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final unpaidInvoices = await txn.rawQuery("SELECT * FROM invoices WHERE user_id = ? AND deleted_at IS NULL AND payment_status IN ('UNPAID', 'PARTIAL', 'DEFERRED') ORDER BY created_at ASC", [userId]);
      double remainingPayment = amountPaid;
      for (var row in unpaidInvoices) {
        if (remainingPayment <= 0) break;
        final inv = Invoice.fromMap(row);
        double debtRemaining = inv.amount - inv.paidAmount;
        if (remainingPayment >= debtRemaining) {
          await txn.update('invoices', {'paid_amount': inv.amount, 'payment_status': 'PAID', 'payment_method_id': paymentMethodId, 'updated_at': now}, where: 'id = ?', whereArgs: [inv.id]);
          remainingPayment -= debtRemaining;
        } else {
          await txn.update('invoices', {'paid_amount': inv.paidAmount + remainingPayment, 'payment_status': 'PARTIAL', 'payment_method_id': paymentMethodId, 'updated_at': now}, where: 'id = ?', whereArgs: [inv.id]);
          remainingPayment = 0;
        }
      }
      await txn.insert('transactions', {'buyer_id': userId, 'type': 'DEBT_PAYMENT', 'amount': amountPaid, 'payment_method_id': paymentMethodId, 'notes': notes, 'created_at': now});
    });
  }

  Future<List<PaymentMethod>> getPaymentMethods({String? category}) async {
    final db = await database;
    String where = 'is_active = 1'; List<dynamic> args = [];
    if (category != null) { where += ' AND category = ?'; args.add(category); }
    final r = await db.query('payment_methods', where: where, whereArgs: args, orderBy: 'sort_order ASC');
    return r.map((m) => PaymentMethod.fromMap(m)).toList();
  }

  Future<int> insertPaymentMethod(PaymentMethod m) async {
    final db = await database;
    return await db.insert('payment_methods', m.toMap());
  }

  Future<int> updatePaymentMethod(PaymentMethod m) async {
    final db = await database;
    return await db.update('payment_methods', m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> deletePaymentMethod(int id) async {
    final db = await database;
    return await db.update('payment_methods', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePaymentMethodsOrder(List<PaymentMethod> methods) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < methods.length; i++) {
        await txn.update('payment_methods', {'sort_order': i}, where: 'id = ?', whereArgs: [methods[i].id]);
      }
    });
  }

  Future<List<Invoice>> getInvoices({DateTime? start, DateTime? end, String? query, bool deleted = false}) async {
    final db = await database;
    String where = deleted ? 'i.deleted_at IS NOT NULL' : 'i.deleted_at IS NULL';
    List<dynamic> args = [];
    if (start != null) { where += ' AND i.created_at >= ?'; args.add(start.toIso8601String()); }
    if (end != null) { where += ' AND i.created_at <= ?'; args.add(end.toIso8601String()); }
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.credit_limit as customer_limit, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at DESC', args);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<void> softDeleteInvoice(Invoice inv) async {
    final db = await database;
    await db.update('invoices', {'deleted_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> restoreInvoice(Invoice inv) async {
    final db = await database;
    await db.update('invoices', {'deleted_at': null}, where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> permanentDeleteInvoice(int id) async {
    final db = await database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Invoice>> getCustomerInvoices(int id, {bool unpaidOnly = false}) async {
    final db = await database;
    String where = 'i.user_id = ? AND i.deleted_at IS NULL';
    if (unpaidOnly) where += " AND i.payment_status IN ('UNPAID', 'PARTIAL', 'DEFERRED')";
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.phone as phone, u.credit_limit as customer_limit, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at ASC', [id]);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<Map<String, dynamic>> getSalesStats({DateTime? start, DateTime? end}) async {
    final db = await database;
    String where = "deleted_at IS NULL AND type = 'SALE'";
    List<dynamic> args = [];
    if (start != null) { where += ' AND created_at >= ?'; args.add(start.toIso8601String()); }
    if (end != null) { where += ' AND created_at <= ?'; args.add(end.toIso8601String()); }
    final salesResult = await db.rawQuery("SELECT SUM(amount) as t FROM invoices WHERE $where", args);
    final debtResult = await db.rawQuery("SELECT SUM(amount - paid_amount) as t FROM invoices WHERE $where AND payment_status != 'PAID'", args);
    final buyersResult = await db.rawQuery("SELECT COUNT(DISTINCT user_id) as t FROM invoices WHERE $where", args);
    return {'total_sales': (salesResult.first['t'] as num?)?.toDouble() ?? 0.0, 'total_debt': (debtResult.first['t'] as num?)?.toDouble() ?? 0.0, 'buyers_count': buyersResult.first['t'] ?? 0};
  }

  Future<Map<String, dynamic>> getGlobalStats() async {
    final db = await database;
    final customers = await db.rawQuery("SELECT COUNT(*) as count FROM users WHERE role = 'customer' AND deleted_at IS NULL");
    final allCustomers = await getCustomers();
    double totalDebts = 0;
    double totalDeposits = 0;
    for (var c in allCustomers) {
      if (c.balance > 0) totalDebts += c.balance;
      else if (c.balance < 0) totalDeposits += c.balance.abs();
    }
    return {'total_customers': customers.first['count'] ?? 0, 'total_debts': totalDebts, 'total_balances': totalDeposits};
  }

  Future<void> recordCashWithdrawal({required User customer, required double amount, String? notes, int? paymentMethodId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final dateStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now());
      await txn.insert('invoices', {'user_id': customer.id, 'invoice_date': dateStr, 'amount': amount, 'paid_amount': 0.0, 'payment_method_id': paymentMethodId, 'payment_status': 'UNPAID', 'type': 'WITHDRAWAL', 'notes': 'سحب نقدي: ${notes ?? ""}', 'created_at': now});
      await txn.insert('purchases', {'merchant_name': 'سحب نقدي: ${customer.name}', 'amount': amount, 'payment_source': 'CASH', 'notes': 'سحب نقدي كدين للمشتري - ${notes ?? ""}', 'created_at': now});
    });
  }

  Future<List<Map<String, dynamic>>> getEditHistory(int targetId, String type) async {
    final db = await database;
    return await db.query('edit_history', where: 'target_id = ? AND target_type = ?', whereArgs: [targetId, type], orderBy: 'created_at DESC');
  }

  Future<Map<String, double>> getDetailedTodayStats() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final appDebt = await db.rawQuery('SELECT SUM(i.amount) as t FROM invoices i JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE i.updated_at LIKE ? AND i.payment_status = \'PAID\' AND pm.type = \'app\'', ['$today%']);
    final cashPurchases = await db.rawQuery('SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = \'CASH\'', ['$today%']);
    final appPurchases = await db.rawQuery('SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = \'APP\'', ['$today%']);
    final cashWithdrawals = await db.rawQuery("SELECT SUM(amount) as t FROM invoices WHERE created_at LIKE ? AND type = 'WITHDRAWAL'", ['$today%']);
    return {'app_debt_repayment': (appDebt.first['t'] as num?)?.toDouble() ?? 0.0, 'cash_purchases': (cashPurchases.first['t'] as num?)?.toDouble() ?? 0.0, 'app_purchases': (appPurchases.first['t'] as num?)?.toDouble() ?? 0.0, 'cash_withdrawals': (cashWithdrawals.first['t'] as num?)?.toDouble() ?? 0.0};
  }

  Future<DailyStatistics?> getTodayStatistics() async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final db = await database;
    final r = await db.query('daily_statistics', where: 'statistic_date = ?', whereArgs: [today]);
    return r.isNotEmpty ? DailyStatistics.fromMap(r.first) : null;
  }

  Future<int> insertDailyStatistics(DailyStatistics stats) async {
    final db = await database;
    return await db.insert('daily_statistics', stats.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, double>> getMonthlySales(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final r = await db.rawQuery('''
      SELECT day, SUM(total) as daily_total FROM (
        SELECT SUBSTR(i.created_at, 1, 10) as day, SUM(i.amount) as total 
        FROM invoices i 
        JOIN payment_methods pm ON i.payment_method_id = pm.id 
        WHERE i.type = 'SALE' AND i.deleted_at IS NULL AND i.payment_status = 'PAID' 
        AND pm.type IN ('cash', 'app') AND i.created_at BETWEEN ? AND ?
        GROUP BY day
        UNION ALL
        SELECT SUBSTR(t.created_at, 1, 10) as day, SUM(t.amount) as total
        FROM transactions t
        JOIN payment_methods pm ON t.payment_method_id = pm.id
        WHERE t.type IN ('DEBT_PAYMENT', 'DEPOSIT') 
        AND pm.type IN ('cash', 'app') AND t.created_at BETWEEN ? AND ?
        GROUP BY day
      ) GROUP BY day
    ''', [start, end, start, end]);
    Map<String, double> result = {};
    for (var row in r) { result[row['day'] as String] = (row['daily_total'] as num).toDouble(); }
    return result;
  }

  Future<List<Purchase>> getPurchasesByMethod(int methodId, {DateTime? start, DateTime? end}) async {
    final db = await database;
    String where = 'payment_method_id = ? AND deleted_at IS NULL';
    List<dynamic> args = [methodId];
    if (start != null) { where += ' AND created_at >= ?'; args.add(start.toIso8601String()); }
    if (end != null) { where += ' AND created_at <= ?'; args.add(end.toIso8601String()); }
    final r = await db.query('purchases', where: where, whereArgs: args, orderBy: 'sort_order DESC');
    return r.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<int> insertPurchase(Purchase p) async {
    final db = await database;
    return await db.insert('purchases', p.toMap());
  }

  Future<List<Purchase>> getTodayPurchases() async {
    final db = await database;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final r = await db.query('purchases', where: "created_at LIKE ? AND deleted_at IS NULL", whereArgs: ["$today%"]);
    return r.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<void> resetAllTransactions([Database? dbInstance]) async {
    final db = dbInstance ?? await database;
    await db.transaction((txn) async {
      await txn.delete('invoices');
      await txn.delete('transactions');
      await txn.delete('purchases');
      await txn.delete('daily_statistics');
      await txn.delete('edit_history');
      await txn.rawUpdate('UPDATE users SET balance = 0.0');
    });
  }

  Future<void> factoryReset() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('invoices');
      await txn.delete('transactions');
      await txn.delete('purchases');
      await txn.delete('daily_statistics');
      await txn.delete('edit_history');
      await txn.delete('payment_methods');
      await txn.delete('users', where: "role = 'customer'");
      await txn.rawUpdate('UPDATE users SET balance = 0.0');
    });
    await _seedInitialData(db);
  }
}
