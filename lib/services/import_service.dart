import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

/// Result of an import operation.
class ImportResult {
  final bool success;
  final String message;
  final Map<String, int> upsertedCounts;
  final List<String> errors;

  const ImportResult({
    required this.success,
    required this.message,
    required this.upsertedCounts,
    required this.errors,
  });
}

/// Handles importing a JSON backup file back into the local SQLite database.
///
/// Strategy: **UUID-first dual-lookup upsert (merge)**
///
/// For each incoming record:
/// 1. Look up by UUID in the local DB → if found, update (version-gated).
/// 2. If not found by UUID, look up by the table's secondary unique key
///    (e.g. `username` for users, `statistic_date` for daily_statistics).
///    If found that way, update the record AND patch its UUID to match the
///    incoming one so future syncs stay consistent.
/// 3. If still not found → insert using `INSERT OR IGNORE` so any remaining
///    edge-case constraint conflicts are silently skipped rather than crashing.
///
/// Local records that are NOT in the JSON file are left untouched.
///
/// After all tables are imported, all customer balances are recalculated from
/// scratch to ensure consistency.
class ImportService {
  final DatabaseService _dbService;

  ImportService(this._dbService);

  // ── Table import order (must respect FK dependency order) ─────────────────
  static const List<String> _tableOrder = [
    'users',
    'payment_methods',
    'invoices',
    'transactions',
    'purchases',
    'daily_statistics',
    'edit_history',
  ];

