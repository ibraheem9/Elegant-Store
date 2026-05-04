import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

class SyncDetailsScreen extends StatefulWidget {
  const SyncDetailsScreen({Key? key}) : super(key: key);

  @override
  State<SyncDetailsScreen> createState() => _SyncDetailsScreenState();
}

class _SyncDetailsScreenState extends State<SyncDetailsScreen> {
  bool _isResetting = false;
  bool _isRestoring = false;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';

  Map<String, int> _unsyncedCounts = {};
  Map<String, int> _totalCounts = {};
  List<Map<String, dynamic>> _duplicateCustomers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final db = context.read<DatabaseService>();
    final unsynced = await db.getUnsyncedCounts();
    final totals = await db.getTotalCounts();
    final duplicates = await db.getDuplicateCustomers();
    if (mounted) {
      setState(() {
        _unsyncedCounts = unsynced;
        _totalCounts = totals;
        _duplicateCustomers = duplicates;
        _loading = false;
      });
    }
  }

  int get _totalUnsynced =>
      _unsyncedCounts.values.fold(0, (sum, v) => sum + v);

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_download_rounded, color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('استعادة كاملة من السيرفر',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          content: const Text(
            'سيتم تحميل جميع البيانات النشطة من السيرفر وكتابتها محلياً.\n\nالسجلات المحذوفة لن تُستعاد (وهذا صحيح).\n\nهذا لا يحذف أي شيء من السيرفر.\n\nهل تريد المتابعة؟',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _isRestoring = true);
    try {
      final syncService = context.read<SyncService>();
      await syncService.performFullRestore();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          const SnackBar(
            content: Text('تمت الاستعادة الكاملة من السيرفر بنجاح ✓'),
            backgroundColor: Colors.teal,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          SnackBar(
            content: Text('فشلت الاستعادة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _handleExport() async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportStatus = 'جاري الاتصال بالسيرفر…';
    });
    try {
      final syncService = context.read<SyncService>();
      final filePath = await syncService.downloadFullExport(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _exportProgress = progress;
              _exportStatus = status;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('تم تصدير البيانات بنجاح ✓\n$filePath'),
              backgroundColor: Colors.indigo,
              duration: const Duration(seconds: 6),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('فشل التصدير: $e'),
              backgroundColor: Colors.red,
            ),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
          _exportStatus = '';
        });
      }
    }
  }

  Future<void> _confirmAndReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildResetConfirmDialog(ctx),
    );
    if (confirmed != true) return;

    setState(() => _isResetting = true);
    try {
      final db = context.read<DatabaseService>();
      final prefs = await SharedPreferences.getInstance();

      await db.clearAllDataAndReset();
      await prefs.remove('last_sync_time');

      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          const SnackBar(
            content: Text('تم مسح جميع البيانات المحلية. سيتم تحميل البيانات عند المزامنة التالية.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        await _loadStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(
          SnackBar(
            content: Text('فشل إعادة التهيئة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final syncService = context.read<SyncService>();
    final details = syncService.lastSyncDetails;

    String lastSyncDisplay = 'لم تتم مزامنة بعد';
    if (details != null && details.lastSyncTime.isNotEmpty) {
      try {
        final dt = DateTime.parse(details.lastSyncTime);
        lastSyncDisplay = DateFormat('yyyy/MM/dd  hh:mm a', 'ar').format(dt);
      } catch (_) {
        lastSyncDisplay = details.lastSyncTime;
      }
    }

    return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
        appBar: AppBar(
          title: const Text('تفاصيل المزامنة', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          foregroundColor: isDark ? Colors.white : Colors.black87,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث الإحصائيات',
              onPressed: _loading ? null : _loadStats,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadStats,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Last Sync Summary Card ─────────────────────────
                      _buildSectionCard(
                        isDark: isDark,
                        icon: Icons.cloud_done_rounded,
                        iconColor: details != null ? Colors.green : Colors.grey,
                        title: 'آخر عملية مزامنة',
                        child: Column(
                          children: [
                            _buildInfoRow('وقت المزامنة', lastSyncDisplay, Icons.access_time_rounded, isDark),
                            if (details != null) ...[
                              const Divider(height: 24),
                              Row(
                                children: [
                                  Expanded(child: _buildCountTile('مرفوع — زبائن', details.customersUploaded, Colors.green, isDark)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildCountTile('مرفوع — فواتير', details.invoicesUploaded, Colors.green, isDark)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(child: _buildCountTile('محمّل — زبائن', details.customersDownloaded, Colors.blue, isDark)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildCountTile('محمّل — فواتير', details.invoicesDownloaded, Colors.blue, isDark)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Unsynced Records Card ──────────────────────────
                      _buildSectionCard(
                        isDark: isDark,
                        icon: _totalUnsynced > 0
                            ? Icons.sync_problem_rounded
                            : Icons.check_circle_rounded,
                        iconColor: _totalUnsynced > 0 ? Colors.orange : Colors.green,
                        title: 'السجلات غير المزامنة',
                        trailing: _totalUnsynced > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '$_totalUnsynced سجل',
                                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              )
                            : null,
                        child: _totalUnsynced == 0
                            ? _buildEmptyState('جميع السجلات مزامنة مع السيرفر ✓', Colors.green, isDark)
                            : Column(
                                children: [
                                  _buildWarningBanner(
                                    'يوجد $_totalUnsynced سجل لم يُرفع للسيرفر بعد. قم بالمزامنة لضمان عدم فقدان البيانات.',
                                    Colors.orange,
                                    isDark,
                                  ),
                                  const SizedBox(height: 16),
                                  ..._unsyncedCounts.entries
                                      .where((e) => e.value > 0)
                                      .map((e) => _buildTableRow(
                                            _tableLabel(e.key),
                                            e.value,
                                            Colors.orange,
                                            isDark,
                                          )),
                                ],
                              ),
                      ),
                      const SizedBox(height: 20),

                      // ── Total Records Card ─────────────────────────────
                      _buildSectionCard(
                        isDark: isDark,
                        icon: Icons.storage_rounded,
                        iconColor: Colors.blue,
                        title: 'إجمالي السجلات المحلية',
                        child: Column(
                          children: _totalCounts.entries
                              .map((e) => _buildTableRow(
                                    _tableLabel(e.key),
                                    e.value,
                                    Colors.blue,
                                    isDark,
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Duplicate Customers Card ───────────────────────
                      _buildSectionCard(
                        isDark: isDark,
                        icon: _duplicateCustomers.isNotEmpty
                            ? Icons.warning_amber_rounded
                            : Icons.people_alt_rounded,
                        iconColor: _duplicateCustomers.isNotEmpty ? Colors.red : Colors.green,
                        title: 'تكرار أسماء الزبائن',
                        trailing: _duplicateCustomers.isNotEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_duplicateCustomers.length} تكرار',
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              )
                            : null,
                        child: _duplicateCustomers.isEmpty
                            ? _buildEmptyState('لا يوجد تكرار في أسماء الزبائن ✓', Colors.green, isDark)
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildWarningBanner(
                                    'تم اكتشاف زبائن بنفس الاسم. سيتم دمجهم تلقائياً عند المزامنة مع السيرفر.',
                                    Colors.red,
                                    isDark,
                                  ),
                                  const SizedBox(height: 16),
                                  ..._duplicateCustomers.map((d) => _buildDuplicateRow(d, isDark)),
                                ],
                              ),
                      ),
                      const SizedBox(height: 20),

                      // ── Merged Customers Card ──────────────────────────
                      if (details != null && details.mergedCustomers.isNotEmpty) ...[
                        _buildSectionCard(
                          isDark: isDark,
                          icon: Icons.merge_type_rounded,
                          iconColor: Colors.purple,
                          title: 'الزبائن الذين تم دمجهم',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildWarningBanner(
                                'تم دمج هؤلاء الزبائن تلقائياً لتطابق أسمائهم عبر أجهزة مختلفة.',
                                Colors.purple,
                                isDark,
                              ),
                              const SizedBox(height: 12),
                              ...details.mergedCustomers.map(
                                (name) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.person_rounded, size: 16, color: Colors.purple),
                                      const SizedBox(width: 8),
                                      Flexible(child: Text(name, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87), overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Action Buttons ─────────────────────────────────
                      _buildActionButtons(isDark),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
      );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCountTile(String label, int count, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(String label, int count, Color color, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateRow(Map<String, dynamic> d, bool isDark) {
    final name = d['name'] as String? ?? '';
    final count = d['count'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_rounded, size: 16, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count نسخ',
              style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(String message, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, Color color, bool isDark) {
    return Row(
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            message,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Consumer<SyncService>(
      builder: (context, syncService, _) {
        final isRestoring = _isRestoring || (syncService.isSyncing && syncService.restoreProgress > 0);
        final progress = syncService.restoreProgress;
        final statusText = syncService.restoreStatus;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Progress bar (visible only during restore) ─────────────────
            if (isRestoring) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.teal.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.cloud_download_rounded, color: Colors.teal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusText.isNotEmpty ? statusText : 'جاري الاستعادة…',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 8,
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.teal.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Full Restore from Server button ────────────────────────────
            ElevatedButton.icon(
              onPressed: (_isResetting || isRestoring || _isExporting) ? null : _handleRestore,
              icon: isRestoring
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_download_rounded, color: Colors.white),
              label: Text(
                isRestoring ? 'جاري الاستعادة...' : 'استعادة كاملة من السيرفر',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Export progress bar (visible only during export) ────────────
            if (_isExporting) ...[  
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.indigo.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.file_download_rounded, color: Colors.indigo, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _exportStatus.isNotEmpty ? _exportStatus : 'جاري التصدير…',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          '${(_exportProgress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _exportProgress > 0 ? _exportProgress : null,
                        minHeight: 8,
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.indigo.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Export JSON button ───────────────────────────────────────
            ElevatedButton.icon(
              onPressed: (_isResetting || isRestoring || _isExporting) ? null : _handleExport,
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.file_download_rounded, color: Colors.white),
              label: Text(
                _isExporting ? 'جاري التصدير...' : 'تصدير قاعدة البيانات JSON',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildResetConfirmDialog(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('تأكيد مسح البيانات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم حذف جميع البيانات المحلية من الجهاز، بما في ذلك:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ...[
              'جميع الزبائن والمحاسبين',
              'جميع الفواتير والمعاملات',
              'جميع المشتريات والإحصائيات',
              'طرق الدفع والسجل التاريخي',
            ].map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(Icons.remove_circle_outline, size: 14, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(item, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'البيانات على السيرفر لن تُحذف. ستُستعاد عند المزامنة التالية.',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.developer_mode_rounded, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'حساب المطور (ibraheem / 123) سيُعاد زرعه تلقائياً بعد المسح.',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('نعم، امسح البيانات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  String _tableLabel(String table) {
    const labels = {
      'users': 'الزبائن والمستخدمين',
      'invoices': 'الفواتير',
      'transactions': 'المعاملات المالية',
      'purchases': 'المشتريات',
      'payment_methods': 'طرق دفع المبيعات',

      'daily_statistics': 'الإحصائيات اليومية',
      'edit_history': 'سجل التعديلات',
    };
    return labels[table] ?? table;
  }
}
