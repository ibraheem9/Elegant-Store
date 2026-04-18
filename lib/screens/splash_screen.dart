import 'package:flutter/material.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  final VoidCallback onInitializationComplete;
  const SplashScreen({Key? key, required this.onInitializationComplete}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _moveAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    // Moves from left to center
    _moveAnimation = Tween<double>(begin: -1.5, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    // After animation and a short delay, signal completion
    Timer(const Duration(milliseconds: 3500), () {
      widget.onInitializationComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Matches the app's dark theme
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF0F172A),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_moveAnimation.value * size.width, 0),
                  child: Opacity(
                    opacity: _opacityAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The animated cart logo
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.2),
                                blurRadius: 50,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png', // Ensure this points to the new cart logo
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Text(
                          'ELEGANT STORE',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 60,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Bottom loading indicator
            Positioned(
              bottom: 80,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: const Column(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      ),
                    ),
                    SizedBox(height: 15),
                    Text(
                      'جاري التحميل...',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
