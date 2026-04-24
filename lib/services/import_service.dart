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
/// Strategy: **UUID-based upsert (merge)**
/// - If a record with the same UUID already exists → update it only if the
///   incoming `version` is higher (last-write-wins by version).
/// - If no record with that UUID exists → insert it.
/// - Local records that are NOT in the JSON file are left untouched.
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

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens a file picker, reads the selected JSON file, validates it, and
  /// imports all records into the local database.
  ///
  /// Returns an [ImportResult] describing what happened.
  Future<ImportResult> pickAndImport() async {
    // 1. Let the user pick a file
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

    // 2. Read file content
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

    // 3. Parse and import
    return importFromJsonString(jsonString);
  }

  /// Parses [jsonString] and imports all records.
  /// Useful for testing or custom import flows.
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

    // Build a UUID→localId cache for FK resolution during import
    // (populated lazily per table as we go)
    final Map<String, Map<String, int>> uuidToIdCache = {};

    await db.transaction((txn) async {
      for (final table in _tableOrder) {
        final List<dynamic> rows = (data[table] as List<dynamic>?) ?? [];
        if (rows.isEmpty) {
          upsertedCounts[table] = 0;
          continue;
        }

        // Populate UUID→id cache for this table (needed for FK resolution)
        final existingRows = await txn.query(table, columns: ['id', 'uuid']);
        uuidToIdCache[table] = {
          for (final r in existingRows) r['uuid'] as String: r['id'] as int,
        };

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

            final int? existingId = uuidToIdCache[table]?[uuid];
            if (existingId != null) {
              // Record exists — update only if incoming version is higher
              final existingVersion = await txn.query(
                table,
                columns: ['version'],
                where: 'id = ?',
                whereArgs: [existingId],
              );
              final int localVersion =
                  (existingVersion.first['version'] as int?) ?? 0;
              final int incomingVersion = (row['version'] as int?) ?? 1;

              if (incomingVersion >= localVersion) {
                row.remove('id'); // never overwrite the local auto-increment id
                await txn.update(
                  table,
                  row,
                  where: 'uuid = ?',
                  whereArgs: [uuid],
                );
                count++;
              }
              // else: local version is newer — skip
            } else {
              // New record — insert
              row.remove('id'); // let SQLite assign a new local id
              row['is_synced'] = 0; // mark as not synced to server
              final int newId = await txn.insert(table, row);
              // Update cache so subsequent tables can resolve this FK
              uuidToIdCache[table] ??= {};
              uuidToIdCache[table]![uuid] = newId;
              count++;
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
            row, 'payment_method_uuid', 'payment_method_id', 'payment_methods', cache);
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
        break;
      case 'transactions':
        _replaceUuidWithId(row, 'buyer_uuid', 'buyer_id', 'users', cache);
        _replaceUuidWithId(row, 'invoice_uuid', 'invoice_id', 'invoices', cache);
        _replaceUuidWithId(
            row, 'payment_method_uuid', 'payment_method_id', 'payment_methods', cache);
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
        break;
      case 'purchases':
        _replaceUuidWithId(
            row, 'payment_method_uuid', 'payment_method_id', 'payment_methods', cache);
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
        break;
      case 'daily_statistics':
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
        break;
      case 'edit_history':
        _replaceUuidWithId(
            row, 'edited_by_uuid', 'edited_by_id', 'users', cache);
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
        break;
      case 'payment_methods':
        _replaceUuidWithId(
            row, 'store_manager_uuid', 'store_manager_id', 'users', cache);
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
    if (uuid != null) {
      row[idKey] = cache[targetTable]?[uuid]; // null if not found yet
    } else {
      row[idKey] = null;
    }
  }
}
