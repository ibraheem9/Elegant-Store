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

    final db = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await _createTables(db);
        await _createTriggers(db);
        await _createIndexes(db);
        // Seed the developer account so the developer can always log in locally.
        await _seedDeveloperAccount(db);
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
        if (oldVersion < 4) {
          // Add yesterday_cash_in_box to daily_statistics if missing
          try { await db.execute('ALTER TABLE daily_statistics ADD COLUMN yesterday_cash_in_box REAL NOT NULL DEFAULT 0'); } catch (_) {}
        }
        if (oldVersion < 5) {
          // Add store_manager_id to users table if missing (added after v1)
          try { await db.execute('ALTER TABLE users ADD COLUMN store_manager_id INTEGER'); } catch (_) {}
          // Add performance indexes for existing databases
          await _createIndexes(db);
        }
        if (oldVersion < 6) {
          // Add action (CREATE/UPDATE/DELETE) and summary columns to edit_history
          try { await db.execute('ALTER TABLE edit_history ADD COLUMN action TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE edit_history ADD COLUMN summary TEXT'); } catch (_) {}
          // Backfill existing rows as UPDATE actions
          try { await db.execute("UPDATE edit_history SET action = 'UPDATE' WHERE action IS NULL"); } catch (_) {}
        }
      },
    );
    // Apply performance PRAGMAs AFTER the database is fully open.
    // sqflite does not allow db.execute() inside onOpen callbacks;
    // rawQuery is used here because it works outside transaction context.
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
      await db.rawQuery('PRAGMA cache_size = -4000');
    } catch (e) {
      dev.log('PRAGMA setup skipped: $e', name: 'DatabaseService');
    }
    return db;
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
        action TEXT,
        field_name TEXT,
        old_value TEXT,
        new_value TEXT,
        edit_reason TEXT,
        summary TEXT,
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

  // _seedInitialData removed — fresh installs start with an empty database.

  /// Creates performance indexes on frequently-queried columns.
  /// Uses IF NOT EXISTS so it is safe to call on existing databases during upgrade.
  Future<void> _createIndexes(Database db) async {
    // Each index is wrapped in try-catch so a missing column on an old DB
    // schema never blocks the migration or the app startup.
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_inv_user_id    ON invoices(user_id)',
      'CREATE INDEX IF NOT EXISTS idx_inv_created_at ON invoices(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_inv_deleted_at ON invoices(deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_inv_status     ON invoices(payment_status)',
      'CREATE INDEX IF NOT EXISTS idx_inv_type       ON invoices(type)',
      'CREATE INDEX IF NOT EXISTS idx_inv_pm_id      ON invoices(payment_method_id)',
      'CREATE INDEX IF NOT EXISTS idx_usr_role       ON users(role)',
      'CREATE INDEX IF NOT EXISTS idx_usr_deleted_at ON users(deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_txn_buyer_id   ON transactions(buyer_id)',
      'CREATE INDEX IF NOT EXISTS idx_txn_invoice_id ON transactions(invoice_id)',
      'CREATE INDEX IF NOT EXISTS idx_txn_deleted_at ON transactions(deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_pur_created_at ON purchases(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_pur_pm_id      ON purchases(payment_method_id)',
      'CREATE INDEX IF NOT EXISTS idx_pur_deleted_at ON purchases(deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_edh_target     ON edit_history(target_id, target_type)',
      'CREATE INDEX IF NOT EXISTS idx_dstat_date     ON daily_statistics(statistic_date)',
    ];
    for (final sql in indexes) {
      try {
        await db.execute(sql);
      } catch (e) {
        dev.log('Index creation skipped (column may not exist yet): $e', name: 'DatabaseService');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SEED
  // ─────────────────────────────────────────────────────────────────────────

  /// Seeds the developer account into the local DB on a fresh install.
  /// Uses INSERT OR IGNORE so it never overwrites an existing record.
  /// Password is stored as plain text (same as the offline-login mechanism).
  Future<void> _seedDeveloperAccount(Database db) async {
    const String devUuid = 'dev-ibraheem-abd-elhadi-00000000-0001';
    const String now = '2026-01-01T00:00:00.000';
    await db.execute('''
      INSERT OR IGNORE INTO users (
        uuid, username, password, name, email,
        role, version, created_at, updated_at, is_synced
      ) VALUES (
        ?, 'ibraheem', '123', 'Ibraheem Abd Elhadi', 'i7r10k8@gmail.com',
        'DEVELOPER', 1, ?, ?, 1
      )
    ''', [devUuid, now, now]);
    dev.log('Developer account seeded (or already exists).', name: 'DatabaseService');
  }

  // --- Methods ----
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

  // ── Paginated customers ──────────────────────────────────────────────────

  /// Returns [pageSize] customers starting at [offset], filtered by [query].
  Future<List<User>> getCustomersPaged({
    int offset = 0,
    int pageSize = 20,
    String query = '',
  }) async {
    final db = await database;
    final q = normalizeArabic(query.trim());
    if (q.isEmpty) {
      final r = await db.query(
        'users',
        where: "role = 'CUSTOMER' AND deleted_at IS NULL",
        orderBy: 'name ASC',
        limit: pageSize,
        offset: offset,
      );
      return r.map((m) => User.fromMap(m)).toList();
    }
    final like = '%$q%';
    final r = await db.rawQuery(
      '''
      SELECT * FROM users
      WHERE role = 'CUSTOMER' AND deleted_at IS NULL
        AND (
          REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name,
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
          OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(nickname,''),
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
          OR COALESCE(phone,'') LIKE ?
          OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(transfer_names,''),
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
        )
      ORDER BY name ASC
      LIMIT ? OFFSET ?
      ''',
      [like, like, like, like, pageSize, offset],
    );
    return r.map((m) => User.fromMap(m)).toList();
  }

  /// Total count of customers matching [query] — used to know when to stop loading.
  Future<int> getCustomersCount({String query = ''}) async {
    final db = await database;
    final q = normalizeArabic(query.trim());
    if (q.isEmpty) {
      final r = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM users WHERE role = 'CUSTOMER' AND deleted_at IS NULL",
      );
      return Sqflite.firstIntValue(r) ?? 0;
    }
    final like = '%$q%';
    final r = await db.rawQuery(
      '''
      SELECT COUNT(*) as cnt FROM users
      WHERE role = 'CUSTOMER' AND deleted_at IS NULL
        AND (
          REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(name,
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
          OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(nickname,''),
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
          OR COALESCE(phone,'') LIKE ?
          OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(transfer_names,''),
            'أ','ا'),'إ','ا'),'آ','ا'),'ة','ه'),'ى','ي'),'ئ','ي'),'ؤ','و'),'ء','') LIKE ?
        )
      ''',
      [like, like, like, like],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ── Paginated customer invoices ───────────────────────────────────────────

  /// Returns [pageSize] invoices for a customer starting at [offset].
  Future<List<Invoice>> getCustomerInvoicesPaged(
    int userId, {
    int offset = 0,
    int pageSize = 20,
  }) async {
    final db = await database;
    final r = await db.rawQuery(
      '''
      SELECT i.*, u.name as customer_name, pm.name as method_name
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id
      WHERE i.user_id = ? AND i.deleted_at IS NULL
      ORDER BY i.created_at DESC
      LIMIT ? OFFSET ?
      ''',
      [userId, pageSize, offset],
    );
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  /// Total invoice count for a customer.
  Future<int> getCustomerInvoicesCount(int userId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM invoices WHERE user_id = ? AND deleted_at IS NULL',
      [userId],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ── Paginated paid invoices (payments review screen) ─────────────────────

  /// Returns [pageSize] paid invoices starting at [offset].
  /// Optionally filters by [methodId] and date range.
  Future<List<Invoice>> getPaidInvoicesPaged({
    int offset = 0,
    int pageSize = 20,
    int? methodId,
    DateTime? start,
    DateTime? end,
  }) async {
    final db = await database;
    String where =
        "i.deleted_at IS NULL AND (i.payment_status = 'PAID' OR i.payment_status = 'paid') AND i.type != 'WITHDRAWAL'";
    final List<dynamic> args = [];
    if (methodId != null) {
      where += ' AND i.payment_method_id = ?';
      args.add(methodId);
    }
    if (start != null) {
      where += ' AND i.created_at >= ?';
      args.add(start.toIso8601String());
    }
    if (end != null) {
      where += ' AND i.created_at <= ?';
      args.add(end.toIso8601String());
    }
    args.addAll([pageSize, offset]);
    final r = await db.rawQuery(
      '''
      SELECT i.*, u.name as customer_name, u.nickname as customer_nickname,
             u.is_permanent_customer as customer_is_permanent,
             pm.name as method_name
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id
      WHERE $where
      ORDER BY i.created_at DESC
      LIMIT ? OFFSET ?
      ''',
      args,
    );
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  /// Total count of paid invoices matching the given filters.
  Future<int> getPaidInvoicesCount({
    int? methodId,
    DateTime? start,
    DateTime? end,
  }) async {
    final db = await database;
    String where =
        "deleted_at IS NULL AND (payment_status = 'PAID' OR payment_status = 'paid') AND type != 'WITHDRAWAL'";
    final List<dynamic> args = [];
    if (methodId != null) {
      where += ' AND payment_method_id = ?';
      args.add(methodId);
    }
    if (start != null) {
      where += ' AND created_at >= ?';
      args.add(start.toIso8601String());
    }
    if (end != null) {
      where += ' AND created_at <= ?';
      args.add(end.toIso8601String());
    }
    final r = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM invoices WHERE $where',
      args,
    );
    return Sqflite.firstIntValue(r) ?? 0;
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
        // When deposit credit is consumed, the deposit invoice already reduced the balance
        // by its full amount via the insert trigger. We must add back the consumed portion
        // so the balance correctly reflects the remaining credit.
        // Example: deposit of 150 → balance = -150. Consuming 100 → balance should be -50.
        if (amountFromBalance > 0) {
          await txn.rawUpdate(
            'UPDATE users SET balance = balance + ?, updated_at = ? WHERE id = ?',
            [amountFromBalance, now, inv.userId],
          );
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
        }
        // No partial payment support — invoice remains UNPAID if not fully covered by credit
      }

      var map = inv.toMap();
      map.remove('id');
      map['uuid'] = (inv.uuid.isEmpty) ? _uuid.v4() : inv.uuid;
      map['paid_amount'] = finalPaidAmount;
      map['payment_status'] = finalStatus;
      map['version'] = 1;
      // Preserve the accountant's manually entered date if provided; fall back to now.
      map['created_at'] = (inv.createdAt.isNotEmpty) ? inv.createdAt : now;
      // On insert, updated_at matches created_at (accountant's date).
      map['updated_at'] = map['created_at'];
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
    final r = await db.rawQuery('''
      SELECT i.*,
        u.name AS customer_name,
        u.nickname AS customer_nickname,
        u.is_permanent_customer AS customer_is_permanent,
        pm.name AS method_name,
        (
          SELECT eh.edited_by_name
          FROM edit_history eh
          WHERE eh.target_id = i.id
            AND eh.target_type = 'INVOICE'
            AND eh.edited_by_name IS NOT NULL
          ORDER BY eh.created_at DESC
          LIMIT 1
        ) AS last_edited_by
      FROM invoices i
      JOIN users u ON i.user_id = u.id
      LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id
      WHERE $where
      ORDER BY i.created_at DESC
    ''', args);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  /// Soft-deletes an invoice and immediately recalculates the owner's balance.
  /// This ensures that deleting a DEPOSIT invoice removes its credit effect
  /// and deleting a SALE/WITHDRAWAL invoice removes its debt effect.
  Future<void> softDeleteInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      'deleted_at': now,
      'is_synced': 0,
      'version': inv.version + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
    // Always recalculate balance after delete so the customer's balance
    // reflects the removal of this invoice's financial effect.
    await recalculateUserBalance(inv.userId);
  }

  /// Restores a soft-deleted invoice and immediately recalculates the owner's balance.
  /// This ensures that restoring a DEPOSIT invoice re-applies its credit effect
  /// and restoring a SALE/WITHDRAWAL invoice re-applies its debt effect.
  Future<void> restoreInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      'deleted_at': null,
      'is_synced': 0,
      'version': inv.version + 1,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
    // Always recalculate balance after restore so the customer's balance
    // reflects the re-inclusion of this invoice's financial effect.
    await recalculateUserBalance(inv.userId);
  }

  /// SAFE-HOUSE: Marks the invoice as unsynced (is_synced = 0) so the next
  /// push will send its deleted_at tombstone to the server before we erase
  /// the record locally. The server will soft-delete it, preserving all data.
  Future<void> markInvoiceUnsyncedBeforePermanentDelete(int id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE invoices SET is_synced = 0 WHERE id = ?',
      [id],
    );
  }

  Future<void> permanentDeleteInvoice(int id) async {
    final db = await database;
    // Fetch userId before deleting so we can recalculate balance afterwards
    final rows = await db.query('invoices', columns: ['user_id'], where: 'id = ?', whereArgs: [id], limit: 1);
    final userId = rows.isNotEmpty ? rows.first['user_id'] as int? : null;
    await db.delete('invoices', where: 'id = ?', whereArgs: [id]);
    if (userId != null) await recalculateUserBalance(userId);
  }

  /// Soft-deletes a customer together with all their invoices and transactions.
  /// Used when the user wants to delete a customer that still has financial records.
  Future<void> softDeleteCustomerWithInvoices(int customerId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      // Soft-delete all active invoices for this customer
      await txn.rawUpdate(
        'UPDATE invoices SET deleted_at = ?, is_synced = 0, version = version + 1, updated_at = ? WHERE user_id = ? AND deleted_at IS NULL',
        [now, now, customerId],
      );
      // Soft-delete all active transactions for this customer
      await txn.rawUpdate(
        'UPDATE transactions SET deleted_at = ?, is_synced = 0, version = version + 1, updated_at = ? WHERE buyer_id = ? AND deleted_at IS NULL',
        [now, now, customerId],
      );
      // Soft-delete the customer (balance becomes 0 since all invoices are deleted)
      final existing = await txn.query('users', columns: ['version'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      final currentVersion = existing.isNotEmpty ? (existing.first['version'] as int? ?? 0) : 0;
      await txn.update('users', {
        'deleted_at': now,
        'is_synced': 0,
        'version': currentVersion + 1,
        'updated_at': now,
        'balance': 0.0,
      }, where: 'id = ?', whereArgs: [customerId]);
    });
  }

  Future<List<Invoice>> getCustomerInvoices(int id, {bool unpaidOnly = false}) async {
    final db = await database;
    String where = 'i.user_id = ? AND i.deleted_at IS NULL';
    if (unpaidOnly) where += " AND i.payment_status IN ('UNPAID', 'DEFERRED')";
    final r = await db.rawQuery('SELECT i.*, u.name as customer_name, pm.name as method_name FROM invoices i JOIN users u ON i.user_id = u.id LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id WHERE $where ORDER BY i.created_at ASC', [id]);
    return r.map((m) => Invoice.fromMap(m)).toList();
  }

  /// Recalculates the balance for a **single** customer.
  /// Use this after any operation that affects only one customer (add/edit/delete invoice).
  /// This is O(1) per customer instead of O(N) for all customers.
  Future<void> recalculateUserBalance(int userId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE users SET balance = (
        SELECT COALESCE(SUM(
          CASE
            WHEN i.type IN ('SALE', 'WITHDRAWAL') THEN (i.amount - i.paid_amount)
            WHEN i.type = 'DEPOSIT' THEN
              -(
                i.amount - COALESCE((
                  SELECT SUM(t.used_amount)
                  FROM transactions t
                  WHERE t.invoice_id = i.id AND t.deleted_at IS NULL
                ), 0)
              )
            ELSE 0
          END
        ), 0)
        FROM invoices i
        WHERE i.user_id = ? AND i.deleted_at IS NULL
      )
      WHERE id = ?
    ''', [userId, userId]);
  }

  /// Recalculates balances for ALL customers.
  /// Only needed after a full sync where multiple customers may be affected.
  Future<void> recalculateAllBalances() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.rawUpdate("UPDATE users SET balance = 0.0 WHERE role = 'CUSTOMER'");
      // For DEPOSIT invoices, we subtract only the REMAINING (unconsumed) credit.
      // The consumed portion is tracked in transactions.used_amount linked by invoice_id.
      await txn.rawUpdate('''
        UPDATE users SET balance = (
          SELECT COALESCE(SUM(
            CASE
              WHEN i.type IN ('SALE', 'WITHDRAWAL') THEN (i.amount - i.paid_amount)
              WHEN i.type = 'DEPOSIT' THEN
                -(
                  i.amount - COALESCE((
                    SELECT SUM(t.used_amount)
                    FROM transactions t
                    WHERE t.invoice_id = i.id AND t.deleted_at IS NULL
                  ), 0)
                )
              ELSE 0
            END
          ), 0)
          FROM invoices i
          WHERE i.user_id = users.id AND i.deleted_at IS NULL
        )
        WHERE role = 'CUSTOMER'
      ''');
    });
  }

  /// Returns global stats in a **single SQL query** instead of loading all customers into RAM.
  Future<Map<String, dynamic>> getGlobalStats() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COUNT(*) AS total_customers,
        COALESCE(SUM(CASE WHEN balance > 0 THEN balance ELSE 0 END), 0) AS total_debts,
        COALESCE(SUM(CASE WHEN balance < 0 THEN ABS(balance) ELSE 0 END), 0) AS total_balances,
        COUNT(CASE WHEN is_permanent_customer = 0 AND balance > 0 THEN 1 END) AS unpaid_non_permanent_count
      FROM users
      WHERE role = 'CUSTOMER' AND deleted_at IS NULL
    ''');
    final row = rows.first;
    return {
      'total_customers':           (row['total_customers'] as int?) ?? 0,
      'total_debts':               (row['total_debts'] as num?)?.toDouble() ?? 0.0,
      'total_balances':            (row['total_balances'] as num?)?.toDouble() ?? 0.0,
      'unpaid_non_permanent_count':(row['unpaid_non_permanent_count'] as int?) ?? 0,
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

  /// Returns total count of non-deleted invoices + transactions linked to this customer.
  /// Used to guard against deleting customers who have any financial records.
  Future<int> countCustomerLinkedRecords(int customerId) async {
    final db = await database;
    final invoiceCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM invoices WHERE user_id = ? AND deleted_at IS NULL',
      [customerId],
    )) ?? 0;
    final txnCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM transactions WHERE buyer_id = ? AND deleted_at IS NULL',
      [customerId],
    )) ?? 0;
    return invoiceCount + txnCount;
  }

  Future<void> addCredit({required int userId, required double amount, String? notes, required int paymentMethodId, DateTime? date}) async {
    final db = await database;
    await db.transaction((txn) async {
      final effectiveDate = date ?? DateTime.now();
      final now = effectiveDate.toIso8601String();
      final dateStr = DateFormat('dd-MM-yyyy EEEE', 'ar').format(effectiveDate);
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

  /// Returns only ACTIVE, non-deleted payment methods.
  /// Use this for sales, invoices, and payment screens where only
  /// usable methods should be offered to the user.
  Future<List<PaymentMethod>> getPaymentMethods({String? category}) async {
    final db = await database;
    String where = 'is_active = 1 AND deleted_at IS NULL';
    List<dynamic> args = [];
    if (category != null) { where += ' AND category = ?'; args.add(category); }
    final r = await db.query('payment_methods', where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'sort_order ASC');
    return r.map((m) => PaymentMethod.fromMap(m)).toList();
  }

  /// Returns ALL non-deleted payment methods (active AND inactive).
  /// Use this for management screens and purchases where the user
  /// needs to see and manage every method, including deactivated ones.
  Future<List<PaymentMethod>> getAllPaymentMethods({String? category}) async {
    final db = await database;
    String where = 'deleted_at IS NULL';
    List<dynamic> args = [];
    if (category != null) { where += ' AND category = ?'; args.add(category); }
    final r = await db.query('payment_methods', where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'sort_order ASC');
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

  /// Soft-deletes a payment method by setting deleted_at.
  /// Does NOT change is_active — active/inactive state is independent
  /// of whether the method has been deleted.
  Future<int> deletePaymentMethod(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final existing = await db.query('payment_methods', where: 'id = ?', whereArgs: [id], limit: 1);
    int currentVersion = existing.isNotEmpty ? (existing.first['version'] as int? ?? 0) : 0;
    return await db.update('payment_methods', {
      'deleted_at': now,
      'is_synced': 0,
      'version': currentVersion + 1,
      'updated_at': now,
    }, where: 'id = ?', whereArgs: [id]);
  }

  /// Returns the total number of non-deleted records (invoices + purchases)
  /// that reference the given payment method. Used to guard against deletion.
  Future<int> countLinkedRecords(int paymentMethodId) async {
    final db = await database;
    final invResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM invoices WHERE payment_method_id = ? AND deleted_at IS NULL',
      [paymentMethodId],
    );
    final purResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM purchases WHERE payment_method_id = ? AND deleted_at IS NULL',
      [paymentMethodId],
    );
    final invCount = (invResult.first['cnt'] as int?) ?? 0;
    final purCount = (purResult.first['cnt'] as int?) ?? 0;
    return invCount + purCount;
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

  Future<void> updateInvoiceWithLog({
    required Invoice oldInv,
    required Invoice newInv,
    required String reason,
    int? performedById,
    String? performedByName,
    int? storeManagerId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
       await txn.update('invoices', {
        ...newInv.toMap(),
        'version': newInv.version + 1,
        // Preserve the accountant's chosen created_at (may have changed if date was edited)
        'created_at': newInv.createdAt.isNotEmpty ? newInv.createdAt : oldInv.createdAt,
        'updated_at': now,
        'is_synced': 0,
      }, where: 'id = ?', whereArgs: [newInv.id]);
      // Detect changed fields and log only those
      final changes = <Map<String, String?>>[];
      if (oldInv.amount != newInv.amount) {
        changes.add({'field': 'amount', 'label': 'المبلغ', 'old': oldInv.amount.toStringAsFixed(2), 'new': newInv.amount.toStringAsFixed(2)});
      }
      if ((oldInv.notes ?? '') != (newInv.notes ?? '')) {
        changes.add({'field': 'notes', 'label': 'الملاحظات', 'old': oldInv.notes ?? '', 'new': newInv.notes ?? ''});
      }
      if (oldInv.paymentMethodId != newInv.paymentMethodId) {
        changes.add({'field': 'payment_method_id', 'label': 'طريقة الدفع', 'old': oldInv.paymentMethodId?.toString() ?? '', 'new': newInv.paymentMethodId?.toString() ?? ''});
      }
      if (oldInv.paymentStatus != newInv.paymentStatus) {
        changes.add({'field': 'payment_status', 'label': 'حالة الدفع', 'old': oldInv.paymentStatus, 'new': newInv.paymentStatus});
      }
      if (oldInv.createdAt != newInv.createdAt) {
        changes.add({'field': 'created_at', 'label': 'تاريخ الفاتورة', 'old': oldInv.createdAt, 'new': newInv.createdAt});
      }

      if (changes.isEmpty) {
        // Nothing changed — log a single summary row
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'store_manager_id': storeManagerId,
          'edited_by_id': performedById,
          'edited_by_name': performedByName,
          'target_id': newInv.id,
          'target_type': 'INVOICE',
          'action': 'UPDATE',
          'field_name': null,
          'old_value': null,
          'new_value': null,
          'edit_reason': reason,
          'summary': 'تعديل الفاتورة (بدون تغيير في القيم)',
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        });
      } else {
        for (final ch in changes) {
          await txn.insert('edit_history', {
            'uuid': _uuid.v4(),
            'store_manager_id': storeManagerId,
            'edited_by_id': performedById,
            'edited_by_name': performedByName,
            'target_id': newInv.id,
            'target_type': 'INVOICE',
            'action': 'UPDATE',
            'field_name': ch['field'],
            'old_value': ch['old'],
            'new_value': ch['new'],
            'edit_reason': reason,
            'summary': 'تعديل ${ch['label']}: من ${ch['old']} إلى ${ch['new']}',
            'version': 1,
            'created_at': now,
            'updated_at': now,
            'is_synced': 0,
          });
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> getEditHistory(int targetId, String type) async {
    final db = await database;
    return await db.query('edit_history', where: 'target_id = ? AND target_type = ?', whereArgs: [targetId, type], orderBy: 'created_at DESC');
  }

  /// [date] defaults to today if null.
  /// Returns all daily stats in **2 SQL queries** instead of 6 separate ones.
  Future<Map<String, double>> getDetailedTodayStats({DateTime? date}) async {
    final today = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());
    final db = await database;

    // Single query to get all invoice-based stats for the day
    final invRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE
          WHEN i.payment_status IN ('PAID','paid') AND pm.type = 'app'
          THEN i.amount ELSE 0 END), 0) AS app_sales,
        COALESCE(SUM(CASE
          WHEN i.payment_status IN ('UNPAID','pending') AND pm.type = 'app'
          THEN i.amount ELSE 0 END), 0) AS app_unpaid,
        COALESCE(SUM(CASE
          WHEN i.type = 'WITHDRAWAL'
          THEN i.amount ELSE 0 END), 0) AS cash_withdrawals,
        COALESCE(SUM(CASE
          WHEN i.type = 'DEPOSIT' AND pm.type = 'cash'
          THEN i.amount ELSE 0 END), 0) AS cash_debt_repayment
      FROM invoices i
      LEFT JOIN payment_methods pm ON i.payment_method_id = pm.id
      WHERE i.created_at LIKE ? AND i.deleted_at IS NULL
    ''', ['$today%']);

    // Single query to get all purchase-based stats for the day
    final purRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN payment_source = 'CASH' THEN amount ELSE 0 END), 0) AS cash_purchases,
        COALESCE(SUM(CASE WHEN payment_source = 'APP'  THEN amount ELSE 0 END), 0) AS app_purchases
      FROM purchases
      WHERE created_at LIKE ? AND deleted_at IS NULL
    ''', ['$today%']);

    final inv = invRows.first;
    final pur = purRows.first;
    final double appSalesTotal  = (inv['app_sales'] as num?)?.toDouble() ?? 0.0;
    final double appUnpaidTotal = (inv['app_unpaid'] as num?)?.toDouble() ?? 0.0;
    final double appDebt = (appUnpaidTotal - appSalesTotal).clamp(0.0, double.infinity);

    return {
      'app_sales':           appSalesTotal,
      'app_debt':            appDebt,
      'cash_withdrawals':    (inv['cash_withdrawals'] as num?)?.toDouble() ?? 0.0,
      'cash_purchases':      (pur['cash_purchases'] as num?)?.toDouble() ?? 0.0,
      'app_purchases':       (pur['app_purchases'] as num?)?.toDouble() ?? 0.0,
      'cash_debt_repayment': (inv['cash_debt_repayment'] as num?)?.toDouble() ?? 0.0,
      // legacy key kept for backward compatibility
      'app_debt_repayment':  appSalesTotal,
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
    // On insert, updated_at matches created_at (accountant's date).
    map['updated_at'] = (p.createdAt.isNotEmpty) ? p.createdAt : now;
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

  /// Soft-delete a purchase (sets deleted_at timestamp)
  Future<void> softDeletePurchase(int purchaseId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'purchases',
      {'deleted_at': now, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  /// Restore a soft-deleted purchase
  Future<void> restorePurchase(int purchaseId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'purchases',
      {'deleted_at': null, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  /// Returns all soft-deleted purchases ordered by deletion date desc
  Future<List<Purchase>> getDeletedPurchases() async {
    final db = await database;
    final rows = await db.query(
      'purchases',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );
    return rows.map((m) => Purchase.fromMap(m)).toList();
  }

  /// Returns paginated soft-deleted purchases (10 per page)
  Future<List<Purchase>> getDeletedPurchasesPaged({
    int limit = 10,
    int offset = 0,
  }) async {
    final db = await database;
    final rows = await db.query(
      'purchases',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((m) => Purchase.fromMap(m)).toList();
  }

  /// Returns total count of soft-deleted purchases
  Future<int> getDeletedPurchasesCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM purchases WHERE deleted_at IS NOT NULL',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Edit purchase with full audit log (records who edited, reason, changed fields)
  Future<void> editPurchaseWithLog({
    required Purchase oldPurchase,
    required Purchase newPurchase,
    required String reason,
    required String editorName,
    required int editorId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'purchases',
        {
          ...newPurchase.toMap(),
          'version': oldPurchase.version + 1,
          // Preserve the accountant's chosen created_at (may have changed if date was edited)
          'created_at': newPurchase.createdAt.isNotEmpty ? newPurchase.createdAt : oldPurchase.createdAt,
          'updated_at': now,
          'is_synced': 0,
        },
        where: 'id = ?',
        whereArgs: [oldPurchase.id],
      );
      // Log date change
      if (oldPurchase.createdAt != newPurchase.createdAt) {
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'target_id': oldPurchase.id,
          'target_type': 'PURCHASE',
          'action': 'UPDATE',
          'field_name': 'created_at',
          'old_value': oldPurchase.createdAt,
          'new_value': newPurchase.createdAt,
          'edit_reason': reason,
          'edited_by_id': editorId,
          'edited_by_name': editorName,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        });
      }
      // Log amount change
      if (oldPurchase.amount != newPurchase.amount) {
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'target_id': oldPurchase.id,
          'target_type': 'PURCHASE',
          'field_name': 'amount',
          'old_value': oldPurchase.amount.toStringAsFixed(2),
          'new_value': newPurchase.amount.toStringAsFixed(2),
          'edit_reason': reason,
          'edited_by_id': editorId,
          'edited_by_name': editorName,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        });
      }
      // Log merchant name change
      if (oldPurchase.merchantName != newPurchase.merchantName) {
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'target_id': oldPurchase.id,
          'target_type': 'PURCHASE',
          'field_name': 'merchant_name',
          'old_value': oldPurchase.merchantName,
          'new_value': newPurchase.merchantName,
          'edit_reason': reason,
          'edited_by_id': editorId,
          'edited_by_name': editorName,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        });
      }
      // Log notes change
      if ((oldPurchase.notes ?? '') != (newPurchase.notes ?? '')) {
        await txn.insert('edit_history', {
          'uuid': _uuid.v4(),
          'target_id': oldPurchase.id,
          'target_type': 'PURCHASE',
          'field_name': 'notes',
          'old_value': oldPurchase.notes ?? '',
          'new_value': newPurchase.notes ?? '',
          'edit_reason': reason,
          'edited_by_id': editorId,
          'edited_by_name': editorName,
          'version': 1,
          'created_at': now,
          'updated_at': now,
          'is_synced': 0,
        });
      }
    });
  }

  /// Returns edit history entries for a specific purchase
  Future<List<Map<String, dynamic>>> getPurchaseEditHistory(int purchaseId) async {
    final db = await database;
    return await db.query(
      'edit_history',
      where: 'target_id = ? AND target_type = ?',
      whereArgs: [purchaseId, 'PURCHASE'],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> updateInvoice(Invoice inv) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update('invoices', {
      ...inv.toMap(),
      'version': inv.version + 1,
      // Preserve accountant's chosen created_at
      'created_at': inv.createdAt.isNotEmpty ? inv.createdAt : now,
      'is_synced': 0,
      'updated_at': now
    }, where: 'id = ?', whereArgs: [inv.id]);
  }

  /// Legacy wrapper kept for backward compatibility.
  Future<void> logEdit(int targetId, String type, String field, String oldVal, String newVal, {int? byId, String? byName}) async {
    await logActivity(
      targetId: targetId,
      targetType: type,
      action: 'UPDATE',
      fieldName: field,
      oldValue: oldVal,
      newValue: newVal,
      performedById: byId,
      performedByName: byName,
    );
  }

  /// Central activity logger — records every CREATE / UPDATE / DELETE operation.
  ///
  /// [targetType]: 'INVOICE' | 'CUSTOMER' | 'PURCHASE' | 'PAYMENT_METHOD' |
  ///               'TRANSACTION' | 'DAILY_STAT' | 'ACCOUNTANT'
  /// [action]:     'CREATE' | 'UPDATE' | 'DELETE'
  Future<void> logActivity({
    required int targetId,
    required String targetType,
    required String action,
    String? fieldName,
    String? oldValue,
    String? newValue,
    String? summary,
    String? reason,
    int? performedById,
    String? performedByName,
    int? storeManagerId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('edit_history', {
      'uuid': _uuid.v4(),
      'store_manager_id': storeManagerId,
      'edited_by_id': performedById,
      'edited_by_name': performedByName,
      'target_id': targetId,
      'target_type': targetType,
      'action': action,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'edit_reason': reason,
      'summary': summary,
      'version': 1,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  }

  /// Returns the full activity log with optional filters.
  /// [targetType] null = all types.
  /// [action] null = all actions.
  /// [performedById] null = all users.
  Future<List<Map<String, dynamic>>> getActivityLog({
    String? targetType,
    String? action,
    int? performedById,
    DateTime? from,
    DateTime? to,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await database;
    final conditions = <String>['deleted_at IS NULL'];
    final args = <dynamic>[];

    if (targetType != null) {
      conditions.add('target_type = ?');
      args.add(targetType);
    }
    if (action != null) {
      conditions.add('action = ?');
      args.add(action);
    }
    if (performedById != null) {
      conditions.add('edited_by_id = ?');
      args.add(performedById);
    }
    if (from != null) {
      conditions.add('created_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      conditions.add('created_at <= ?');
      args.add(to.toIso8601String());
    }

    return db.query(
      'edit_history',
      where: conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
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
    // Re-seed the developer account so the developer can log in immediately
    await _seedDeveloperAccount(db);
    dev.log('Full database reset completed. Developer account re-seeded.', name: 'DatabaseService');
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

  /// Returns customers with the given name (for duplicate check before insert).
  Future<List<User>> findCustomersByName(String name) async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT * FROM users WHERE name = ? AND role = 'CUSTOMER' AND deleted_at IS NULL LIMIT 1",
      [name.trim()],
    );
    return rows.map((r) => User.fromMap(r)).toList();
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

      // 3. For CUSTOMER users: merge by name to prevent duplicates
      if (table == 'users' && sanitizedData['role'] == 'CUSTOMER' && !isDeletedOnServer) {
        final name = sanitizedData['name'];
        if (name != null && name.toString().trim().isNotEmpty) {
          final byName = await txn.rawQuery(
            "SELECT * FROM users WHERE name = ? AND role = 'CUSTOMER' AND deleted_at IS NULL LIMIT 1",
            [name.toString().trim()],
          );
          if (byName.isNotEmpty) {
            final existingId = byName.first['id'] as int;
            final existingVersion = byName.first['version'] as int? ?? 0;
            final incomingVersion = sanitizedData['version'] as int? ?? 0;
            // Re-link all invoices and transactions to the surviving record
            await txn.rawUpdate(
              'UPDATE invoices SET user_id = ? WHERE user_id = ?',
              [existingId, existingId],
            );
            await txn.rawUpdate(
              'UPDATE transactions SET buyer_id = ? WHERE buyer_id = (SELECT id FROM users WHERE uuid = ? LIMIT 1)',
              [existingId, uuid],
            );
            // Update the surviving record with server data if server version is newer
            if (incomingVersion >= existingVersion) {
              sanitizedData.remove('password');
              await txn.update('users', sanitizedData, where: 'id = ?', whereArgs: [existingId]);
            }
            return existingId;
          }
        }
      }

      // 4. Insert new record — skip if server is telling us it is deleted
      // (no point creating a record locally that is already deleted on server)
      if (isDeletedOnServer) return -1;

      if (table == 'users') {
        // Assign a safe local password; real auth goes through the server token
        sanitizedData['password'] = sanitizedData['password'] ?? '***';
      }
      return await txn.insert(table, sanitizedData);
    }
  }

  // Smart Notifications
  Future<List<Map<String, dynamic>>> getSmartNotifications() async {
    final db = await database;
    final List<Map<String, dynamic>> notifications = [];

    // 1. Unpaid invoices (UNPAID only) for customers with real positive balance (actual debt)
    final debtCustomers = await db.rawQuery('''
      SELECT u.id, u.name, u.nickname, u.balance, u.credit_limit,
             COUNT(i.id) as unpaid_count,
             SUM(i.amount) as unpaid_total
      FROM users u
      JOIN invoices i ON i.user_id = u.id
        AND i.deleted_at IS NULL
        AND i.type = 'SALE'
        AND i.payment_status = 'UNPAID'
      WHERE u.role = 'CUSTOMER'
        AND u.deleted_at IS NULL
        AND u.balance > 0
      GROUP BY u.id
      ORDER BY u.balance DESC
    ''');

    for (final row in debtCustomers) {
      notifications.add({
        'type': 'UNPAID_INVOICES',
        'customerId': row['id'],
        'customerName': row['name'],
        'customerNickname': row['nickname'],
        'balance': (row['balance'] as num).toDouble(),
        'unpaidCount': row['unpaid_count'],
        'unpaidTotal': (row['unpaid_total'] as num?)?.toDouble() ?? 0.0,
        'creditLimit': row['credit_limit'],
      });
    }

    // 2. Debt ceiling warnings (balance >= 80% of credit_limit, credit_limit > 0)
    final ceilingWarnings = await db.rawQuery('''
      SELECT id, name, nickname, balance, credit_limit
      FROM users
      WHERE role = 'CUSTOMER'
        AND deleted_at IS NULL
        AND credit_limit > 0
        AND balance >= (credit_limit * 0.8)
      ORDER BY (CAST(balance AS REAL) / credit_limit) DESC
    ''');

    for (final row in ceilingWarnings) {
      final balance = (row['balance'] as num).toDouble();
      final limit = (row['credit_limit'] as num).toDouble();
      // Skip if already included as UNPAID_INVOICES with balance >= limit
      notifications.add({
        'type': 'CEILING_WARNING',
        'customerId': row['id'],
        'customerName': row['name'],
        'customerNickname': row['nickname'],
        'balance': balance,
        'creditLimit': limit,
        'percentage': ((balance / limit) * 100).round(),
      });
    }

    return notifications;
  }

  Future<int> getSmartNotificationsCount() async {
    final db = await database;
    // Count customers with real debt (balance > 0) that have UNPAID invoices only
    final r = await db.rawQuery('''
      SELECT COUNT(DISTINCT u.id) as cnt
      FROM users u
      JOIN invoices i ON i.user_id = u.id
        AND i.deleted_at IS NULL
        AND i.type = 'SALE'
        AND i.payment_status = 'UNPAID'
      WHERE u.role = 'CUSTOMER'
        AND u.deleted_at IS NULL
        AND u.balance > 0
    ''');
    final unpaidCount = Sqflite.firstIntValue(r) ?? 0;

    final r2 = await db.rawQuery('''
      SELECT COUNT(*) as cnt FROM users
      WHERE role = 'CUSTOMER' AND deleted_at IS NULL
        AND credit_limit > 0 AND balance >= (credit_limit * 0.8)
    ''');
    final ceilingCount = Sqflite.firstIntValue(r2) ?? 0;

    return unpaidCount + ceilingCount;
  }

  /// Returns true if the accountant (employee) has any linked invoices or payments
  Future<bool> accountantHasOperations(int accountantId) async {
    final db = await database;
    // Check invoices linked to this accountant via payment method
    final invoiceResult = await db.rawQuery('''
      SELECT COUNT(*) as cnt
      FROM invoices
      WHERE payment_method_id IN (
        SELECT id FROM payment_methods WHERE accountant_id = ?
      )
      AND deleted_at IS NULL
    ''', [accountantId]);
    final invoiceCount = (invoiceResult.first['cnt'] as int?) ?? 0;
    if (invoiceCount > 0) return true;

    // Check if accountant is directly referenced in any transaction
    final txResult = await db.rawQuery('''
      SELECT COUNT(*) as cnt
      FROM transactions
      WHERE accountant_id = ?
      AND deleted_at IS NULL
    ''', [accountantId]);
    final txCount = (txResult.first['cnt'] as int?) ?? 0;
    return txCount > 0;
  }
}
