import 'dart:async';
import 'package:flutter/material.dart';
//import 'package:healthcarenew/homepage.dart';
import 'package:healthcarenew/setup.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as math;

class Secondpage extends StatefulWidget {
  @override
  _SecondpageScreenState createState() => _SecondpageScreenState();
}

class _SecondpageScreenState extends State<Secondpage> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _pulseAnimation;
  String statusMessage = "Initializing...";
  int currentStep = 0;
  bool _isCompleted = false;

  final List<Map<String, dynamic>> steps = [
    {
      "message": "Verifying credentials",
      "icon": Icons.verified_user_outlined,
      "description": "Securely validating your login information"
    },
    {
      "message": "Requesting health data access",
      "icon": Icons.health_and_safety_outlined,
      "description": "Ensuring access to necessary health monitoring features"
    },
    {
      "message": "Syncing health profile",
      "icon": Icons.sync,
      "description": "Setting up your personalized health dashboard"
    },
    {
      "message": "Finalizing setup",
      "icon": Icons.check_circle_outline,
      "description": "Almost ready to monitor your health"
    },
  ];

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _navigateThroughSteps();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _controller.forward();
  }
  
  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: () {
            openAppSettings();
          },
        ),
      ),
    );
  }

  Future<void> _navigateThroughSteps() async {
    for (int i = 0; i < steps.length; i++) {
      if (!mounted) return;
      
      setState(() {
        currentStep = i;
        statusMessage = steps[i]["message"] ?? "Processing...";
      });

      if (i == 1) {
        // Request health data access (e.g., sensors, camera, etc.)
        final status = await Permission.sensors.request();
        if (!status.isGranted) {
          _showError("Health data access is required for the app to function properly.");
        }
      }

      await Future.delayed(const Duration(seconds: 2));
    }
    
    if (!mounted) return;
    
    setState(() {
      _isCompleted = true;
    });
    
    await Future.delayed(const Duration(seconds: 1));
    
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => Setup(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A237E), // Deep indigo
              Color(0xFF303F9F), // Indigo
              Color(0xFF1976D2), // Blue
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _slideAnimation.value),
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Stack(
                    children: [
                      // Background decorative elements
                      Positioned(
                        top: -100,
                        right: -100,
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -150,
                        left: -70,
                        child: Container(
                          width: 300,
                          height: 300,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                      
                      // Main content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Logo with pulse animation
                            AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _isCompleted ? 1.0 : _pulseAnimation.value,
                                  child: Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withOpacity(0.1),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      height: 120,
                                      width: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withOpacity(0.9),
                                            Colors.white.withOpacity(0.7),
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: _isCompleted
                                            ? Icon(
                                                Icons.check,
                                                size: 60,
                                                color: Color(0xFF1976D2),
                                              )
                                            : Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  // Animated wave background
                                                  AnimatedBuilder(
                                                    animation: _waveController,
                                                    builder: (context, child) {
                                                      return CustomPaint(
                                                        size: Size(60, 60),
                                                        painter: HeartbeatPainter(
                                                          progress: _waveController.value,
                                                          color: Color(0xFF1976D2),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  Icon(
                                                    Icons.monitor_heart,
                                                    size: 60,
                                                    color: Color(0xFF1976D2),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            ),
                            const SizedBox(height: 32),
                            
                            // App title
                            Text(
                              "REMOHEALTH",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 3.0,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              "HEALTH MONITORING SYSTEM",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.7),
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 40),
                            
                            // Status message
                            AnimatedSwitcher(
                              duration: Duration(milliseconds: 300),
                              child: Text(
                                _isCompleted ? "Setup Complete!" : statusMessage,
                                key: ValueKey<String>(_isCompleted ? "complete" : statusMessage),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: _isCompleted ? Colors.greenAccent : Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(height: 8),
                            
                            // Current step description
                            AnimatedSwitcher(
                              duration: Duration(milliseconds: 300),
                              child: Text(
                                _isCompleted 
                                    ? "Redirecting to your profile setup..." 
                                    : (steps[currentStep]["description"] ?? ""),
                                key: ValueKey<String>(_isCompleted 
                                    ? "redirect" 
                                    : (steps[currentStep]["description"] ?? "")),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            
                            // Progress steps
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: Column(
                                children: List.generate(steps.length, (index) {
                                  final isActive = index <= currentStep;
                                  final isCompleted = index < currentStep || _isCompleted;
                                  final isCurrentStep = index == currentStep && !_isCompleted;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: Row(
                                      children: [
                                        // Step indicator
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isCompleted
                                                ? Colors.greenAccent
                                                : isCurrentStep
                                                    ? Colors.white.withOpacity(0.9)
                                                    : Colors.white.withOpacity(0.2),
                                            boxShadow: isActive
                                                ? [
                                                    BoxShadow(
                                                      color: isCompleted
                                                          ? Colors.greenAccent.withOpacity(0.5)
                                                          : Colors.white.withOpacity(0.2),
                                                      blurRadius: 8,
                                                      spreadRadius: 2,
                                                    )
                                                  ]
                                                : [],
                                          ),
                                          child: Center(
                                            child: Icon(
                                              isCompleted
                                                  ? Icons.check
                                                  : steps[index]["icon"],
                                              color: isCompleted
                                                  ? Colors.white
                                                  : isCurrentStep
                                                      ? Color(0xFF1976D2)
                                                      : Colors.white.withOpacity(0.5),
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        
                                        // Step text
                                        Expanded(
                                          child: Opacity(
                                            opacity: isActive ? 1.0 : 0.5,
                                            child: Text(
                                              steps[index]["message"] ?? "",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: isCurrentStep
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                                color: isCompleted
                                                    ? Colors.greenAccent
                                                    : Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(height: 40),
                            
                            // Progress indicator
                            AnimatedOpacity(
                              duration: Duration(milliseconds: 300),
                              opacity: _isCompleted ? 0.0 : 1.0,
                              child: Container(
                                width: 50,
                                height: 50,
                                padding: EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.1),
                                ),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Custom painter for heartbeat animation
class HeartbeatPainter extends CustomPainter {
  final double progress;
  final Color color;
  
  HeartbeatPainter({required this.progress, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
      
    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw the heartbeat line
    final path = Path();
    path.moveTo(0, size.height * 0.5);
    
    // First part of the heartbeat
    path.lineTo(size.width * 0.3, size.height * 0.5);
    path.lineTo(size.width * 0.4, size.height * 0.2);
    path.lineTo(size.width * 0.5, size.height * 0.8);
    path.lineTo(size.width * 0.6, size.height * 0.2);
    path.lineTo(size.width * 0.7, size.height * 0.5);
    path.lineTo(size.width, size.height * 0.5);
    
    // Calculate the progress offset
    final pathMetrics = path.computeMetrics().first;
    final extractPath = pathMetrics.extractPath(
      0.0,
      pathMetrics.length * progress,
    );
    
    canvas.drawPath(extractPath, paint);
  }
  
  @override
  bool shouldRepaint(HeartbeatPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}