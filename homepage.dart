import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:healthcarenew/chatbot.dart';
import 'package:healthcarenew/disease_predictions_page.dart';
import 'package:healthcarenew/ecg_page.dart';
import 'package:healthcarenew/seizure_alert_service.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: GoogleFonts.poppins().fontFamily,
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        fontFamily: GoogleFonts.poppins().fontFamily,
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HealthData {
  final double temperatureC;
  final double temperatureF;
  final int bpm;
  final double spo2;
  final String timestamp;
  final String? anomaly;
  final bool fallDetected;

  HealthData({
    required this.temperatureC,
    required this.temperatureF,
    required this.bpm,
    required this.spo2,
    required this.timestamp,
    this.anomaly,
    this.fallDetected = false,
  });

  factory HealthData.fromRealtimeDatabase(Map<String, dynamic> data) {
    dynamic safeParse(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value;
      if (value is String) {
        final parsed = double.tryParse(value);
        return parsed ?? 0;
      }
      return 0;
    }

    return HealthData(
      temperatureC: (safeParse(data['temperature_C']) as num).toDouble(),
      temperatureF: (safeParse(data['temperature_F']) as num).toDouble(),
      bpm: (safeParse(data['bpm']) as num).toInt(),
      spo2: (safeParse(data['spo2']) as num).toDouble(),
      timestamp: data['timestamp']?.toString() ?? '',
      anomaly: data['anomaly']?.toString(),
      fallDetected: data['fall_detected'] ?? false,
    );
  }

  List<String> detectAnomalies() {
    List<String> anomalies = [];
    if (bpm < 60) anomalies.add("Heart Rate (too low)");
    else if (bpm > 100) anomalies.add("Heart Rate (too high)");
    if (spo2 < 95) anomalies.add("SpO2 (too low)");
    if (temperatureC < 36.1) anomalies.add("Temperature (too low)");
    else if (temperatureC > 37.2) anomalies.add("Temperature (too high)");
    return anomalies;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  HealthData? healthData;
  List<String> anomalies = [];
  final String esp32Url = 'http://116.68.83.190/setuid';
  String? _fcmToken;
  auth.AutoRefreshingAuthClient? _authClient;
  late AnimationController _animationController;
  late AnimationController _pulseAnimationController;
  bool _isRefreshing = false;
  int _predictionCount = 0;
  String? _latestDiseasePrediction;
  String? _latestSeizurePrediction;
  String? _latestSeizureProb;
  String? _latestSeizureConf;
  DatabaseReference? _predictionsRef;
  StreamSubscription? _predictionsCountSubscription;
  final DatabaseReference _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://healthcareapp-361d0-default-rtdb.firebaseio.com',
  ).ref();
  StreamSubscription? _healthDataSubscription;

  // ─────────────────────────────────────────────────────────────────
  // initState — ALL setup code lives here, inside this method
  // ─────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    sendUidToEsp32();

    _setupFCM().then((_) {
      print('FCM setup completed');
    }).catchError((e) {
      print('FCM setup error: $e');
    });

    _startListeningToHealthData();
    _startListeningToPredictions();

    // ── SeizureAlertService init ────────────────────────────────────
    // Must use addPostFrameCallback so 'context' is valid on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SeizureAlertService.instance.init(
        context,
        userId: FirebaseAuth.instance.currentUser?.uid,
        onSeizureResult: ({
          required String prediction,
          required String probability,
          required String confidence,
        }) {
          if (!mounted) return;
          setState(() {
            _latestSeizurePrediction = prediction;
            _latestSeizureProb = probability;
            _latestSeizureConf = confidence;
          });
        },
      );
    });
    // ── end SeizureAlertService init ────────────────────────────────
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseAnimationController.dispose();
    _healthDataSubscription?.cancel();
    _predictionsCountSubscription?.cancel();
    SeizureAlertService.instance.dispose(); // ← stop Firebase listener
    super.dispose();
  }

  // ── Health data listener ────────────────────────────────────────
  void _startListeningToHealthData() {
    print('🔍 ========== STARTING FIREBASE LISTENER ==========');
    _healthDataSubscription?.cancel();

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('❌ No user logged in');
      return;
    }
    print('✅ User: ${user.uid}');

    final DatabaseReference healthRef = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('health_readings');

    _healthDataSubscription =
        healthRef.onChildAdded.listen((DatabaseEvent event) {
      print('\n📡 === NEW DATA ARRIVED ===');
      print('📦 Key: ${event.snapshot.key}');

      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        print('📦 Data: $data');

        if (data is Map) {
          try {
            final healthDataMap = <String, dynamic>{};
            data.forEach((key, value) {
              healthDataMap[key.toString()] = value;
            });

            final newHealthData =
                HealthData.fromRealtimeDatabase(healthDataMap);

            if (mounted) {
              setState(() {
                healthData = newHealthData;
                anomalies = healthData!.detectAnomalies();
                print(
                    '✅ UI Updated - BPM: ${healthData!.bpm}, SpO2: ${healthData!.spo2}');
              });
            }
          } catch (e) {
            print('❌ Error processing: $e');
          }
        }
      }
    }, onError: (e) {
      print('❌ Listener error: $e');
    });

    print('✅ Listener set up successfully');
  }

  // ── Predictions listener ────────────────────────────────────────
  void _startListeningToPredictions() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final healthRef = FirebaseDatabase.instance
        .ref()
        .child('users')
        .child(user.uid)
        .child('health_readings');

    _predictionsCountSubscription =
        healthRef.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value;
        if (data is Map) {
          String? latestResult;
          String? latestTimestamp;

          data.forEach((key, value) {
            if (value is Map) {
              final result = value['result']?.toString();
              final timestamp = value['timestamp']?.toString() ??
                  value['updated_timestamp']?.toString();

              if (result != null && result.isNotEmpty) {
                if (latestTimestamp == null ||
                    (timestamp != null &&
                        timestamp.compareTo(latestTimestamp!) > 0)) {
                  latestResult = result;
                  latestTimestamp = timestamp;
                }
              }
            }
          });

          setState(() {
            _latestDiseasePrediction = latestResult;
            _predictionCount = latestResult != null ? 1 : 0;
          });

          print('🩺 Latest prediction: $_latestDiseasePrediction');
        }
      } else {
        setState(() {
          _latestDiseasePrediction = null;
          _predictionCount = 0;
        });
      }
    }, onError: (error) {
      print('❌ Error listening to predictions: $error');
    });
  }

  // ── FCM ─────────────────────────────────────────────────────────
  Future<void> _setupFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      _fcmToken = await messaging.getToken();
      print('FCM Token: $_fcmToken');
      await _initializeAuthClient();
    } else {
      print('User declined or has not accepted permission');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Got a message whilst in the foreground!');
      if (message.notification != null) {
        _showSnackBar(
            '${message.notification!.title}: ${message.notification!.body}');
      }
    });
  }

  void _showSnackBar(String message) {
    final snackBar = SnackBar(
      content: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.notifications_active,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.all(16),
      backgroundColor: Colors.blue.shade800.withOpacity(0.9),
      elevation: 8,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
          label: 'Dismiss', textColor: Colors.white, onPressed: () {}),
    ).animate().slideY(
          begin: 0.3,
          end: 0,
          curve: Curves.easeOutQuad,
          duration: const Duration(milliseconds: 300),
        ).fadeIn();

    ScaffoldMessenger.of(context).showSnackBar(snackBar as SnackBar);
  }

  Future<void> _initializeAuthClient() async {
    final serviceAccountJson = dotenv.env['SERVICE_ACCOUNT_JSON'];
    if (serviceAccountJson == null) {
      print('Service account JSON not found');
      return;
    }
    final credentials =
        auth.ServiceAccountCredentials.fromJson(serviceAccountJson);
    _authClient = await auth.clientViaServiceAccount(
      credentials,
      ['https://www.googleapis.com/auth/firebase.messaging'],
    );
  }

  Future<void> sendUidToEsp32() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        String uid = user.uid;
        final response = await http.get(Uri.parse('$esp32Url?uid=$uid'));
        if (response.statusCode == 200) {
          print('UID sent to ESP32: $uid');
        } else {
          print(
              'Failed to send UID: ${response.statusCode} - ${response.body}');
        }
      } else {
        print('No user is logged in');
      }
    } catch (e) {
      print('Error sending UID: $e');
    }
  }

  Future<void> _sendNotification(List<String> anomalies) async {
    if (_fcmToken == null || _authClient == null) {
      print('FCM token or auth client not available');
      return;
    }

    final url =
        'https://fcm.googleapis.com/v1/projects/healthcareapp-361d0/messages:send';
    final headers = {
      'Content-Type': 'application/json',
      'Authorization':
          'Bearer ${(_authClient!.credentials as auth.AccessCredentials).accessToken.data}',
    };
    final payload = {
      'message': {
        'token': _fcmToken,
        'notification': {
          'title': 'Health Anomaly Detected',
          'body': 'Anomalies: ${anomalies.join(", ")}',
        },
        'data': {
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          'anomalies': anomalies.join(","),
        },
      },
    };

    try {
      final response = await http.post(Uri.parse(url),
          headers: headers, body: jsonEncode(payload));
      if (response.statusCode == 200) {
        print('Notification sent successfully');
      } else {
        print(
            'Failed to send notification: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  // ── Seizure status card ─────────────────────────────────────────
  Widget _buildSeizureStatusCard(bool isDarkMode) {
    final hasResult = _latestSeizurePrediction != null;
    final isSeizure = _latestSeizurePrediction == 'SEIZURE';
    final Color accent = isSeizure
        ? const Color(0xFFD32F2F)
        : hasResult
            ? Colors.green.shade600
            : Colors.grey.shade400;
    final Color bg = isSeizure
        ? const Color(0xFFFFF3F3)
        : hasResult
            ? const Color(0xFFF1FFF4)
            : Colors.grey.shade50;

    return GestureDetector(
      onTap: isSeizure
          ? () => SeizureAlertService.instance.showManualAlert(
                context,
                probability: _latestSeizureProb ?? '?',
                confidence: _latestSeizureConf ?? 'UNKNOWN',
              )
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.12),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          AnimatedBuilder(
            animation: _pulseAnimationController,
            builder: (_, child) => Transform.scale(
              scale: isSeizure
                  ? (1.0 + 0.08 * _pulseAnimationController.value)
                  : 1.0,
              child: child,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSeizure
                    ? Icons.warning_rounded
                    : hasResult
                        ? Icons.check_circle_rounded
                        : Icons.sensors,
                color: accent,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    'Motion Anomaly Detection',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    // child: Text(
                    //   'MPU6050',
                    //   style: TextStyle(
                    //     fontSize: 10,
                    //     fontWeight: FontWeight.w600,
                    //     color: accent,
                    //   ),
                    // ),
                  ),
                ]),
                const SizedBox(height: 5),
                Text(
                  hasResult
                      ? isSeizure
                          ? 'Motion Anomaly activity detected  •  ${_latestSeizureProb ?? "?"}%  •  ${_latestSeizureConf ?? ""}'
                          : 'No anomaly detected  •  ${_latestSeizureProb ?? "?"}%  •  ${_latestSeizureConf ?? ""}'
                      : 'Monitoring — waiting for first sensor reading...',
                  style: TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isSeizure)
            Icon(Icons.chevron_right_rounded, color: accent, size: 22),
        ]),
      ),
    );
  }

  // ── Device card ─────────────────────────────────────────────────
  Widget _buildDeviceCard(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDarkMode
              ? [Colors.grey.shade900, Colors.grey.shade800]
              : [Colors.white, Colors.grey.shade50],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.watch_outlined,
                      size: 32, color: Colors.blue.shade600),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Health Monitor',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('Connected',
                            style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600])),
                      ]),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _isRefreshing = true);
                    Future.delayed(const Duration(seconds: 1), () {
                      setState(() => _isRefreshing = false);
                      _showSnackBar('Device connection refreshed');
                    });
                  },
                  icon: _isRefreshing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue.shade600))
                      : Icon(Icons.refresh_rounded,
                          color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
          Container(
              height: 1,
              color: isDarkMode
                  ? Colors.grey.shade800
                  : Colors.grey.shade200),
        ],
      ),
    );
  }

  // ── Disease prediction row ──────────────────────────────────────
  Widget _buildFullWidthPredictionRow(bool isDarkMode) {
    final hasPrediction = _latestDiseasePrediction != null;

    return GestureDetector(
      onTap: hasPrediction
          ? () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28)),
                ),
                backgroundColor: Colors.white,
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.health_and_safety,
                              color: Colors.purple.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Text('Latest Prediction',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.purple.shade200, width: 1.5),
                        ),
                        child: Text(_latestDiseasePrediction ?? '',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.purple.shade800)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                          'This is an AI-generated prediction. Please consult a doctor.',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600])),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          : null,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 140),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade50,
              Colors.indigo.shade50,
              Colors.blue.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.purple.withOpacity(0.2),
                blurRadius: 15,
                spreadRadius: 1,
                offset: const Offset(0, 4))
          ],
          border: Border.all(
              color: Colors.purple.shade200.withOpacity(0.5), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.purple.withOpacity(0.15),
                        blurRadius: 8)
                  ],
                ),
                child: Icon(Icons.health_and_safety,
                    color: Colors.purple.shade600, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.bolt,
                            size: 12, color: Colors.purple.shade700),
                        const SizedBox(width: 4),
                        Text('AI-POWERED',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700)),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    const Text('Disease Prediction',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    hasPrediction
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.purple.shade200, width: 1),
                            ),
                            child: Row(children: [
                              Icon(Icons.medical_information_outlined,
                                  size: 16, color: Colors.purple.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(_latestDiseasePrediction!,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.purple.shade800),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                          )
                        : Text('Waiting for AI health analysis...',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hasPrediction)
                Icon(Icons.chevron_right_rounded,
                    size: 24, color: Colors.purple.shade400),
            ],
          ),
        ),
      ).animate().fadeIn(delay: 600.ms).slideY(
            begin: 0.2,
            end: 0,
            duration: 500.ms,
            curve: Curves.easeOutCubic,
          ),
    );
  }

  // ── ECG button ──────────────────────────────────────────────────
  Widget _buildECGButton({
    required String title,
    required IconData icon,
    required Color iconColor,
    required LinearGradient bgGradient,
    required bool isDarkMode,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width / 2 - 36),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ECGPage(
                  userId:
                      FirebaseAuth.instance.currentUser?.uid ?? ''),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: Colors.red.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 1,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: iconColor, size: 20)),
                  const SizedBox(width: 12),
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800])),
                ]),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.red.withOpacity(0.1),
                            blurRadius: 10,
                            spreadRadius: 2)
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_arrow_rounded,
                          color: Colors.red.shade600, size: 18),
                      const SizedBox(width: 8),
                      Text('View ECG',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                    child: Text('Real-time monitoring',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600]))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Metric tile ─────────────────────────────────────────────────
  Widget _buildMetricTile({
    required String title,
    required IconData icon,
    required Color iconColor,
    required LinearGradient bgGradient,
    required String value,
    required String unit,
    required bool hasAnomaly,
    required bool isDarkMode,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width / 2 - 36),
      child: Container(
        decoration: BoxDecoration(
          gradient: bgGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: hasAnomaly
                  ? Colors.red.withOpacity(0.2)
                  : Colors.blue.withOpacity(0.1),
              blurRadius: 15,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (hasAnomaly)
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedBuilder(
                  animation: _pulseAnimationController,
                  builder: (context, child) {
                    return Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(
                                0.5 * _pulseAnimationController.value),
                            blurRadius:
                                10 * _pulseAnimationController.value,
                            spreadRadius:
                                2 * _pulseAnimationController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: iconColor, size: 20)),
                    const SizedBox(width: 12),
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800])),
                  ]),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(value,
                          style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: hasAnomaly
                                  ? Colors.red.shade700
                                  : Colors.black87)),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(unit,
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600])),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: hasAnomaly
                              ? Colors.red.withOpacity(0.1)
                              : Colors.green.withOpacity(0.1),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          hasAnomaly
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: hasAnomaly
                              ? Colors.red.shade700
                              : Colors.green.shade600,
                          size: 14),
                      const SizedBox(width: 4),
                      Text(hasAnomaly ? 'Abnormal' : 'Normal',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: hasAnomaly
                                  ? Colors.red.shade700
                                  : Colors.green.shade600)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            pinned: true,
            stretch: true,
            backgroundColor:
                isDarkMode ? Colors.grey[900] : Colors.blue[800],
            elevation: 0,
            shape: const RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 16),
              title: Text(
                'Health Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  shadows: [
                    Shadow(
                        offset: const Offset(1, 1),
                        blurRadius: 3.0,
                        color: Colors.black.withOpacity(0.3))
                  ],
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isDarkMode ? Colors.indigo[900]! : Colors.blue[700]!,
                      isDarkMode
                          ? Colors.purple[900]!
                          : Colors.indigo[500]!,
                    ],
                  ),
                ),
                child: Stack(children: [
                  Positioned(
                    right: -50,
                    top: -20,
                    child: Opacity(
                        opacity: 0.1,
                        child: SizedBox(
                            width: 200,
                            height: 200,
                            child: CustomPaint(
                                painter: WavePainter(
                                    isDarkMode: isDarkMode)))),
                  ),
                  Positioned(
                      left: -20,
                      bottom: 20,
                      child: CircleAvatar(
                          radius: 60,
                          backgroundColor:
                              Colors.white.withOpacity(0.1))),
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 10,
                    left: 20,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 26),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.chat_bubble_outline,
                      color: Colors.white, size: 20),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation,
                              secondaryAnimation) =>
                          Chatbot(
                              healthData: healthData,
                              anomalies: anomalies),
                      transitionsBuilder: (context, animation,
                          secondaryAnimation, child) {
                        var tween = Tween(
                                begin: const Offset(1.0, 0.0),
                                end: Offset.zero)
                            .chain(
                                CurveTween(curve: Curves.easeOutQuart));
                        return SlideTransition(
                            position: animation.drive(tween),
                            child: child);
                      },
                    ),
                  );
                },
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.notifications_outlined,
                      color: Colors.white, size: 20),
                ),
                onPressed: () =>
                    _showNotificationBottomSheet(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeviceCard(isDarkMode),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your Health Metrics',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode
                                  ? Colors.white
                                  : Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.grey.shade800
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          Icon(Icons.access_time,
                              size: 14,
                              color: isDarkMode
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text('Live',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkMode
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade700)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Real-time monitoring of your vital signs',
                      style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600])),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GridView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  children: [
                    if (healthData != null) ...[
                      _buildMetricTile(
                        title: "Heart",
                        icon: Icons.favorite,
                        iconColor: Colors.red.shade400,
                        bgGradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: anomalies
                                  .any((a) => a.contains("Heart Rate"))
                              ? [Colors.red.shade50, Colors.red.shade100]
                              : [
                                  Colors.red.shade50,
                                  Colors.orange.shade50
                                ],
                        ),
                        value: healthData!.bpm.toString(),
                        unit: "bpm",
                        hasAnomaly: anomalies
                            .any((a) => a.contains("Heart Rate")),
                        isDarkMode: isDarkMode,
                      ),
                      _buildMetricTile(
                        title: "spO2",
                        icon: Icons.air,
                        iconColor: Colors.blue.shade400,
                        bgGradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors:
                              anomalies.any((a) => a.contains("SpO2"))
                                  ? [
                                      Colors.blue.shade50,
                                      Colors.red.shade50
                                    ]
                                  : [
                                      Colors.blue.shade50,
                                      Colors.cyan.shade50
                                    ],
                        ),
                        value: healthData!.spo2.toStringAsFixed(1),
                        unit: "%",
                        hasAnomaly:
                            anomalies.any((a) => a.contains("SpO2")),
                        isDarkMode: isDarkMode,
                      ),
                      _buildMetricTile(
                        title: "Temp",
                        icon: Icons.thermostat,
                        iconColor: Colors.orange.shade400,
                        bgGradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: anomalies
                                  .any((a) => a.contains("Temperature"))
                              ? [
                                  Colors.orange.shade50,
                                  Colors.red.shade50
                                ]
                              : [
                                  Colors.orange.shade50,
                                  Colors.yellow.shade50
                                ],
                        ),
                        value: healthData!.temperatureC.toStringAsFixed(1),
                        unit: "°C",
                        hasAnomaly: anomalies
                            .any((a) => a.contains("Temperature")),
                        isDarkMode: isDarkMode,
                      ),
                      _buildECGButton(
                        title: "ECG",
                        icon: FontAwesomeIcons.heartPulse,
                        iconColor: Colors.red.shade400,
                        bgGradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.red.shade50,
                            Colors.pink.shade50
                          ],
                        ),
                        isDarkMode: isDarkMode,
                      ),
                    ] else ...[
                      for (int i = 0; i < 4; i++)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.grey.shade100,
                                Colors.grey.shade200
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                                SizedBox(height: 12),
                                Text('Loading...',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ]
                      .asMap()
                      .entries
                      .map((entry) {
                        return entry.value
                            .animate(
                              controller: _animationController,
                              delay: Duration(
                                  milliseconds: 150 * entry.key),
                            )
                            .slideY(
                              begin: 0.3,
                              end: 0,
                              curve: Curves.easeOutQuad,
                              duration:
                                  const Duration(milliseconds: 600),
                            )
                            .fadeIn(
                              duration:
                                  const Duration(milliseconds: 800),
                            );
                      })
                      .toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Disease prediction row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildFullWidthPredictionRow(isDarkMode),
              ),
              const SizedBox(height: 16),
              // Seizure detection status card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSeizureStatusCard(isDarkMode),
              ),
              const SizedBox(height: 30),
            ]),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  Chatbot(healthData: healthData, anomalies: anomalies),
            ),
          );
        },
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text(''),
        elevation: 4,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

void _showNotificationBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    backgroundColor: Colors.white,
    builder: (context) {
      return Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications',
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('No new notifications at this time.',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}

class WavePainter extends CustomPainter {
  final bool isDarkMode;
  WavePainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final path = Path();
    path.moveTo(0, size.height / 2);
    for (int i = 0; i < 6; i++) {
      if (i % 2 == 0) {
        path.quadraticBezierTo(size.width * (i + 0.5) / 6,
            size.height / 4, size.width * (i + 1) / 6, size.height / 2);
      } else {
        path.quadraticBezierTo(
            size.width * (i + 0.5) / 6,
            size.height * 3 / 4,
            size.width * (i + 1) / 6,
            size.height / 2);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}