import 'package:flutter/material.dart';

class TutorialScreen extends StatefulWidget {
  final bool showSkip;
  const TutorialScreen({Key? key, this.showSkip = true}) : super(key: key);

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _tutorialData = [
    {
      'title': 'لوحة التحكم الذكية',
      'description': 'تابع أداء متجرك، مبيعاتك اليومية، وديون الزبائن في مكان واحد وبشكل مبسط.',
      'image': 'assets/1 (1).png', // Using existing assets if they look relevant
      'icon': 'dashboard',
    },
    {
      'title': 'شاشة بيع سريعة',
      'description': 'أنشئ فواتير البيع بسرعة فائقة، وأدر طرق الدفع المختلفة بكل سهولة.',
      'image': 'assets/1 (2).png',
      'icon': 'receipt',
    },
    {
      'title': 'إدارة الزبائن والديون',
      'description': 'سجل بيانات زبائنك، تابع أرصدتهم، وقم بتذكيرهم بالديون غير المسددة.',
      'image': 'assets/1 (3).png',
      'icon': 'people',
    },
    {
      'title': 'تصدير البيانات ونسخها',
      'description': 'يمكنك تصدير بياناتك بصيغة JSON وحفظها في جوجل درايف أو أي مكان آمن لضمان عدم فقدانها.',
      'image': 'assets/logo.png',
      'icon': 'export',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.showSkip)
              Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تخطي', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                ),
              ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: _tutorialData.length,
                itemBuilder: (context, index) {
                  return _buildPage(
                    _tutorialData[index]['title']!,
                    _tutorialData[index]['description']!,
                    _tutorialData[index]['image']!,
                    _tutorialData[index]['icon']!,
                    isDark,
                  );
                },
              ),
            ),
            _buildBottomControls(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(String title, String description, String imagePath, String iconType, bool isDark) {
    IconData icon;
    Color iconColor;
    switch (iconType) {
      case 'dashboard': icon = Icons.dashboard_rounded; iconColor = Colors.blue; break;
      case 'receipt': icon = Icons.receipt_long_rounded; iconColor = Colors.green; break;
      case 'people': icon = Icons.people_alt_rounded; iconColor = Colors.orange; break;
      case 'export': icon = Icons.ios_share_rounded; iconColor = Colors.purple; break;
      default: icon = Icons.help_outline_rounded; iconColor = Colors.blue;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: iconColor.withOpacity(0.1)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: -20,
                  right: -20,
                  child: Icon(icon, size: 200, color: iconColor.withOpacity(0.05)),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 80, color: iconColor),
                    ),
                    const SizedBox(height: 30),
                    Image.asset('assets/logo.png', height: 40, color: isDark ? Colors.white24 : Colors.black12),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),
          Text(
            title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            description,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white70 : Colors.black54,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Indicators
          Row(
            children: List.generate(
              _tutorialData.length,
              (index) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                height: 8,
                width: _currentPage == index ? 24 : 8,
                decoration: BoxDecoration(
                  color: _currentPage == index ? Colors.blue : Colors.blue.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          // Next/Finish Button
          ElevatedButton(
            onPressed: () {
              if (_currentPage < _tutorialData.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              } else {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_currentPage < _tutorialData.length - 1 ? 'التالي' : 'ابدأ الآن'),
          ),
        ],
      ),
    );
  }
}
