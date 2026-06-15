import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import '../services/import_service.dart';

class DatabaseSetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const DatabaseSetupScreen({super.key, required this.onSetupComplete});

  @override
  State<DatabaseSetupScreen> createState() => _DatabaseSetupScreenState();
}

class _DatabaseSetupScreenState extends State<DatabaseSetupScreen> {
  bool _isLoading = false;

  Future<void> _createNewDatabase() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_database_path');
      DatabaseService.setCustomPath(null);

      // Force initialize to create the file
      final dbService = DatabaseService();
      await dbService.initDatabase();
      
      widget.onSetupComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importFromJson() async {
    setState(() => _isLoading = true);
    try {
      // 1. Ensure we have a clean default database to import into
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_database_path');
      DatabaseService.setCustomPath(null);
      
      final dbService = DatabaseService();
      await dbService.initDatabase();

      // 2. Perform the import
      final importService = ImportService(dbService);
      final result = await importService.pickAndImport();

      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.green,
            ),
          );
          widget.onSetupComplete();
        } else if (result.message != 'لم يتم اختيار أي ملف.') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الاستيراد: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickExistingDatabase() async {
    setState(() => _isLoading = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
        dialogTitle: 'اختر ملف قاعدة البيانات (abd_elhadi_store.db)',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('custom_database_path', path);
        DatabaseService.setCustomPath(path);
        
        // Explicitly initialize to ensure seeding and connection are ready
        final dbService = DatabaseService();
        await dbService.initDatabase();
        
        widget.onSetupComplete();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_rounded, size: 64, color: Colors.blue),
                  const SizedBox(height: 24),
                  const Text(
                    'تنبيه: قاعدة البيانات غير موجودة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'يبدو أنه تم حذف ملف قاعدة البيانات أو نقله. يرجى اختيار إجراء للمتابعة:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else ...[
                    ElevatedButton.icon(
                      onPressed: _pickExistingDatabase,
                      icon: const Icon(Icons.file_open_rounded),
                      label: const Text('اختيار ملف قاعدة بيانات موجود'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _importFromJson,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('استيراد البيانات من نسخة احتياطية (JSON)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _createNewDatabase,
                      icon: const Icon(Icons.add_to_photos_rounded),
                      label: const Text('إنشاء قاعدة بيانات جديدة (فارغة)'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
