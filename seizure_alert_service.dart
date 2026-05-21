// seizure_alert_service.dart
// Place in lib/ folder.
//
// Setup required:
// 1. flutter pub add flutter_local_notifications
// 2. AndroidManifest.xml changes (see bottom of this file)
// 3. iOS: add to Info.plist (see bottom of this file)

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef SeizureResultCallback = void Function({
  required String prediction,
  required String probability,
  required String confidence,
});

class SeizureAlertService {
  SeizureAlertService._();
  static final SeizureAlertService instance = SeizureAlertService._();

  // ── Local notifications plugin ────────────────────────────────────
  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();
  bool _notifInitialised = false;

  StreamSubscription? _sub1;
  StreamSubscription? _sub2;
  BuildContext?       _context;
  bool                _alertShowing = false;
  String?             _lastAlertedKey;
  SeizureResultCallback? _onSeizureResult;

  // ── Init ──────────────────────────────────────────────────────────
  Future<void> init(
    BuildContext context, {
    String? userId,
    SeizureResultCallback? onSeizureResult,
  }) async {
    _context         = context;
    _onSeizureResult = onSeizureResult;

    await _initNotifications();

    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[SeizureAlert] No UID — listener not started');
      return;
    }

    _startListening(uid);
    debugPrint('[SeizureAlert] Ready — uid=$uid');
  }

  // ── Initialise local notifications ────────────────────────────────
  Future<void> _initNotifications() async {
    if (_notifInitialised) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission : true,
      requestBadgePermission : true,
      requestSoundPermission : true,
    );

    await _notifPlugin.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
    );

    // Request Android 13+ notification permission
    final androidPlugin = _notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    // Create high-priority notification channel (Android 8+)
    const channel = AndroidNotificationChannel(
      'seizure_alerts',
      'Motion Anomaly Alerts',
      description   : 'Critical motion detection alerts from wearable sensor',
      importance    : Importance.max,
      playSound     : true,
      enableVibration: true,
      showBadge     : true,
    );
    await androidPlugin?.createNotificationChannel(channel);

    _notifInitialised = true;
    debugPrint('[SeizureAlert] Notifications initialised');
  }

  // ── Firebase listener ─────────────────────────────────────────────
  void _startListening(String uid) {
    _sub1?.cancel();
    _sub2?.cancel();
    final ref =
        FirebaseDatabase.instance.ref('users/$uid/health_readings');
    _sub1 = ref.onChildAdded.listen(_handleEvent);
    _sub2 = ref.onChildChanged.listen(_handleEvent);
  }

  void _handleEvent(DatabaseEvent event) {
    final key  = event.snapshot.key;
    final data = event.snapshot.value;

    if (key == null)            return;
    if (data is! Map)           return;
    if (key == _lastAlertedKey) return; // no duplicate for same reading

    final result = data['seizure_result'];
    if (result is! Map) return;

    final prediction = result['prediction']?.toString().toUpperCase() ?? '';
    final rawProb    = result['probability'];
    final confidence = result['confidence']?.toString() ?? 'UNKNOWN';
    final prob = rawProb is num
        ? (rawProb * 100).toStringAsFixed(1)
        : rawProb?.toString() ?? '?';

    // Always update UI status card
    _onSeizureResult?.call(
      prediction : prediction,
      probability: prob,
      confidence : confidence,
    );

    if (prediction == 'SEIZURE') {
      _lastAlertedKey = key;
      debugPrint('[SeizureAlert] SEIZURE — prob=$prob% conf=$confidence');
      _showOverlayAlert(probability: prob, confidence: confidence);
      _sendBackgroundNotification(prob, confidence);
    }
  }

  // ── Full-screen overlay popup (while app is open) ─────────────────
  void _showOverlayAlert({
    required String probability,
    required String confidence,
  }) {
    if (_alertShowing) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    _alertShowing = true;
    HapticFeedback.vibrate();

    showGeneralDialog(
      context           : ctx,
      barrierDismissible: false,
      barrierColor      : Colors.black.withOpacity(0.88),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder : (_, anim, __, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (dialogCtx, _, __) => _SeizureAlertDialog(
        probability: probability,
        confidence : confidence,
        onDismiss  : () {
          Navigator.of(dialogCtx).pop();
          _alertShowing = false;
        },
      ),
    );
  }

  // ── Manual re-show (from status card tap) ─────────────────────────
  void showManualAlert(
    BuildContext context, {
    required String probability,
    required String confidence,
  }) {
    _context      = context;
    _alertShowing = false;
    _showOverlayAlert(probability: probability, confidence: confidence);
  }

  // ── Background / lock-screen notification ─────────────────────────
  Future<void> _sendBackgroundNotification(
      String prob, String confidence) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'seizure_alerts',
        'Anomaly Detection Alerts',
        channelDescription: 'Critical motion detection alerts',
        importance        : Importance.max,
        priority          : Priority.high,
        fullScreenIntent  : true,   // shows on lock screen
        color             : const Color(0xFFD32F2F),
        icon              : '@mipmap/ic_launcher',
        enableVibration   : true,
        playSound         : true,
        ticker            : 'Motion Anomaly Detected',
        styleInformation  : BigTextStyleInformation(
          'Probability: $prob%  •  Confidence: $confidence\n'
          'Please check on the patient immediately and call for help if needed.',
          contentTitle: '🚨 Motion Anomaly Detected by Wearable',
          summaryText : 'MPU6050 Health Monitor',
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert    : true,
        presentBadge    : true,
        presentSound    : true,
        interruptionLevel: InterruptionLevel.critical,
      );

      await _notifPlugin.show(
        9999,
        '🚨 Motion Anomaly Detected!',
        'Probability: $prob%  •  Confidence: $confidence — Check the patient now.',
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );

      debugPrint('[SeizureAlert] Background notification sent');
    } catch (e) {
      debugPrint('[SeizureAlert] Notification error: $e');
    }
  }

  // ── Update context when navigating ───────────────────────────────
  void updateContext(BuildContext context) {
    _context = context;
  }

  // ── Dispose ───────────────────────────────────────────────────────
  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    _sub1 = _sub2 = null;
    _context = null;
  }
}