  /// Secondary unique fields used as fallback lookup when UUID is not found.
  /// Maps table name → column name (nullable = no fallback).
  static const Map<String, String?> _secondaryUniqueField = {
    'users': 'username',
    'payment_methods': null,
    'invoices': null,
    'transactions': null,
    'purchases': null,
    'daily_statistics': 'statistic_date',
    'edit_history': null,
  };

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens a file picker, reads the selected JSON file, validates it, and
  /// imports all records into the local database.
  Future<ImportResult> pickAndImport() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'اختر ملف النسخة الاحتياطية',
    );

    if (result == null || result.files.isEmpty) {
      return const ImportResult(
        success: false,
        message: 'لم يتم اختيار أي ملف.',
        upsertedCounts: {},
        errors: [],
      );
    }

    final String? filePath = result.files.single.path;
    if (filePath == null) {
      return const ImportResult(
        success: false,
        message: 'تعذّر الوصول إلى الملف المحدد.',
        upsertedCounts: {},
        errors: [],
      );
    }

    final String jsonString;
    try {
      jsonString = await File(filePath).readAsString(encoding: utf8);
    } catch (e) {
      return ImportResult(
        success: false,
        message: 'فشل قراءة الملف: $e',
        upsertedCounts: {},
        errors: [e.toString()],
      );
    }

    return importFromJsonString(jsonString);
  }

  /// Parses [jsonString] and imports all records.
  Future<ImportResult> importFromJsonString(String jsonString) async {
    // ── Parse JSON ──────────────────────────────────────────────────────────
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return ImportResult(
        success: false,
        message: 'الملف ليس JSON صالحاً: $e',
        upsertedCounts: {},
        errors: [e.toString()],
      );
    }

    // ── Validate structure ──────────────────────────────────────────────────
    final meta = payload['meta'] as Map<String, dynamic>?;
    final data = payload['data'] as Map<String, dynamic>?;

    if (meta == null || data == null) {
      return const ImportResult(
        success: false,
        message: 'بنية الملف غير صحيحة: يجب أن يحتوي على حقلَي "meta" و"data".',
        upsertedCounts: {},
        errors: [],
      );
    }

    final String appName = meta['app'] as String? ?? '';
    if (!appName.toLowerCase().contains('elegant')) {
      return const ImportResult(
        success: false,
        message: 'الملف لا ينتمي إلى تطبيق Elegant Store.',
        upsertedCounts: {},
        errors: [],
      );
    }

    // ── Perform import ──────────────────────────────────────────────────────
    final Map<String, int> upsertedCounts = {};
    final List<String> errors = [];

    final db = await _dbService.database;

    // UUID→localId cache populated per table for FK resolution
    final Map<String, Map<String, int>> uuidToIdCache = {};

    await db.transaction((txn) async {
      for (final table in _tableOrder) {
        final List<dynamic> rows = (data[table] as List<dynamic>?) ?? [];
        if (rows.isEmpty) {
          upsertedCounts[table] = 0;
          continue;
        }

        // Build UUID→id cache for this table
        final existingRows = await txn.query(
          table,
          columns: ['id', 'uuid'],
        );
        uuidToIdCache[table] = {
          for (final r in existingRows)
            if (r['uuid'] != null) r['uuid'] as String: r['id'] as int,
        };

        // Build secondary-key→id cache if applicable
        final String? secondaryField = _secondaryUniqueField[table];
        Map<String, int> secondaryKeyCache = {};
        if (secondaryField != null) {
          final secRows = await txn.query(
            table,
            columns: ['id', 'uuid', secondaryField],
          );
          secondaryKeyCache = {
            for (final r in secRows)
              if (r[secondaryField] != null)
                r[secondaryField] as String: r['id'] as int,
          };
        }

        int count = 0;
        for (final dynamic rawRow in rows) {
          try {
            final Map<String, dynamic> row =
                Map<String, dynamic>.from(rawRow as Map);

            // Resolve UUID-based FKs back to local integer IDs
            _resolveUuidForeignKeys(table, row, uuidToIdCache);

            final String? uuid = row['uuid'] as String?;
            if (uuid == null) {
              errors.add('[$table] سجل بدون uuid — تم تخطيه');
              continue;
            }

            // ── Step 1: Look up by UUID ────────────────────────────────────
            int? existingId = uuidToIdCache[table]?[uuid];

            // ── Step 2: Fallback lookup by secondary unique field ──────────
            if (existingId == null && secondaryField != null) {
              final secondaryValue = row[secondaryField] as String?;
              if (secondaryValue != null) {
                existingId = secondaryKeyCache[secondaryValue];
                if (existingId != null) {
                  // Patch the UUID in DB so future lookups work by UUID
                  await txn.update(
                    table,
                    {'uuid': uuid},
                    where: 'id = ?',
                    whereArgs: [existingId],
                  );
                  // Update caches
                  uuidToIdCache[table]![uuid] = existingId;
                  debugPrint(
                    '[ImportService] [$table] UUID patched for $secondaryField=$secondaryValue',
                  );
                }
              }
            }

            if (existingId != null) {
              // ── Record exists → update only if incoming version ≥ local ──
              final versionResult = await txn.query(
                table,
                columns: ['version'],
                where: 'id = ?',
                whereArgs: [existingId],
              );
              final int localVersion =
                  (versionResult.first['version'] as int?) ?? 0;
              final int incomingVersion = (row['version'] as int?) ?? 1;

              if (incomingVersion >= localVersion) {
                row.remove('id'); // never overwrite the local auto-increment id
                await txn.update(
                  table,
                  row,
                  where: 'id = ?',
                  whereArgs: [existingId],
                );
                count++;
              }
              // else: local version is newer — skip silently
            } else {
              // ── New record → insert with OR IGNORE to skip constraint ─────
              // conflicts that may still occur (e.g. duplicate uuid race).
              row.remove('id'); // let SQLite assign a new local id
              row['is_synced'] = 0; // mark as not yet synced to server

              final int newId = await txn.rawInsert(
                _buildInsertOrIgnoreSql(table, row),
                row.values.toList(),
              );

              if (newId > 0) {
                // Update caches so subsequent tables can resolve this FK
                uuidToIdCache[table] ??= {};
                uuidToIdCache[table]![uuid] = newId;
                if (secondaryField != null) {
                  final secVal = row[secondaryField] as String?;
                  if (secVal != null) secondaryKeyCache[secVal] = newId;
                }
                count++;
              } else {
                // INSERT OR IGNORE skipped the row — log as warning
                errors.add(
                  '[$table] تم تخطي سجل (تعارض في القيد الفريد): uuid=$uuid',
                );
              }
            }
          } catch (e) {
            errors.add('[$table] خطأ: $e');
            debugPrint('[ImportService] Error importing row in $table: $e');
          }
        }
        upsertedCounts[table] = count;
      }
    });

    // ── Recalculate all customer balances ───────────────────────────────────
    try {
      await _dbService.recalculateAllBalances();
    } catch (e) {
      errors.add('فشل إعادة حساب الأرصدة: $e');
    }

    final int total = upsertedCounts.values.fold(0, (a, b) => a + b);
    final bool hasErrors = errors.isNotEmpty;

    return ImportResult(
      success: true,
      message: hasErrors
          ? 'تم الاستيراد مع ${errors.length} تحذير/خطأ. إجمالي السجلات المُعالَجة: $total'
          : 'تم الاستيراد بنجاح. إجمالي السجلات المُعالَجة: $total',
      upsertedCounts: upsertedCounts,
      errors: errors,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: BUILD INSERT OR IGNORE SQL
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds an `INSERT OR IGNORE INTO <table> (col1, col2, ...) VALUES (?, ?, ...)`
  /// statement from the given [row] map.
  String _buildInsertOrIgnoreSql(
    String table,
    Map<String, dynamic> row,
  ) {
    final columns = row.keys.join(', ');
    final placeholders = List.filled(row.length, '?').join(', ');
    return 'INSERT OR IGNORE INTO $table ($columns) VALUES ($placeholders)';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: FK RESOLUTION (UUID → local integer id)
  // ─────────────────────────────────────────────────────────────────────────

  void _resolveUuidForeignKeys(
    String table,
    Map<String, dynamic> row,
    Map<String, Map<String, int>> cache,
  ) {
    switch (table) {
      case 'users':
        _replaceUuidWithId(row, 'parent_uuid', 'parent_id', 'users', cache);
        break;
      case 'invoices':
        _replaceUuidWithId(row, 'user_uuid', 'user_id', 'users', cache);
        _replaceUuidWithId(
          row,
          'payment_method_uuid',
          'payment_method_id',
          'payment_methods',
          cache,
        );
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
      case 'transactions':
        _replaceUuidWithId(row, 'buyer_uuid', 'buyer_id', 'users', cache);
        _replaceUuidWithId(
          row,
          'invoice_uuid',
          'invoice_id',
          'invoices',
          cache,
        );
        _replaceUuidWithId(
          row,
          'payment_method_uuid',
          'payment_method_id',
          'payment_methods',
          cache,
        );
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
      case 'purchases':
        _replaceUuidWithId(
          row,
          'payment_method_uuid',
          'payment_method_id',
          'payment_methods',
          cache,
        );
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
      case 'daily_statistics':
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
      case 'edit_history':
        _replaceUuidWithId(
          row,
          'edited_by_uuid',
          'edited_by_id',
          'users',
          cache,
        );
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
      case 'payment_methods':
        _replaceUuidWithId(
          row,
          'store_manager_uuid',
          'store_manager_id',
          'users',
          cache,
        );
        break;
    }
  }

  void _replaceUuidWithId(
    Map<String, dynamic> row,
    String uuidKey,
    String idKey,
    String targetTable,
    Map<String, Map<String, int>> cache,
  ) {
    final String? uuid = row[uuidKey] as String?;
    row.remove(uuidKey);
    row[idKey] = uuid != null ? cache[targetTable]?[uuid] : null;
  }
}
