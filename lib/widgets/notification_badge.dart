import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../screens/notifications_screen.dart';

class NotificationBadge extends StatelessWidget {
  final bool isDark;

  const NotificationBadge({
    Key? key,
    required this.isDark,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>();

    return ValueListenableBuilder<int>(
      valueListenable: db.notificationCountNotifier,
      builder: (context, count, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
                // Refresh count when returning, just in case
                db.refreshNotificationCount();
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  count > 0 ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                  color: count > 0 
                      ? Colors.orange 
                      : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF64748B)),
                  size: 22,
                ),
              ),
            ),
            if (count > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: isDark ? const Color(0xFF071028) : Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
