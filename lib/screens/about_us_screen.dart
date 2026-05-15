import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('عن المطور', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: isDark ? Colors.white : Colors.black,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 40,
            vertical: 20,
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Developer Logo ---
                  Hero(
                    tag: 'dev_logo',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          )
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          height: 140,
                          width: 140,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.person_pin_rounded,
                            size: 120,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // --- Name & Title ---
                  Text(
                    'إبراهيم عبد الهادي',
                    style: TextStyle(
                      fontSize: isMobile ? 30 : 38,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Software Systems Engineer',
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueAccent,
                      letterSpacing: 0.8,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- Bio Section ---
                  _buildSectionCard(
                    isDark,
                    title: 'نبذة تعريفية',
                    icon: Icons.person_outline_rounded,
                    child: const Text(
                      'مهندس أنظمة برمجيات بخبرة تزيد عن 7 سنوات متمرس في تطوير وتصميم الويب. متخصص في بيئة PHP/Laravel، مع خبرة واسعة في إدارة المشاريع المستقلة والعمل الجماعي. ترتكز فلسفتي المهنية على دقة تصميم قواعد البيانات والتحليل العميق للأنظمة لضمان جودة البرمجيات.',
                      style: TextStyle(height: 1.8, fontSize: 16),
                      textAlign: TextAlign.justify,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- Skills Grid ---
                  _buildSectionCard(
                    isDark,
                    title: 'المهارات التقنية',
                    icon: Icons.psychology_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('البنية التحتية والأنظمة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildSkillChip('Laravel (Expert)', Colors.orange),
                            _buildSkillChip('PHP', Colors.blue),
                            _buildSkillChip('SQL', Colors.indigo),
                            _buildSkillChip('System Analysis', Colors.purple),
                            _buildSkillChip('Database Design', Colors.teal),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Text('الواجهات الأمامية:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _buildSkillChip('Vue.js', Colors.green),
                            _buildSkillChip('Bootstrap', Colors.deepPurple),
                            _buildSkillChip('JavaScript/jQuery', Colors.amber),
                            _buildSkillChip('UI/UX Optimization', Colors.pink),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- Contact Section ---
                  _buildSectionCard(
                    isDark,
                    title: 'تواصل معي',
                    icon: Icons.alternate_email_rounded,
                    child: Column(
                      children: [
                        _buildContactTile(
                          icon: Icons.email_outlined,
                          label: 'ibraheem7hadi@gmail.com',
                          onTap: () => _launchUrl('mailto:ibraheem7hadi@gmail.com'),
                        ),
                        _buildContactTile(
                          icon: Icons.phone_android_outlined,
                          label: '+970 567 228380',
                          onTap: () => _launchUrl('tel:+970567228380'),
                        ),
                        _buildContactTile(
                          icon: Icons.public_outlined,
                          label: 'ibraheem.vironna.com',
                          onTap: () => _launchUrl('https://ibraheem.vironna.com/'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 50),

                  // --- Footer ---
                  Opacity(
                    opacity: 0.6,
                    child: Column(
                      children: [
                        const Text(
                          'تم التطوير بكل شغف بواسطة إبراهيم عبد الهادي',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '© ${DateTime.now().year} All Rights Reserved',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(bool isDark, {required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.blueAccent, size: 22),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildSkillChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildContactTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: Colors.blueAccent, size: 24),
        title: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
        ),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
