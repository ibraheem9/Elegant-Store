import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import 'dart:developer' as dev;

class DatabaseService {
  static Database? _database;
  static const String dbName = 'elegant_store_v300.db'; // HQ Sync Version
  final _uuid = const Uuid();

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

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await _createTables(db);
        await _createTriggers(db);
        await _seedInitialData(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add missing columns for edit_history
          try { await db.execute('ALTER TABLE edit_history ADD COLUMN edited_by_id INTEGER'); } catch (_) {}
          try { await db.execute('ALTER TABLE edit_history ADD COLUMN edited_by_name TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE edit_history ADD COLUMN deleted_at TEXT'); } catch (_) {}
          // Add missing deleted_at for payment_methods, daily_statistics
          try { await db.execute('ALTER TABLE payment_methods ADD COLUMN deleted_at TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE payment_methods ADD COLUMN created_at TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE daily_statistics ADD COLUMN deleted_at TEXT'); } catch (_) {}
        }
        if (oldVersion < 3) {
          // Ensure created_at column exists and backfill NULLs
          try { await db.execute('ALTER TABLE payment_methods ADD COLUMN created_at TEXT'); } catch (_) {}
          final now = DateTime.now().toIso8601String();
          await db.execute(
            "UPDATE payment_methods SET created_at = ? WHERE created_at IS NULL OR created_at = ''",
            [now],
          );
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        parent_id INTEGER,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        email TEXT,
        name TEXT NOT NULL,
        nickname TEXT,
        role TEXT NOT NULL,
        is_permanent_customer INTEGER DEFAULT 0,
        credit_limit REAL DEFAULT 0.0,
        phone TEXT,
        notes TEXT,
        transfer_names TEXT,
        balance REAL DEFAULT 0.0,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_methods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        category TEXT DEFAULT 'SALE',
        description TEXT,
        is_active INTEGER DEFAULT 1,
        sort_order INTEGER DEFAULT 0,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0
      )''');



    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        user_id INTEGER NOT NULL,
        invoice_date TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_amount REAL DEFAULT 0.0,
        payment_method_id INTEGER,
        payment_status TEXT NOT NULL,
        type TEXT DEFAULT 'SALE',
        notes TEXT,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY(user_id) REFERENCES users(id),
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        buyer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        used_amount REAL DEFAULT 0.0,
        payment_method_id INTEGER,
        notes TEXT,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY(buyer_id) REFERENCES users(id),
        FOREIGN KEY(invoice_id) REFERENCES invoices(id),
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        merchant_name TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_source TEXT NOT NULL,
        payment_method_id INTEGER,
        notes TEXT,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY(payment_method_id) REFERENCES payment_methods(id)
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_statistics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        statistic_date TEXT UNIQUE NOT NULL,
        yesterday_cash_in_box REAL NOT NULL,
        today_cash_in_box REAL NOT NULL,
        total_cash_debt_repayment REAL NOT NULL,
        total_app_debt_repayment REAL NOT NULL,
        total_cash_purchases REAL NOT NULL,
        total_app_purchases REAL NOT NULL,
        total_sales_cash REAL NOT NULL,
        total_sales_credit REAL NOT NULL,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS edit_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE NOT NULL,
        store_manager_id INTEGER,
        edited_by_id INTEGER,
        edited_by_name TEXT,
        target_id INTEGER,
        target_type TEXT,
        field_name TEXT,
        old_value TEXT,
        new_value TEXT,
        edit_reason TEXT,
        version INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        is_synced INTEGER DEFAULT 0
      )''');
  }

  Future<void> _createTriggers(Database db) async {
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

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().toIso8601String();
    final initialSaleMethods = [
      {'name': 'نقدي (كاش)', 'type': 'cash', 'sort_order': 1},
      {'name': 'تطبيق بنكي', 'type': 'app', 'sort_order': 2},
      {'name': 'دين (أجل)', 'type': 'deferred', 'sort_order': 3},
      {'name': 'غير مدفوع', 'type': 'unpaid', 'sort_order': 4},
      {'name': 'رصيد المحفظة', 'type': 'credit_balance', 'sort_order': 5},
    ];
    for (var m in initialSaleMethods) {
      await db.insert('payment_methods', {
        'uuid': _uuid.v4(),
        'name': m['name'],
        'type': m['type'],
        'category': 'SALE',
        'sort_order': m['sort_order'],
        'is_active': 1,
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
    }

    final initialPurchaseMethods = [
      {'name': 'كاش من الصندوق', 'type': 'cash', 'sort_order': 1},
      {'name': 'دفع عبر التطبيق', 'type': 'app', 'sort_order': 2},
    ];
    for (var m in initialPurchaseMethods) {
      await db.insert('payment_methods', {
        'uuid': _uuid.v4(),
        'name': m['name'],
        'type': m['type'],
        'category': 'PURCHASE',
        'sort_order': m['sort_order'],
        'is_active': 1,
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
    }
  }

  // --- Methods ---

  Future<User?> authenticate(String username, String password) async {
    final db = await database;
    final r = await db.query('users', where: 'username = ? AND password = ?', whereArgs: [username, password]);
    if (r.isNotEmpty) return User.fromMap(r.first);
    return null;
  }

  Future<List<User>> getCustomers() async {
    final db = await database;
    final r = await db.query('users', where: "role = 'CUSTOMER' AND deleted_at IS NULL");
    return r.map((m) => User.fromMap(m)).toList();
  }

  Future<List<User>> getAccountants() async {
    final db = await database;
    final r = await db.query('users', where: "role = 'ACCOUNTANT' AND deleted_at IS NULL");
    return r.map((m) => User.fromMap(m)).toList();
  }

  Future<int> insertUser(User u, String p) async {
    final db = await database; 
    final now = DateTime.now().toIso8601String();
    var map = u.toMap();
    map.remove('id');
    map['uuid'] = (u.uuid.isEmpty) ? _uuid.v4() : u.uuid;
    map['password'] = p; 
    map['version'] = 1;
    map['created_at'] = now;
    map['updated_at'] = now;
    map['is_synced'] = 0;
    return await db.insert('users', map);
  }
  
  Future<void> updateUser(User newUser, User oldUser) async {
    final db = await database;
    await db.update('users', {
      ...newUser.toMap(),
      'id': newUser.id,
      'version': (oldUser.version) + 1,
      'is_synced': 0,
      'updated_at': DateTime.now().toIso8601String()
    }, where: 'id = ?', whereArgs: [newUser.id]);
  }
  
  Future<void> softDeleteUser(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('users', where: 'id = ?', whereArgs: [id], limit: 1);
    int currentVersion = existing.isNotEmpty ? (existing.first['version'] as int? ?? 0) : 0;
    
    await db.update('users', {
      'deleted_at': now,
      'is_synced': 0,
      'version': currentVersion + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [id]);
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
          int depositId = d['id'] as int;
          double available = (d['amount'] as num).toDouble() - (d['used_amount'] as num).toDouble();
          double deduction = (totalToPay > available) ? available : totalToPay;
          await txn.rawUpdate('UPDATE transactions SET used_amount = used_amount + ?, is_synced = 0, updated_at = ? WHERE id = ?', [deduction, now, depositId]);
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

      var map = inv.toMap();
      map.remove('id');
      map['uuid'] = (inv.uuid.isEmpty) ? _uuid.v4() : inv.uuid;
      map['paid_amount'] = finalPaidAmount;
      map['payment_status'] = finalStatus;
      map['version'] = 1;
      map['created_at'] = now;
      map['updated_at'] = now;
      map['is_synced'] = 0;
      return await txn.insert('invoices', map);
    });
  }

  Future<List<Invoice>> getInvoices({DateTime? start, DateTime? end, String? query, bool deleted = false}) async {
    final db = await database;
    String where = deleted ? 'i.deleted_at IS NOT NULL' : 'i.deleted_at IS NULL';
    List<dynamic> args = [];
    if (start != null) { where += ' AND i.created_at >= ?'; args.add(start.toIso8601String()); }
    if (end != null) { where += ' AND i.created_at <= ?'; args.add(end.toIso8601String()); }
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, u.nickname as customer_nickname, u.is_permanent_customer as customer_is_permanent, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at DESC', args);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<void> softDeleteInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      'deleted_at': now,
      'is_synced': 0,
      'version': inv.version + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> restoreInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      'deleted_at': null,
      'is_synced': 0,
      'version': inv.version + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> permanentDeleteInvoice(int id) async {
    final db = await database;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Invoice>> getCustomerInvoices(int id, {bool unpaidOnly = false}) async {
    final db = await database;
    String where = 'i.user_id = ? AND i.deleted_at IS NULL';
    if (unpaidOnly) where += " AND i.payment_status IN ('UNPAID', 'PARTIAL', 'DEFERRED')";
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at ASC', [id]);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  Future<void> recalculateAllBalances() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate("UPDATE users SET balance = 0.0 WHERE role = 'CUSTOMER'");
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
        WHERE role = 'CUSTOMER'
      ''');
    });
  }

  Future<Map<String, dynamic>> getGlobalStats() async {
    final db = await database;
    final customersCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM users WHERE role = 'CUSTOMER' AND deleted_at IS NULL")) ?? 0;
    final customers = await getCustomers();
    double totalDebts = 0;
    double totalDeposits = 0;
    for (var c in customers) {
      if (c.balance > 0) totalDebts += c.balance;
      else if (c.balance < 0) totalDeposits += c.balance.abs();
    }
    final unpaidNonPermanentCount = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*) FROM users 
      WHERE role = 'CUSTOMER' 
      AND is_permanent_customer = 0 
      AND balance > 0 
      AND deleted_at IS NULL
    ''')) ?? 0;

    return {
      'total_customers': customersCount,
      'total_debts': totalDebts,
      'total_balances': totalDeposits,
      'unpaid_non_permanent_count': unpaidNonPermanentCount,
    };
  }

  Future<User?> getLastSyncedUser() async {
    final db = await database;
    final r = await db.query('users', where: 'deleted_at IS NULL', orderBy: 'updated_at DESC', limit: 1);
    return r.isNotEmpty ? User.fromMap(r.first) : null;
  }

  Future<Invoice?> getLastSyncedInvoice() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT i.*, u.name as customer_name
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      WHERE i.deleted_at IS NULL
      ORDER BY i.updated_at DESC
      LIMIT 1
    ''');
    return r.isNotEmpty ? Invoice.fromMap(r.first) : null;
  }

  String normalizeArabic(String text) {
    String normalized = text;
    normalized = normalized.replaceAll(RegExp(r'[أإآا]'), 'ا');
    normalized = normalized.replaceAll(RegExp(r'[ة]'), 'ه');
    normalized = normalized.replaceAll(RegExp(r'[ىيئ]'), 'ي');
    return normalized.toLowerCase().trim();
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
      final invId = await txn.insert('invoices', {
        'uuid': _uuid.v4(),
        'user_id': userId,
        'invoice_date': dateStr,
        'amount': amount,
        'paid_amount': amount,
        'payment_status': 'PAID',
        'payment_method_id': paymentMethodId,
        'type': 'DEPOSIT',
        'notes': 'دفع مقدم (إيداع رصيد): ${notes ?? ""}',
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
      await txn.insert('transactions', {
        'uuid': _uuid.v4(),
        'buyer_id': userId,
        'invoice_id': invId,
        'type': 'DEPOSIT',
        'amount': amount,
        'used_amount': 0.0,
        'payment_method_id': paymentMethodId,
        'notes': notes,
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
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
    final now = DateTime.now().toIso8601String();
    var map = m.toMap();
    map.remove('id');
    map['uuid'] = (m.uuid.isEmpty) ? _uuid.v4() : m.uuid;
    map['version'] = 1;
    map.putIfAbsent('created_at', () => now);
    map['updated_at'] = now;
    map['is_synced'] = 0;
    return await db.insert('payment_methods', map);
  }

  Future<int> updatePaymentMethod(PaymentMethod m) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.update('payment_methods', {
      ...m.toMap(),
      'version': m.version + 1,
      'updated_at': now,
      'is_synced': 0
    }, where: 'id = ?', whereArgs: [m.id]);
  }

  Future<int> deletePaymentMethod(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('payment_methods', where: 'id = ?', whereArgs: [id], limit: 1);
    int currentVersion = existing.isNotEmpty ? (existing.first['version'] as int? ?? 0) : 0;

    return await db.update('payment_methods', {
      'is_active': 0,
      'is_synced': 0,
      'version': currentVersion + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updatePaymentMethodsOrder(List<PaymentMethod> methods) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (int i = 0; i < methods.length; i++) {
        await txn.update('payment_methods', {
          'sort_order': i,
          'version': methods[i].version + 1,
          'updated_at': now,
          'is_synced': 0
        }, where: 'id = ?', whereArgs: [methods[i].id]);
      }
    });
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

  Future<void> recordCashWithdrawal({required User customer, required double amount, String? notes, int? paymentMethodId}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final dateStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(DateTime.now());
      await txn.insert('invoices', {
        'uuid': _uuid.v4(),
        'user_id': customer.id,
        'invoice_date': dateStr,
        'amount': amount,
        'paid_amount': 0.0,
        'payment_status': 'UNPAID',
        'type': 'WITHDRAWAL',
        'notes': 'سحب نقدي: ${notes ?? ""}',
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
      await txn.insert('purchases', {
        'uuid': _uuid.v4(),
        'merchant_name': 'سحب نقدي: ${customer.name}',
        'amount': amount,
        'payment_source': 'CASH',
        'notes': 'سحب نقدي كدين للمشتري - ${notes ?? ""}',
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'is_synced': 0
      });
    });
  }

  Future<void> updateInvoiceWithLog({required Invoice oldInv, required Invoice newInv, required String reason}) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.update('invoices', {
        ...newInv.toMap(),
        'version': newInv.version + 1,
        'updated_at': now,
        'is_synced': 0
      }, where: 'id = ?', whereArgs: [newInv.id]);

      if (oldInv.amount != newInv.amount) {
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'target_id': newInv.id,
          'target_type': 'INVOICE',
          'field_name': 'amount',
          'old_value': oldInv.amount.toString(),
          'new_value': newInv.amount.toString(),
          'edit_reason': reason,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getEditHistory(int targetId, String type) async {
    final db = await database;
    return await db.query('edit_history', where: 'target_id = ? AND target_type = ?', whereArgs: [targetId, type], orderBy: 'created_at DESC');
  }

  /// [date] defaults to today if null.
  Future<Map<String, double>> getDetailedTodayStats({DateTime? date}) async {
    final today = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
    final db = await database;

    // إجمالي المبيعات على التطبيق = كل الفواتير المدفوعة (PAID) بطريقة دفع بنكي (app)
    // تشمل فواتير البيع وفواتير تسديد الديون
    final appSalesQuery = await db.rawQuery(
      '''SELECT SUM(i.amount) as t FROM invoices i
         JOIN payment_methods pm ON i.payment_method_id = pm.id
         WHERE i.created_at LIKE ? AND i.payment_status IN ('PAID','paid')
         AND pm.type = 'app' AND i.deleted_at IS NULL''',
      ['$today%'],
    );
    final double appSalesTotal = (appSalesQuery.first['t'] as num?)?.toDouble() ?? 0.0;

    // إجمالي الفواتير غير المدفوعة بطريقة بنكي (UNPAID / دين آجل)
    final appUnpaidQuery = await db.rawQuery(
      '''SELECT SUM(i.amount) as t FROM invoices i
         JOIN payment_methods pm ON i.payment_method_id = pm.id
         WHERE i.created_at LIKE ? AND i.payment_status IN ('UNPAID','pending','PARTIAL')
         AND pm.type = 'app' AND i.deleted_at IS NULL''',
      ['$today%'],
    );
    final double appUnpaidTotal = (appUnpaidQuery.first['t'] as num?)?.toDouble() ?? 0.0;

    // إجمالي الدين على التطبيق = الفواتير غير المدفوعة بنكي - إجمالي المبيعات على التطبيق
    // إذا كانت النتيجة سالبة تُعرض صفر (معناه المبيعات المدفوعة تغطي كل الديون)
    final double appDebt = (appUnpaidTotal - appSalesTotal).clamp(0.0, double.infinity);

    // إجمالي الديون الكاش = إجمالي السحب الكاش
    final cashWithdrawals = await db.rawQuery(
      "SELECT SUM(amount) as t FROM invoices WHERE created_at LIKE ? AND type = 'WITHDRAWAL' AND deleted_at IS NULL",
      ['$today%'],
    );

    // المشتريات
    final cashPurchases = await db.rawQuery(
      "SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = 'CASH'",
      ['$today%'],
    );
    final appPurchases = await db.rawQuery(
      "SELECT SUM(amount) as t FROM purchases WHERE created_at LIKE ? AND payment_source = 'APP'",
      ['$today%'],
    );

    return {
      'app_sales':        appSalesTotal,
      'app_debt':         appDebt,
      'cash_withdrawals': (cashWithdrawals.first['t'] as num?)?.toDouble() ?? 0.0,
      'cash_purchases':   (cashPurchases.first['t'] as num?)?.toDouble() ?? 0.0,
      'app_purchases':    (appPurchases.first['t'] as num?)?.toDouble() ?? 0.0,
      // legacy key
      'app_debt_repayment': appSalesTotal,
    };
  }

  /// [date] defaults to today if null.
  Future<DailyStatistics?> getTodayStatistics({DateTime? date}) async {
    final today = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
    final db = await database;
    final r = await db.query('daily_statistics', where: 'statistic_date = ?', whereArgs: [today]);
    return r.isNotEmpty ? DailyStatistics.fromMap(r.first) : null;
  }

  /// Returns the today_cash_in_box saved for the day before [date] (defaults to yesterday).
  Future<double> getYesterdayCashInBox({DateTime? date}) async {
    final ref = date ?? DateTime.now();
    final yesterday = DateFormat('yyyy-MM-dd').format(ref.subtract(const Duration(days: 1)));
    final db = await database;
    final r = await db.query('daily_statistics',
        columns: ['today_cash_in_box'],
        where: 'statistic_date = ?',
        whereArgs: [yesterday]);
    if (r.isNotEmpty) {
      return (r.first['today_cash_in_box'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<int> insertDailyStatistics(DailyStatistics stats) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var map = stats.toMap();
    map.remove('id');
    map['uuid'] = (stats.uuid.isEmpty) ? _uuid.v4() : stats.uuid;
    map['version'] = 1;
    map['updated_at'] = now;
    map['is_synced'] = 0;
    return await db.insert('daily_statistics', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, double>> getMonthlySales(int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final r = await db.rawQuery('''
      SELECT day, SUM(daily_total) as daily_total FROM (
        SELECT SUBSTR(i.created_at, 1, 10) as day, SUM(i.amount) as daily_total
        FROM invoices i
        JOIN payment_methods pm ON i.payment_method_id = pm.id
        WHERE i.type = 'SALE' AND i.deleted_at IS NULL AND i.payment_status = 'PAID'
        AND pm.type IN ('cash', 'app') AND i.created_at BETWEEN ? AND ?
        GROUP BY day
        UNION ALL
        SELECT SUBSTR(t.created_at, 1, 10) as day, SUM(t.amount) as daily_total
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
    final r = await db.query('purchases', where: where, whereArgs: args, orderBy: 'created_at DESC');
    return r.map((m) => Purchase.fromMap(m)).toList();
  }

  Future<int> insertPurchase(Purchase p) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    var map = p.toMap();
    map.remove('id');
    map['uuid'] = (p.uuid.isEmpty) ? _uuid.v4() : p.uuid;
    map['version'] = 1;
    map['updated_at'] = now;
    map['is_synced'] = 0;
    return await db.insert('purchases', map);
  }

  Future<void> updatePurchase(Purchase p) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'purchases',
      {
        ...p.toMap(),
        'version': p.version + 1,
        'is_synced': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  Future<void> updateInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      ...inv.toMap(),
      'version': inv.version + 1,
      'is_synced': 0,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
  }

  Future<void> logEdit(int targetId, String type, String field, String oldVal, String newVal) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('edit_history', {
      'uuid': _uuid.v4(),
      'target_id': targetId,
      'target_type': type,
      'field_name': field,
      'old_value': oldVal,
      'new_value': newVal,
      'version': 1,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0
    });
  }

  Future<void> resetSyncStatus() async {
    final db = await database;
    final tables = ['users', 'payment_methods', 'invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history'];
    await db.transaction((txn) async {
      for (var table in tables) {
        await txn.update(table, {'is_synced': 0});
      }
    });
  }

  // --- Sync Helpers ---

  Future<void> fixLocalDataOwnership(User currentUser) async {
    final db = await database;
    final int? managerId = currentUser.getStoreManagerIdLocal();
    if (managerId == null) return;

    await db.transaction((txn) async {
      await txn.rawUpdate('''
        UPDATE users SET
          parent_id = ?,
          is_synced = 0,
          updated_at = ?
        WHERE id != ? AND role = 'CUSTOMER'
      ''', [managerId, DateTime.now().toIso8601String(), managerId]);

      final storeTables = ['payment_methods', 'invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history'];
      for (var table in storeTables) {
        final tableInfo = await txn.rawQuery('PRAGMA table_info($table)');
        if (tableInfo.any((col) => col['name'] == 'store_manager_id')) {
          await txn.update(table,
            {'store_manager_id': managerId, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
            where: 'store_manager_id IS NULL OR store_manager_id = 0'
          );
        }
      }
    });
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      final tables = ['invoices', 'transactions', 'purchases', 'daily_statistics', 'edit_history', 'payment_methods', 'users'];
      for (var table in tables) {
        await txn.delete(table);
      }
    });
    dev.log('All data cleared from mobile database.', name: 'DatabaseService');
  }

  /// Full reset: delete all rows, reset AUTOINCREMENT counters, and VACUUM.
  /// Used to fix sync corruption or start fresh.
  Future<void> clearAllDataAndReset() async {
    final db = await database;
    await db.transaction((txn) async {
      final tables = [
        'daily_statistics',
        'edit_history',
        'invoices',
        'payment_methods',
        'purchases',
        'transactions',
        'users',
      ];
      for (final table in tables) {
        await txn.rawDelete('DELETE FROM $table');
      }
      // Reset all AUTOINCREMENT counters
      await txn.rawDelete('DELETE FROM sqlite_sequence');
    });
    // Reclaim disk space outside of transaction
    await db.rawQuery('VACUUM');
    dev.log('Full database reset completed.', name: 'DatabaseService');
  }

  /// Returns the count of unsynced records per table for the sync details screen.
  Future<Map<String, int>> getUnsyncedCounts() async {
    final db = await database;
    final tables = [
      'users', 'invoices', 'transactions', 'purchases',
      'payment_methods', 'daily_statistics', 'edit_history',
    ];
    final Map<String, int> counts = {};
    for (final table in tables) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $table WHERE is_synced = 0',
      );
      counts[table] = result.first['cnt'] as int? ?? 0;
    }
    return counts;
  }

  /// Returns total record counts per table.
  Future<Map<String, int>> getTotalCounts() async {
    final db = await database;
    final tables = [
      'users', 'invoices', 'transactions', 'purchases',
      'payment_methods',
    ];
    final Map<String, int> counts = {};
    for (final table in tables) {
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $table');
      counts[table] = result.first['cnt'] as int? ?? 0;
    }
    return counts;
  }

  /// Returns customers whose name appears more than once (local duplicates).
  Future<List<Map<String, dynamic>>> getDuplicateCustomers() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT name, COUNT(*) as count
      FROM users
      WHERE role = 'CUSTOMER'
      GROUP BY name
      HAVING COUNT(*) > 1
      ORDER BY count DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getUnsynced(String table) async {
    final db = await database;
    return await db.query(table, where: 'is_synced = 0');
  }

  Future<void> markAsSynced(String table, List<String> uuids) async {
    final db = await database;
    if (uuids.isEmpty) return;
    await db.update(table, {'is_synced': 1}, where: 'uuid IN (${uuids.map((_) => '?').join(',')})', whereArgs: uuids);
  }

  Future<int> upsertFromSync(String table, Map<String, dynamic> data) async {
    final db = await database;
    return await db.transaction((txn) async {
      return await upsertFromSyncInTxn(table, data, txn);
    });
  }

  Future<int> upsertFromSyncInTxn(String table, Map<String, dynamic> data, dynamic txn) async {
    final uuid = data['uuid'];
    if (uuid == null) return -1;

    final sanitizedData = Map<String, dynamic>.from(data);
    sanitizedData.remove('id');
    sanitizedData['is_synced'] = 1;

    // Strip fields that don't exist in the local SQLite table to prevent errors
    final tableInfo = await txn.rawQuery('PRAGMA table_info($table)');
    final validColumns = tableInfo.map((col) => col['name'] as String).toSet();
    sanitizedData.removeWhere((key, _) => !validColumns.contains(key));

    // SQLite only supports num, String, and Uint8List — convert booleans to 0/1
    sanitizedData.updateAll((key, value) {
      if (value is bool) return value ? 1 : 0;
      return value;
    });

    // Determine if the server is marking this record as deleted
    final bool isDeletedOnServer = sanitizedData['deleted_at'] != null &&
        sanitizedData['deleted_at'].toString().isNotEmpty;

    // 1. Try to find by UUID (including soft-deleted rows)
    final existing = await txn.rawQuery(
      'SELECT * FROM $table WHERE uuid = ? LIMIT 1',
      [uuid],
    );

    if (existing.isNotEmpty) {
      final existingId = existing.first['id'] as int;
      final existingVersion = existing.first['version'] as int? ?? 0;
      final incomingVersion = sanitizedData['version'] as int? ?? 0;

      if (incomingVersion >= existingVersion) {
        // Preserve local password — never overwrite with server hash
        if (table == 'users') {
          sanitizedData.remove('password');
        }
        await txn.update(table, sanitizedData, where: 'id = ?', whereArgs: [existingId]);
      }
      return existingId;
    } else {
      // 2. For users: also try matching by username to handle UUID changes
      if (table == 'users') {
        final byUsername = await txn.rawQuery(
          'SELECT * FROM $table WHERE username = ? LIMIT 1',
          [sanitizedData['username']],
        );
        if (byUsername.isNotEmpty) {
          final existingId = byUsername.first['id'] as int;
          sanitizedData.remove('password');
          await txn.update(table, sanitizedData, where: 'id = ?', whereArgs: [existingId]);
          return existingId;
        }
      }

      // 3. Insert new record — skip if server is telling us it is deleted
      // (no point creating a record locally that is already deleted on server)
      if (isDeletedOnServer) return -1;

      if (table == 'users') {
        // Assign a safe local password; real auth goes through the server token
        sanitizedData['password'] = sanitizedData['password'] ?? '***';
      }
      return await txn.insert(table, sanitizedData);
    }
  }
}
