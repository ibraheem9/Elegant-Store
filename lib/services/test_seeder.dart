import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'database_service.dart';

class TestSeeder {
  /// Runs the seeding process for Mohammad Store.
  /// This will:
  /// 1. Delete all current data from the mobile DB.
  /// 2. Create the manager 'mohammad'.
  /// 3. Create the specific payment methods.
  /// 4. Create 67 customers with usernames buyer_1 to buyer_67.
  static Future<void> run(BuildContext context) async {
    try {
      final db = Provider.of<DatabaseService>(context, listen: false);
      await db.seedMohammadStoreData();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تهيئة بيانات متجر محمد (67 زبون) بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء التهيئة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
