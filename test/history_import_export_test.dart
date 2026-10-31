import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:abd_elhadi_store/services/database_service.dart';
import 'package:abd_elhadi_store/services/import_service.dart';
import 'package:abd_elhadi_store/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Verify history optimization, creator backfilling, and export/import filtering', () async {
    final tempDbFile = File('test_verification_temp.db');
    if (tempDbFile.existsSync()) {
      tempDbFile.deleteSync();
    }

    DatabaseService.setCustomPath(tempDbFile.path);
    final dbService = DatabaseService();

    final db = await dbService.database;

    final sampleJsonFile = File('dev/elegant_store_export_2026-10-01_00-58-35.json');
    expect(sampleJsonFile.existsSync(), isTrue, reason: 'Sample JSON export file must exist');

    final jsonString = sampleJsonFile.readAsStringSync();

    final importService = ImportService(dbService);
    final stopwatch = Stopwatch()..start();
    final importResult = await importService.importFromJsonString(jsonString);
    stopwatch.stop();

    print('Import completed in ${stopwatch.elapsedMilliseconds} ms');
    expect(importResult.success, isTrue);

    // 1. Verify edit_history in local DB
    final historyRows = await db.query('edit_history');
    print('Total edit_history rows in imported DB: ${historyRows.length}');

    int createInHistory = 0;
    int nonSupportedTypes = 0;

    for (final row in historyRows) {
      final action = row['action']?.toString() ?? 'NULL';
      final targetType = row['target_type']?.toString() ?? 'NULL';

      if (action == 'CREATE' ||
          (row['summary']?.toString() ?? '').startsWith('إضافة') ||
          (row['summary']?.toString() ?? '').contains('جديد')) {
        createInHistory++;
      }
      if (targetType != 'INVOICE' && targetType != 'TRANSACTION' && targetType != 'PURCHASE') {
        nonSupportedTypes++;
      }
    }

    expect(createInHistory, equals(0), reason: 'No CREATE records allowed in edit_history');
    expect(nonSupportedTypes, equals(0), reason: 'Only INVOICE, TRANSACTION, PURCHASE target_types allowed');

    // 2. Verify created_by fields on invoices, transactions, purchases
    final invNullCreators = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM invoices WHERE created_by_name IS NULL OR created_by_id IS NULL')
    ) ?? 0;
    final txnNullCreators = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM transactions WHERE created_by_name IS NULL OR created_by_id IS NULL')
    ) ?? 0;
    final purNullCreators = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM purchases WHERE created_by_name IS NULL OR created_by_id IS NULL')
    ) ?? 0;

    expect(invNullCreators, equals(0), reason: 'Invoices must have created_by fields populated');
    expect(txnNullCreators, equals(0), reason: 'Transactions must have created_by fields populated');
    expect(purNullCreators, equals(0), reason: 'Purchases must have created_by fields populated');

    final managerInvoices = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM invoices WHERE created_by_name = 'Mohammad'")
    ) ?? 0;
    print('Invoices credited to store manager Mohammad: $managerInvoices');
    expect(managerInvoices, greaterThan(0), reason: 'Invoices should be attributed to store manager Mohammad');

    // 3. Verify ExportService output
    final exportService = ExportService(dbService);
    final exportedJsonStr = await exportService.exportToJsonString();
    final exportedJson = jsonDecode(exportedJsonStr) as Map<String, dynamic>;
    final exportedData = exportedJson['data'] as Map<String, dynamic>;
    final exportedHistory = exportedData['edit_history'] as List;

    print('Exported JSON edit_history count: ${exportedHistory.length}');
    expect(exportedHistory.length, equals(historyRows.length));

    await db.close();
    if (tempDbFile.existsSync()) {
      tempDbFile.deleteSync();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
