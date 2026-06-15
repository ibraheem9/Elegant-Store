import 'contact_us_screen.dart';
import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        title: const Text('دليل الاستخدام', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF071028) : Colors.white,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHelpSection(
            context,
            'إدارة المبيعات',
            Icons.receipt_long_rounded,
            [
              _HelpItem(
                'كيفية إنشاء فاتورة بيع؟',
                '1. انتقل إلى شاشة "البيع".\n2. اختر الزبون من القائمة أو أضف زبوناً جديداً.\n3. أضف الأصناف والأسعار المطلوبة.\n4. اختر طريقة الدفع المناسبة.\n5. اضغط على "حفظ" لإتمام العملية.',
              ),
              _HelpItem(
                'تعديل أو حذف فاتورة؟',
                'يمكنك الوصول للفواتير السابقة من خلال "مراجعة المدفوعات" أو من ملف الزبون الشخصي، حيث تظهر قائمة بآخر العمليات.',
              ),
            ],
            isDark,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            'الزبائن والديون',
            Icons.people_alt_rounded,
            [
              _HelpItem(
                'إضافة زبون جديد؟',
                'انتقل إلى شاشة "إدارة الزبائن" واضغط على أيقونة الإضافة (+)، ثم أدخل اسم الزبون ورقم هاتفه.',
              ),
              _HelpItem(
                'متابعة ديون الزبائن؟',
                'من خلال "أرصدة الزبائن" يمكنك رؤية المبالغ المستحقة على كل زبون بشكل مفصل.',
              ),
            ],
            isDark,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            'نسخ البيانات احتياطياً',
            Icons.backup_rounded,
            [
              _HelpItem(
                'كيف أقوم بحفظ نسخة من بياناتي؟',
                '1. انتقل إلى شاشة "تصدير البيانات".\n2. اضغط على زر "تصدير بصيغة JSON".\n3. اختر مكاناً آمناً لحفظ الملف مثل Google Drive أو إرساله لنفسك عبر الواتساب.',
              ),
              _HelpItem(
                'لماذا يجب علي التصدير يدوياً؟',
                'في هذا الإصدار، لا تتوفر مزامنة سحابية تلقائية، لذا من الضروري تصدير بياناتك دورياً لضمان عدم ضياعها في حال حدوث مشكلة للهاتف.',
              ),
            ],
            isDark,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            'الإعدادات والأمان',
            Icons.security_rounded,
            [
              _HelpItem(
                'ما هو مفتاح الاستعادة؟',
                'هو رمز فريد خاص بك يستخدم لاستعادة حسابك. يجب حفظه في مكان آمن جداً خارج الهاتف.',
              ),
              _HelpItem(
                'تغيير السمة (داكن/فاتح)؟',
                'يمكنك تغيير مظهر التطبيق من شاشة "الإعدادات والسمة".',
              ),
            ],
            isDark,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactUsScreen()));
            },
            icon: const Icon(Icons.support_agent_rounded),
            label: const Text('تواصل مع الدعم الفني'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'Abd Elhadi Store v1.0.0',
              style: TextStyle(color: isDark ? Colors.white30 : Colors.black26, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection(BuildContext context, String title, IconData icon, List<_HelpItem> items, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: items.map((item) => _buildHelpItem(item, isDark)).toList(),
      ),
    );
  }

  Widget _buildHelpItem(_HelpItem item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.question,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            item.answer,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, height: 1.5),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

class _HelpItem {
  final String question;
  final String answer;
  _HelpItem(this.question, this.answer);
}