// ─────────────────────────────────────────────────────────────────────
// Alert Dialog Widget
// ─────────────────────────────────────────────────────────────────────
class _SeizureAlertDialog extends StatefulWidget {
  final String       probability;
  final String       confidence;
  final VoidCallback onDismiss;

  const _SeizureAlertDialog({
    required this.probability,
    required this.confidence,
    required this.onDismiss,
  });

  @override
  State<_SeizureAlertDialog> createState() => _SeizureAlertDialogState();
}

class _SeizureAlertDialogState extends State<_SeizureAlertDialog>
    with SingleTickerProviderStateMixin {

  late AnimationController _pulse;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.14)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    // Double vibration on open
    Future.delayed(const Duration(milliseconds: 150),
        HapticFeedback.heavyImpact);
    Future.delayed(const Duration(milliseconds: 480),
        HapticFeedback.heavyImpact);
  }

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  Color get _confColor {
    switch (widget.confidence.toUpperCase()) {
      case 'HIGH':   return const Color(0xFFB71C1C);
      case 'MEDIUM': return const Color(0xFFF57C00);
      default:       return const Color(0xFFF9A825);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            decoration: BoxDecoration(
              color       : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow   : [
                BoxShadow(
                  color      : Colors.red.withOpacity(0.45),
                  blurRadius : 50,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // ── Red header ─────────────────────────────────────────
              Container(
                width  : double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
                    begin : Alignment.topLeft,
                    end   : Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28)),
                ),
                child: Column(children: [

                  // Pulsing icon
                  AnimatedBuilder(
                    animation: _scale,
                    builder: (_, child) =>
                        Transform.scale(scale: _scale.value, child: child),
                    child: Container(
                      width : 80, height: 80,
                      decoration: BoxDecoration(
                        color : Colors.white.withOpacity(0.20),
                        shape : BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                            width: 2.5),
                      ),
                      child: const Icon(Icons.warning_rounded,
                          color: Colors.white, size: 42),
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Text(
                    'MOTION ANOMALY DETECTED',
                    style: TextStyle(
                      color      : Colors.white,
                      fontSize   : 22,
                      fontWeight : FontWeight.w900,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'MPU6050 wearable sensor alert',
                    style: TextStyle(
                      color   : Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ]),
              ),

              // ── Body ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(children: [

                  // Probability + confidence row
                  Row(children: [
                    Expanded(child: _StatBox(
                      label: 'Probability',
                      value: '${widget.probability}%',
                      color: const Color(0xFFD32F2F),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatBox(
                      label: 'Confidence',
                      value: widget.confidence,
                      color: _confColor,
                    )),
                  ]),

                  const SizedBox(height: 16),

                  // Action card
                  Container(
                    width  : double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color       : const Color(0xFFFFF3F3),
                      borderRadius: BorderRadius.circular(16),
                      border      : Border.all(
                          color: const Color(0xFFFFCDD2), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.medical_services_outlined,
                              color: Color(0xFFD32F2F), size: 18),
                          const SizedBox(width: 8),
                          const Text(
                            'Immediate Action Required',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color     : Color(0xFFD32F2F),
                              fontSize  : 14,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _ActionItem(icon: Icons.person_pin,
                            text: 'Keep the patient safe — lay on their side'),
                        _ActionItem(icon: Icons.timer_outlined,
                            text: 'Note the exact time the motion anomaly started'),
                        _ActionItem(icon: Icons.phone_in_talk,
                            text: 'Call emergency services if lasting over 5 minutes'),
                        _ActionItem(icon: Icons.block,
                            text: 'Do NOT restrain or put anything in their mouth'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Dismiss button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'I Understand — Dismiss Alert',
                        style: TextStyle(
                          fontWeight   : FontWeight.bold,
                          fontSize     : 15,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'Triggered by MPU6050 wearable sensor.\n'
                    'Always confirm with a medical professional.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color   : Colors.grey[500],
                      height  : 1.5,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String label, value;
  final Color  color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    decoration: BoxDecoration(
      color       : color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      border      : Border.all(color: color.withOpacity(0.25), width: 1.5),
    ),
    child: Column(children: [
      Text(value, style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w900, color: color)),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  );
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String   text;
  const _ActionItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: const Color(0xFFE57373)),
      const SizedBox(width: 8),
      Expanded(child: Text(text,
          style: const TextStyle(
              fontSize: 13, color: Color(0xFF5D4037), height: 1.4))),
    ]),
  );
}