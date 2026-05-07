import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

/// Notification types — mirrors the two conditions in getSmartNotifications().
enum NotificationType {
  unpaidInvoices('UNPAID_INVOICES'),
  ceilingWarning('CEILING_WARNING');

  const NotificationType(this.value);
  final String value;

  static NotificationType fromString(String v) =>
      NotificationType.values.firstWhere((e) => e.value == v);
}

/// A single persisted notification row.
class AppNotification {
  final int? id;
  final String type;
  final int customerId;
  final String customerName;
  final String? customerNickname;
  final double balance;
  final int? unpaidCount;
  final double? unpaidTotal;
  final double? creditLimit;
  final int? percentage;
  final bool isRead;
  final String createdAt;
  final String updatedAt;

  const AppNotification({
    this.id,
    required this.type,
    required this.customerId,
    required this.customerName,
    this.customerNickname,
    required this.balance,
    this.unpaidCount,
    this.unpaidTotal,
    this.creditLimit,
    this.percentage,
    this.isRead = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as int?,
        type: m['type'] as String,
        customerId: m['customer_id'] as int,
        customerName: m['customer_name'] as String,
        customerNickname: m['customer_nickname'] as String?,
        balance: (m['balance'] as num).toDouble(),
        unpaidCount: m['unpaid_count'] as int?,
        unpaidTotal: (m['unpaid_total'] as num?)?.toDouble(),
        creditLimit: (m['credit_limit'] as num?)?.toDouble(),
        percentage: m['percentage'] as int?,
        isRead: (m['is_read'] as int? ?? 0) == 1,
        createdAt: m['created_at'] as String,
        updatedAt: m['updated_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'type': type,
        'customer_id': customerId,
        'customer_name': customerName,
        'customer_nickname': customerNickname,
        'balance': balance,
        'unpaid_count': unpaidCount,
        'unpaid_total': unpaidTotal,
        'credit_limit': creditLimit,
        'percentage': percentage,
        'is_read': isRead ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// Repository for the local `app_notifications` SQLite table.
///
/// Design rules:
/// - One row per (customer_id, type) — UPSERT keeps it fresh.
/// - Hard-deleted when the triggering condition is resolved.
/// - Paginated reads for the UI.
/// - `rebuildAll()` for Option 3 (post-restore backfill).
class NotificationRepository {
  final DatabaseService _dbService;

  NotificationRepository(this._dbService);

  // ─── Table DDL ────────────────────────────────────────────────────────────

  static const String createTableSql = '''
    CREATE TABLE IF NOT EXISTS app_notifications (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      type             TEXT    NOT NULL,
      customer_id      INTEGER NOT NULL,
      customer_name    TEXT    NOT NULL,
      customer_nickname TEXT,
      balance          REAL    NOT NULL DEFAULT 0,
      unpaid_count     INTEGER,
      unpaid_total     REAL,
      credit_limit     REAL,
      percentage       INTEGER,
      is_read          INTEGER NOT NULL DEFAULT 0,
      created_at       TEXT    NOT NULL,
      updated_at       TEXT    NOT NULL,
      UNIQUE(customer_id, type)
    )
  ''';

  static const String createIndexSql = '''
    CREATE INDEX IF NOT EXISTS idx_app_notif_type_read
    ON app_notifications(type, is_read)
  ''';

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<Database> get _db => _dbService.database;

  String get _now {
    final utc = DateTime.now().toUtc();
    return utc.toIso8601String();
  }

  // ─── Write / Upsert ───────────────────────────────────────────────────────

  /// Inserts or updates a notification for a customer.
  /// Preserves `is_read` and `created_at` if the row already exists.
  Future<void> upsert(AppNotification n) async {
    final db = await _db;
    final now = _now;

    // Check if row exists to preserve created_at and is_read
    final existing = await db.query(
      'app_notifications',
      where: 'customer_id = ? AND type = ?',
      whereArgs: [n.customerId, n.type],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert(
        'app_notifications',
        n.toMap()..['created_at'] = now,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await db.update(
        'app_notifications',
        {
          'customer_name': n.customerName,
          'customer_nickname': n.customerNickname,
          'balance': n.balance,
          'unpaid_count': n.unpaidCount,
          'unpaid_total': n.unpaidTotal,
          'credit_limit': n.creditLimit,
          'percentage': n.percentage,
          'updated_at': now,
        },
        where: 'customer_id = ? AND type = ?',
        whereArgs: [n.customerId, n.type],
      );
    }
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  /// Hard-deletes a specific notification type for a customer.
  Future<void> deleteForCustomer(int customerId, NotificationType type) async {
    final db = await _db;
    await db.delete(
      'app_notifications',
      where: 'customer_id = ? AND type = ?',
      whereArgs: [customerId, type.value],
    );
  }

  /// Hard-deletes ALL notifications for a customer (used when customer is deleted).
  Future<void> deleteAllForCustomer(int customerId) async {
    final db = await _db;
    await db.delete(
      'app_notifications',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
  }

  /// Hard-deletes all notifications (used on clearAllData / logout).
  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('app_notifications');
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  /// Returns paginated notifications ordered by balance DESC.
  Future<List<AppNotification>> getPage({
    int page = 0,
    int pageSize = 20,
    String? typeFilter, // null = all
  }) async {
    final db = await _db;
    final offset = page * pageSize;
    final where = typeFilter != null ? 'type = ?' : null;
    final whereArgs = typeFilter != null ? [typeFilter] : null;

    final rows = await db.query(
      'app_notifications',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'balance DESC',
      limit: pageSize,
      offset: offset,
    );
    return rows.map(AppNotification.fromMap).toList();
  }

  /// Returns the total count (for badge).
  Future<int> getTotalCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM app_notifications',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns count per type.
  Future<Map<String, int>> getCountByType() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT type, COUNT(*) as cnt FROM app_notifications GROUP BY type',
    );
    return {for (final r in rows) r['type'] as String: r['cnt'] as int};
  }

  // ─── Mark Read ────────────────────────────────────────────────────────────

  Future<void> markRead(int notificationId) async {
    final db = await _db;
    await db.update(
      'app_notifications',
      {'is_read': 1, 'updated_at': _now},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
  }

  Future<void> markAllRead() async {
    final db = await _db;
    await db.update(
      'app_notifications',
      {'is_read': 1, 'updated_at': _now},
      where: 'is_read = 0',
    );
  }

  // ─── Option 3: Full Rebuild (post-restore backfill) ───────────────────────

  /// Clears the table and rebuilds it from the current state of invoices/users.
  /// Applies the exact same conditions as getSmartNotifications().
  Future<void> rebuildAll() async {
    final db = await _db;
    final now = _now;

    await db.transaction((txn) async {
      // Clear existing
      await txn.delete('app_notifications');

      // ── 1. Unpaid invoices (SALE + UNPAID + balance > 0) ──────────────────
      final debtRows = await txn.rawQuery('''
        SELECT u.id, u.name, u.nickname, u.balance, u.credit_limit,
               COUNT(i.id)   AS unpaid_count,
               SUM(i.amount) AS unpaid_total
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

      for (final row in debtRows) {
        final balance = (row['balance'] as num).toDouble();
        final limit = (row['credit_limit'] as num?)?.toDouble();
        await txn.insert('app_notifications', {
          'type': NotificationType.unpaidInvoices.value,
          'customer_id': row['id'],
          'customer_name': row['name'],
          'customer_nickname': row['nickname'],
          'balance': balance,
          'unpaid_count': row['unpaid_count'],
          'unpaid_total': (row['unpaid_total'] as num?)?.toDouble() ?? 0.0,
          'credit_limit': limit,
          'percentage': limit != null && limit > 0
              ? ((balance / limit) * 100).round()
              : null,
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // ── 2. Ceiling warnings (balance >= 80% of credit_limit) ──────────────
      final ceilingRows = await txn.rawQuery('''
        SELECT id, name, nickname, balance, credit_limit
        FROM users
        WHERE role = 'CUSTOMER'
          AND deleted_at IS NULL
          AND credit_limit > 0
          AND balance >= (credit_limit * 0.8)
        ORDER BY (CAST(balance AS REAL) / credit_limit) DESC
      ''');

      for (final row in ceilingRows) {
        final balance = (row['balance'] as num).toDouble();
        final limit = (row['credit_limit'] as num).toDouble();
        await txn.insert('app_notifications', {
          'type': NotificationType.ceilingWarning.value,
          'customer_id': row['id'],
          'customer_name': row['name'],
          'customer_nickname': row['nickname'],
          'balance': balance,
          'unpaid_count': null,
          'unpaid_total': null,
          'credit_limit': limit,
          'percentage': ((balance / limit) * 100).round(),
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  // ─── Option 2 helpers: called after invoice/customer mutations ────────────

  /// Re-evaluates and upserts/deletes UNPAID_INVOICES notification for one customer.
  /// Call this after any invoice insert, update, delete, or balance recalculation.
  Future<void> refreshUnpaidForCustomer(int customerId) async {
    final db = await _db;
    final now = _now;

    final rows = await db.rawQuery('''
      SELECT u.id, u.name, u.nickname, u.balance, u.credit_limit,
             COUNT(i.id)   AS unpaid_count,
             SUM(i.amount) AS unpaid_total
      FROM users u
      JOIN invoices i ON i.user_id = u.id
        AND i.deleted_at IS NULL
        AND i.type = 'SALE'
        AND i.payment_status = 'UNPAID'
      WHERE u.role = 'CUSTOMER'
        AND u.deleted_at IS NULL
        AND u.id = ?
        AND u.balance > 0
      GROUP BY u.id
    ''', [customerId]);

    if (rows.isEmpty) {
      // Condition no longer met — hard delete
      await db.delete(
        'app_notifications',
        where: 'customer_id = ? AND type = ?',
        whereArgs: [customerId, NotificationType.unpaidInvoices.value],
      );
    } else {
      final row = rows.first;
      final balance = (row['balance'] as num).toDouble();
      final limit = (row['credit_limit'] as num?)?.toDouble();

      final existing = await db.query(
        'app_notifications',
        where: 'customer_id = ? AND type = ?',
        whereArgs: [customerId, NotificationType.unpaidInvoices.value],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('app_notifications', {
          'type': NotificationType.unpaidInvoices.value,
          'customer_id': row['id'],
          'customer_name': row['name'],
          'customer_nickname': row['nickname'],
          'balance': balance,
          'unpaid_count': row['unpaid_count'],
          'unpaid_total': (row['unpaid_total'] as num?)?.toDouble() ?? 0.0,
          'credit_limit': limit,
          'percentage': limit != null && limit > 0
              ? ((balance / limit) * 100).round()
              : null,
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await db.update(
          'app_notifications',
          {
            'customer_name': row['name'],
            'customer_nickname': row['nickname'],
            'balance': balance,
            'unpaid_count': row['unpaid_count'],
            'unpaid_total': (row['unpaid_total'] as num?)?.toDouble() ?? 0.0,
            'credit_limit': limit,
            'percentage': limit != null && limit > 0
                ? ((balance / limit) * 100).round()
                : null,
            'updated_at': now,
          },
          where: 'customer_id = ? AND type = ?',
          whereArgs: [customerId, NotificationType.unpaidInvoices.value],
        );
      }
    }
  }

  /// Re-evaluates and upserts/deletes CEILING_WARNING notification for one customer.
  /// Call this after balance recalculation or credit_limit change.
  Future<void> refreshCeilingForCustomer(int customerId) async {
    final db = await _db;
    final now = _now;

    final rows = await db.rawQuery('''
      SELECT id, name, nickname, balance, credit_limit
      FROM users
      WHERE id = ?
        AND role = 'CUSTOMER'
        AND deleted_at IS NULL
        AND credit_limit > 0
        AND balance >= (credit_limit * 0.8)
    ''', [customerId]);

    if (rows.isEmpty) {
      await db.delete(
        'app_notifications',
        where: 'customer_id = ? AND type = ?',
        whereArgs: [customerId, NotificationType.ceilingWarning.value],
      );
    } else {
      final row = rows.first;
      final balance = (row['balance'] as num).toDouble();
      final limit = (row['credit_limit'] as num).toDouble();
      final pct = ((balance / limit) * 100).round();

      final existing = await db.query(
        'app_notifications',
        where: 'customer_id = ? AND type = ?',
        whereArgs: [customerId, NotificationType.ceilingWarning.value],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('app_notifications', {
          'type': NotificationType.ceilingWarning.value,
          'customer_id': row['id'],
          'customer_name': row['name'],
          'customer_nickname': row['nickname'],
          'balance': balance,
          'unpaid_count': null,
          'unpaid_total': null,
          'credit_limit': limit,
          'percentage': pct,
          'is_read': 0,
          'created_at': now,
          'updated_at': now,
        });
      } else {
        await db.update(
          'app_notifications',
          {
            'customer_name': row['name'],
            'customer_nickname': row['nickname'],
            'balance': balance,
            'credit_limit': limit,
            'percentage': pct,
            'updated_at': now,
          },
          where: 'customer_id = ? AND type = ?',
          whereArgs: [customerId, NotificationType.ceilingWarning.value],
        );
      }
    }
  }

  /// Convenience: refresh both notification types for one customer.
  Future<void> refreshAllForCustomer(int customerId) async {
    await refreshUnpaidForCustomer(customerId);
    await refreshCeilingForCustomer(customerId);
  }
}
