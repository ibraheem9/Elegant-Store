import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

/// Handles exporting the entire local SQLite database to a structured JSON file.
///
/// The exported JSON uses UUIDs as the canonical identifier for every record,
/// so all relationships (foreign keys) remain intact and the file can be used
/// to recreate any database — SQLite, MySQL, PostgreSQL, etc. — without any
/// ID-mapping issues.
///
/// Export format:
/// ```json
/// {
///   "meta": {
///     "app": "Elegant Store",
///     "exported_at": "2026-04-18T12:00:00.000",
///     "version": 1,
///     "tables": ["users", "payment_methods", ...]
///   },
///   "data": {
///     "users": [ { ...record with uuid-based FKs... }, ... ],
///     "payment_methods": [ ... ],
///     "invoices": [ ... ],
///     "transactions": [ ... ],
///     "purchases": [ ... ],
///     "daily_statistics": [ ... ],
///     "edit_history": [ ... ]
///   }
/// }
/// ```
class ExportService {
  final DatabaseService _dbService;

  ExportService(this._dbService);

  // ── Table export order (respects FK dependency order) ─────────────────────
  static const List<String> _tableOrder = [
    'users',
    'payment_methods',
    'invoices',
    'transactions',
    'purchases',
    'daily_statistics',
    'edit_history',
  ];

  // ── UUID lookup cache: table -> { localId -> uuid } ───────────────────────
  // Populated once per export run to avoid N+1 queries.
  final Map<String, Map<int, String>> _uuidCache = {};

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Exports all data to a JSON file and opens the system share sheet so the
  /// user can save it to Files, send it via email, etc.
  ///
  /// Returns the path of the written file.
  Future<String> exportAndShare() async {
    final jsonString = await _buildExportJson();
    final filePath = await _writeToFile(jsonString);
    await _shareFile(filePath);
    return filePath;
  }

  /// Exports all data and returns the raw JSON string (useful for testing or
  /// custom save flows).
  Future<String> exportToJsonString() => _buildExportJson();

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: BUILD JSON
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _buildExportJson() async {
    _uuidCache.clear();
    final db = await _dbService.database;

    // Pre-populate UUID cache for all tables that are referenced as FKs
    for (final table in _tableOrder) {
      final rows = await db.query(table, columns: ['id', 'uuid']);
      _uuidCache[table] = {
        for (final r in rows) (r['id'] as int): r['uuid'] as String,
      };
    }

    final Map<String, dynamic> exportData = {};

    for (final table in _tableOrder) {
      final rows = await db.query(table);
      exportData[table] = rows
          .map((row) => _resolveRowForeignKeys(table, Map<String, dynamic>.from(row)))
          .toList();
    }

    final payload = {
      'meta': {
        'app': 'Elegant Store',
        'exported_at': DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(DateTime.now()),
        'schema_version': 4,
        'tables': _tableOrder,
        'record_counts': {
          for (final t in _tableOrder) t: (exportData[t] as List).length,
        },
      },
      'data': exportData,
    };

    // Use a JsonEncoder with indentation for human-readable output
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: FOREIGN KEY RESOLUTION
  // Replace every integer FK column with its UUID equivalent so that the
  // exported file is self-contained and portable across different databases.
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _resolveRowForeignKeys(
      String table, Map<String, dynamic> row) {
    // Always remove the local auto-increment id — uuid is the canonical key
    row.remove('id');

    switch (table) {
      case 'users':
        _replaceIdWithUuid(row, 'parent_id', 'parent_uuid', 'users');
        break;

      case 'invoices':
        _replaceIdWithUuid(row, 'user_id', 'user_uuid', 'users');
        _replaceIdWithUuid(
            row, 'payment_method_id', 'payment_method_uuid', 'payment_methods');
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;

      case 'transactions':
        _replaceIdWithUuid(row, 'buyer_id', 'buyer_uuid', 'users');
        _replaceIdWithUuid(row, 'invoice_id', 'invoice_uuid', 'invoices');
        _replaceIdWithUuid(
            row, 'payment_method_id', 'payment_method_uuid', 'payment_methods');
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;

      case 'purchases':
        _replaceIdWithUuid(
            row, 'payment_method_id', 'payment_method_uuid', 'payment_methods');
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;

      case 'daily_statistics':
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;

      case 'edit_history':
        _replaceIdWithUuid(
            row, 'edited_by_id', 'edited_by_uuid', 'users');
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;

      case 'payment_methods':
        _replaceIdWithUuid(
            row, 'store_manager_id', 'store_manager_uuid', 'users');
        break;
    }

    return row;
  }

  /// Replaces an integer FK column ([idKey]) with a UUID string column
  /// ([uuidKey]) by looking up the UUID from the pre-populated cache.
  void _replaceIdWithUuid(
    Map<String, dynamic> row,
    String idKey,
    String uuidKey,
    String targetTable,
  ) {
    final int? id = row[idKey] as int?;
    row.remove(idKey);
    if (id != null) {
      row[uuidKey] = _uuidCache[targetTable]?[id];
    } else {
      row[uuidKey] = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: FILE I/O
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> _writeToFile(String jsonString) async {
    final Directory dir = await _getExportDirectory();
    final String timestamp =
        DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final String fileName = 'elegant_store_export_$timestamp.json';
    final File file = File('${dir.path}/$fileName');
    await file.writeAsString(jsonString, encoding: utf8, flush: true);
    debugPrint('[ExportService] Written to: ${file.path}');
    return file.path;
  }

  Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Use the app's documents directory so the file persists and is
      // accessible via the Files app on iOS / file manager on Android.
      return getApplicationDocumentsDirectory();
    }
    // Desktop / other platforms — use the Downloads folder
    final downloads = await getDownloadsDirectory();
    return downloads ?? await getApplicationDocumentsDirectory();
  }

  Future<void> _shareFile(String filePath) async {
    final XFile xFile = XFile(filePath, mimeType: 'application/json');
    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: 'Elegant Store — Database Export',
        text: 'ملف تصدير قاعدة بيانات متجر Elegant Store',
      ),
    );
  }
}
