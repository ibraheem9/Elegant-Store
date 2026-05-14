import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/timestamp_formatter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';
import '../models/models.dart';

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
///
/// Platform behaviour:
/// - **Windows**: Opens a native "Save As" dialog so the user can choose the
///   destination folder and file name before writing.
/// - **Android / iOS**: Writes to the app documents directory then opens the
///   system share sheet.
/// - **macOS / Linux**: Writes to the Downloads folder then opens the share
///   sheet.
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

  /// Exports all data to a JSON file.
  ///
  /// - On **Windows**: shows a native Save-As dialog so the user picks the
  ///   destination folder and file name. Returns `null` if the user cancels.
  /// - On all other platforms: writes to the default export directory and
  ///   opens the system share sheet.
  ///
  /// Returns the final file path, or `null` if the user cancelled (Windows).
  Future<String?> exportAndShare() async {
    final jsonString = await _buildExportJson();

    if (Platform.isWindows) {
      return _exportWindows(jsonString);
    }

    final filePath = await _writeToFile(jsonString);
    await _shareFile(filePath);
    return filePath;
  }

  /// Exports all data and returns the raw JSON string (useful for testing or
  /// custom save flows).
  Future<String> exportToJsonString() => _buildExportJson();

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC: EXCEL EXPORT
  // ─────────────────────────────────────────────────────────────────────────

  /// Generates a well-organized Excel file containing:
  /// 1. General Summary (Totals)
  /// 2. Invoices Log
  /// 3. Customer Balances
  Future<String?> exportInvoicesToExcel() async {
    final excel = Excel.createExcel();

    // 1. Rename default Sheet1 to "الملخص العام"
    const String summarySheetName = 'الملخص العام';
    excel.rename(excel.getDefaultSheet()!, summarySheetName);

    // Fetch data
    final List<Invoice> invoices = await _dbService.getInvoices();
    final List<User> customers = await _dbService.getCustomers();

    // -- Sheet 1: الملخص العام --
    _buildSummarySheet(excel.sheets[summarySheetName]!, invoices, customers);

    // -- Sheet 2: سجل الفواتير --
    const String invoicesSheetName = 'سجل الفواتير';
    excel.updateCell(invoicesSheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue('Temporary')); // force creation
    _buildInvoicesSheet(excel.sheets[invoicesSheetName]!, invoices);

    // -- Sheet 3: أرصدة العملاء --
    const String customersSheetName = 'أرصدة العملاء';
    excel.updateCell(customersSheetName, CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue('Temporary')); // force creation
    _buildCustomersSheet(excel.sheets[customersSheetName]!, customers);

    // Save
    final List<int>? fileBytes = excel.save();
    if (fileBytes == null) return null;

    final String timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final String fileName = 'elegant_store_report_$timestamp.xlsx';

    if (Platform.isWindows) {
      return _saveExcelWindows(fileBytes, fileName);
    }

    final String filePath = await _writeBytesToFile(fileBytes, fileName);
    await _shareExcelFile(filePath);
    return filePath;
  }

  void _buildSummarySheet(Sheet sheet, List<Invoice> invoices, List<User> customers) {
    double totalSales = 0;
    double totalCollected = 0;
    double totalDebt = 0;

    for (final inv in invoices) {
      if (inv.type == 'SALE') {
        totalSales += inv.amount;
        totalCollected += inv.paidAmount;
      } else if (inv.type == 'DEPOSIT') {
        totalCollected += inv.amount;
      }
    }

    for (final c in customers) {
      if (c.balance > 0) totalDebt += c.balance;
    }

    // Styles
    final CellStyle headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#E2E8F0'),
      fontColorHex: ExcelColor.fromHexString('#0F172A'),
    );

    // Headers
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      ..value = TextCellValue('الإحصائية')
      ..cellStyle = headerStyle;
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0))
      ..value = TextCellValue('القيمة')
      ..cellStyle = headerStyle;

    // Data
    final List<List<dynamic>> data = [
      ['إجمالي المبيعات', totalSales],
      ['إجمالي المبالغ المحصلة', totalCollected],
      ['إجمالي الديون المستحقة', totalDebt],
      ['عدد الفواتير', invoices.length],
      ['عدد العملاء', customers.length],
      ['تاريخ التصدير', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())],
    ];

    for (int i = 0; i < data.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1)).value = _wrapCellValue(data[i][0]);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1)).value = _wrapCellValue(data[i][1]);
    }

    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 20);
  }

  void _buildInvoicesSheet(Sheet sheet, List<Invoice> invoices) {
    final CellStyle headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#0B74FF'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    final headers = ['التاريخ', 'العميل', 'النوع', 'المبلغ الإجمالي', 'المبلغ المدفوع', 'الحالة', 'ملاحظات'];
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = TextCellValue(headers[i])
        ..cellStyle = headerStyle;
    }

    for (int i = 0; i < invoices.length; i++) {
      final inv = invoices[i];
      final rowIdx = i + 1;
      
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue(inv.invoiceDate.toLocalShort());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = TextCellValue(inv.customerName ?? '-');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = TextCellValue(inv.type == 'SALE' ? 'بيع' : (inv.type == 'DEPOSIT' ? 'دفعة/إيداع' : inv.type));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = DoubleCellValue(inv.amount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx)).value = DoubleCellValue(inv.paidAmount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx)).value = TextCellValue(_translateStatus(inv.paymentStatus));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx)).value = TextCellValue(inv.notes ?? '');
    }

    sheet.setColumnWidth(0, 20);
    sheet.setColumnWidth(1, 25);
    sheet.setColumnWidth(2, 15);
    sheet.setColumnWidth(3, 15);
    sheet.setColumnWidth(4, 15);
    sheet.setColumnWidth(5, 15);
    sheet.setColumnWidth(6, 40);
  }

  void _buildCustomersSheet(Sheet sheet, List<User> customers) {
    final CellStyle headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: ExcelColor.fromHexString('#10B981'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );

    final headers = ['اسم العميل', 'رقم الهاتف', 'الرصيد الحالي', 'ملاحظات'];
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = TextCellValue(headers[i])
        ..cellStyle = headerStyle;
    }

    // Sort customers by balance (highest debt first)
    final sortedCustomers = List<User>.from(customers)
      ..sort((a, b) => b.balance.compareTo(a.balance));

    for (int i = 0; i < sortedCustomers.length; i++) {
      final c = sortedCustomers[i];
      final rowIdx = i + 1;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx)).value = TextCellValue(c.name);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx)).value = TextCellValue(c.phone ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx)).value = DoubleCellValue(c.balance);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx)).value = TextCellValue(c.notes ?? '');
    }

    sheet.setColumnWidth(0, 30);
    sheet.setColumnWidth(1, 20);
    sheet.setColumnWidth(2, 20);
    sheet.setColumnWidth(3, 40);
  }

  CellValue _wrapCellValue(dynamic val) {
    if (val == null) return TextCellValue('');
    if (val is String) return TextCellValue(val);
    if (val is int) return IntCellValue(val);
    if (val is double) return DoubleCellValue(val);
    if (val is bool) return BoolCellValue(val);
    return TextCellValue(val.toString());
  }

  String _translateStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PAID': return 'مدفوع';
      case 'UNPAID': return 'غير مدفوع';
      case 'DEFERRED': return 'آجل';
      case 'PARTIAL': return 'جزئي';
      default: return status;
    }
  }

  Future<String?> _saveExcelWindows(List<int> bytes, String fileName) async {
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ تقرير Excel',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (savePath == null) return null;

    final String finalPath = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
    final File file = File(finalPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> _writeBytesToFile(List<int> bytes, String fileName) async {
    final Directory dir = await _getExportDirectory();
    final File file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _shareExcelFile(String filePath) async {
    final XFile xFile = XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await Share.shareXFiles(
      [xFile],
      subject: 'Elegant Store — Excel Report',
      text: 'تقرير فواتير وأرصدة عملاء متجر Elegant Store',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE: WINDOWS — Save-As dialog
  // ─────────────────────────────────────────────────────────────────────────

  /// Opens the native Windows "Save As" dialog, writes the JSON to the chosen
  /// path, and returns that path. Returns `null` if the user cancels.
  Future<String?> _exportWindows(String jsonString) async {
    final String suggestedName =
        'elegant_store_export_${DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())}.json';

    // FilePicker.saveFile returns the full path chosen by the user, or null
    // if the dialog is dismissed.
    final String? savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ ملف التصدير',
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (savePath == null) {
      // User cancelled the dialog — nothing to do.
      debugPrint('[ExportService] Windows save dialog cancelled by user.');
      return null;
    }

    // Ensure the path ends with .json (some Windows versions strip the
    // extension when the user types a custom name without it).
    final String finalPath =
        savePath.endsWith('.json') ? savePath : '$savePath.json';

    final File file = File(finalPath);
    await file.writeAsString(jsonString, encoding: utf8, flush: true);
    debugPrint('[ExportService] Written to: ${file.path}');
    return file.path;
  }

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
          .map((row) =>
              _resolveRowForeignKeys(table, Map<String, dynamic>.from(row)))
          .toList();
    }

    final payload = {
      'meta': {
        'app': 'Elegant Store',
        'exported_at':
            DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(DateTime.now()),
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
        _replaceIdWithUuid(row, 'edited_by_id', 'edited_by_uuid', 'users');
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
  // PRIVATE: FILE I/O (non-Windows)
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
    // macOS / Linux — use the Downloads folder
    final downloads = await getDownloadsDirectory();
    return downloads ?? await getApplicationDocumentsDirectory();
  }

  Future<void> _shareFile(String filePath) async {
    // share_plus v10 API: Share.shareXFiles (static method)
    // Note: SharePlus.instance.share / ShareParams are only available in v11+
    final XFile xFile = XFile(filePath, mimeType: 'application/json');
    await Share.shareXFiles(
      [xFile],
      subject: 'Elegant Store — Database Export',
      text: 'ملف تصدير قاعدة بيانات متجر Elegant Store',
    );
  }
}
