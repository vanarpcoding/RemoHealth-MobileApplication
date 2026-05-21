import 'package:flutter/material.dart';
import 'package:healthcarenew/login.dart';
import 'dart:ui';

void main() => runApp(DoctorApp());

class DoctorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Montserrat', // Use a clean font if available
      ),
      home: IntroScreen(),
    );
  }
}

class IntroScreen extends StatefulWidget {
  @override
  _IntroScreenState createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _numPages = 3;

  List<Color> gradientColors = [
    Color(0xFF2196F3), // Blue
    Color(0xFF3F51B5), // Indigo
    Color(0xFF1976D2), // Darker Blue
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      int next = _pageController.page!.round();
      if (_currentPage != next) {
        setState(() {
          _currentPage = next;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated Background Gradient
          AnimatedContainer(
            duration: Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  gradientColors[_currentPage],
                  gradientColors[_currentPage].withOpacity(0.7),
                ],
              ),
            ),
          ),
          
          // Background Design Elements
          Positioned(
            top: -120,
            right: -100,
            child: Container(
              height: 300,
              width: 300,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -120,
            child: Container(
              height: 350,
              width: 350,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          
          // Main Content with PageView
          Container(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: [
                      // First Page
                      EnhancedIntroPage(
                        imagePath: 'assets/images/intoimage.jpg',
                        title: 'Remote Health Monitoring',
                        description:
                            'Remote Health Care Monitoring and Alert Generation using AI/ML.',
                        index: 0,
                        currentPage: _currentPage,
                      ),

                      // Second Page
                      EnhancedIntroPage(
                        imagePath: 'assets/images/swipe2.jpeg.jpg',
                        title: 'AI-Powered Insights',
                        description:
                            'Get real-time health analytics powered by AI and Machine Learning.',
                        index: 1,
                        currentPage: _currentPage,
                      ),

                      // Third Page
                      EnhancedIntroPage(
                        imagePath: 'assets/images/swipe3.jpeg.jpg',
                        title: 'Seamless Patient Care',
                        description:
                            'Monitor patients remotely and provide timely assistance.',
                        index: 2,
                        currentPage: _currentPage,
                      ),
                    ],
                  ),
                ),
                
                // Bottom Navigation and Indicators
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    children: [
                      // Page Indicators
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _numPages,
                          (index) => buildPageIndicator(index),
                        ),
                      ),
                      SizedBox(height: 30),
                      
                      // Navigation Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Skip Button
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const Login()),
                              );
                            },
                            child: Text(
                              'Skip',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          
                          // Next or Get Started Button
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: gradientColors[_currentPage],
                              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 5,
                              shadowColor: Colors.black26,
                            ),
                            onPressed: () {
                              if (_currentPage == _numPages - 1) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const Login()),
                                );
                              } else {
                                _pageController.nextPage(
                                  duration: Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                );
                              }
                            },
                            child: Text(
                              _currentPage == _numPages - 1 ? 'Get Started' : 'Next',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPageIndicator(int index) {
    bool isCurrentPage = index == _currentPage;
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      margin: EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: isCurrentPage ? 24 : 8,
      decoration: BoxDecoration(
        color: isCurrentPage ? Colors.white : Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

// Enhanced Intro Page with Animations
class EnhancedIntroPage extends StatelessWidget {
  final String imagePath;
  final String title;
  final String description;
  final int index;
  final int currentPage;

  const EnhancedIntroPage({
    required this.imagePath,
    required this.title,
    required this.description,
    required this.index,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    // Control animation based on page visibility
    bool isVisible = index == currentPage;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Top Spacing
          SizedBox(height: 60),
          
          // Image with Animation
          AnimatedOpacity(
            duration: Duration(milliseconds: 500),
            opacity: isVisible ? 1.0 : 0.0,
            child: AnimatedPadding(
              duration: Duration(milliseconds: 800),
              padding: isVisible ? EdgeInsets.zero : EdgeInsets.only(top: 50),
              child: Container(
                height: 280,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 50),
          
          // Title with Animation
          AnimatedOpacity(
            duration: Duration(milliseconds: 500),
            opacity: isVisible ? 1.0 : 0.0,
            child: AnimatedPadding(
              duration: Duration(milliseconds: 800),
              padding: isVisible ? EdgeInsets.zero : EdgeInsets.only(top: 20),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(height: 20),
          
          // Description with Animation
          AnimatedOpacity(
            duration: Duration(milliseconds: 500),
            opacity: isVisible ? 1.0 : 0.0,
            //delay: Duration(milliseconds: 200),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  height: 1.5,
                  letterSpacing: 0.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}