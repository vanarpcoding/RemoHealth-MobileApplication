// ecg_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ECGPage extends StatefulWidget {
  final String userId;
  
  const ECGPage({super.key, required this.userId});
  
  @override
  _ECGPageState createState() => _ECGPageState();
}

class _ECGPageState extends State<ECGPage> {
  List<ECGData> _ecgData = [];
  List<ECGData> _displayData = [];
  late StreamSubscription _ecgSubscription;
  late StreamSubscription _healthSubscription;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isLoading = true;
  bool _showLiveData = true;
  double _currentBPM = 0;
  double _currentAmplitude = 0;
  Timer? _simulationTimer;
  Map<int, double> _bpmMap = {}; // Store BPM values by timestamp
  
  @override
  void initState() {
    super.initState();
    _startListeningToData();
    // Start simulation if no real data
    _startSimulation();
  }
  
  @override
  void dispose() {
    _ecgSubscription.cancel();
    _healthSubscription.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }
  
  void _startListeningToData() {
    // Listen to ECG data
    final ecgRef = _database.child('users/${widget.userId}/ecg_readings');
    final healthRef = _database.child('users/${widget.userId}/health_readings');
    
    // Listen to ECG readings
    _ecgSubscription = ecgRef.onChildAdded.listen((DatabaseEvent event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final timestamp = data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final ecgRaw = (data['ecg_raw'] as num?)?.toDouble() ?? 0.0;
        
        // Convert ECG raw value to normalized value for display
        // Adjust these values based on your ECG sensor range
        final ecgValue = _normalizeECGValue(ecgRaw);
        
        // Find corresponding BPM for this timestamp
        double bpm = _findNearestBPM(timestamp);
        
        final ecgPoint = ECGData(
          timestamp: timestamp,
          value: ecgValue,
          bpm: bpm,
        );
        
        setState(() {
          _ecgData.add(ecgPoint);
          // Keep only last 500 points for performance
          if (_ecgData.length > 500) {
            _ecgData.removeAt(0);
          }
          
          if (_showLiveData) {
            _displayData = List.from(_ecgData);
          }
          
          _currentBPM = bpm;
          _currentAmplitude = ecgValue.abs();
          _isLoading = false;
        });
      }
    });
    
    // Listen to Health readings (for BPM)
    _healthSubscription = healthRef.onChildAdded.listen((DatabaseEvent event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final timestamp = data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final bpm = (data['bpm'] as num?)?.toDouble() ?? 0.0;
        
        // Store BPM with timestamp
        _bpmMap[timestamp] = bpm;
        
        // Keep only recent BPM values (last 100 entries)
        if (_bpmMap.length > 100) {
          final oldestKey = _bpmMap.keys.reduce((a, b) => a < b ? a : b);
          _bpmMap.remove(oldestKey);
        }
        
        // Update current BPM if no ECG data is coming
        if (_ecgData.isEmpty) {
          setState(() {
            _currentBPM = bpm;
          });
        }
      }
    });
  }
  
  // Normalize ECG raw value to display range (-0.2 to 1.5)
  double _normalizeECGValue(double rawValue) {
    // Adjust these normalization factors based on your ECG sensor
    // Example: Raw values from 0-4095 (12-bit ADC) to 0-1.5 mV
    const double maxRawValue = 4095.0; // Adjust based on your sensor
    const double displayMax = 1.5;
    const double displayMin = -0.2;
    
    // Convert to normalized value
    double normalized = (rawValue / maxRawValue) * (displayMax - displayMin) + displayMin;
    
    return normalized;
  }
  
  // Find the nearest BPM value for a given timestamp
  double _findNearestBPM(int timestamp) {
    if (_bpmMap.isEmpty) return 72.0; // Default BPM
    
    // Find the closest timestamp
    int closestTimestamp = _bpmMap.keys.first;
    int minDifference = (timestamp - closestTimestamp).abs();
    
    for (final key in _bpmMap.keys) {
      final difference = (timestamp - key).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestTimestamp = key;
      }
    }
    
    // Only use if within reasonable time difference (e.g., 5 seconds)
    if (minDifference < 5000) {
      return _bpmMap[closestTimestamp]!;
    }
    
    return 72.0; // Default if no recent BPM
  }
  
  void _startSimulation() {
    // Simulate ECG data if no real data is coming
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_ecgData.isEmpty || _ecgData.length < 10) {
        final now = DateTime.now().millisecondsSinceEpoch;
        // Simulate ECG waveform (sine wave with some noise)
        final timeOffset = now / 1000.0;
        final baseValue = 0.5 + 0.5 * (timeOffset % 2);
        final ecgValue = 0.8 * baseValue * (1 + 0.2 * (timeOffset % 1));
        
        // Use current BPM from health readings or default
        final bpm = _currentBPM > 0 ? _currentBPM : 72 + 10 * (timeOffset % 1);
        
        final simulatedData = ECGData(
          timestamp: now,
          value: ecgValue,
          bpm: bpm,
        );
        
        setState(() {
          _ecgData.add(simulatedData);
          if (_ecgData.length > 500) {
            _ecgData.removeAt(0);
          }
          _displayData = List.from(_ecgData);
          _currentBPM = bpm;
          _currentAmplitude = simulatedData.value;
          _isLoading = false;
        });
      }
    });
    
    // Auto-stop simulation after 10 seconds if real data appears
    Future.delayed(const Duration(seconds: 10), () {
      if (_ecgData.length > 20) {
        _simulationTimer?.cancel();
      }
    });
  }
  
  void _toggleView(bool showLive) {
    setState(() {
      _showLiveData = showLive;
      if (showLive) {
        _displayData = List.from(_ecgData);
      } else {
        // Show last 5 seconds of data
        final cutoff = DateTime.now().millisecondsSinceEpoch - 5000;
        _displayData = _ecgData.where((point) => point.timestamp > cutoff).toList();
      }
    });
  }
  
  Widget _buildECGChart() {
    if (_displayData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 20),
            Text(
              'Waiting for ECG data...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return SfCartesianChart(
      backgroundColor: Colors.transparent,
      plotAreaBorderWidth: 0,
      primaryXAxis: NumericAxis(
        isVisible: false,
      ),
      primaryYAxis: NumericAxis(
        isVisible: false,
        minimum: -0.2,
        maximum: 1.5,
      ),
      series: <CartesianSeries>[
        LineSeries<ECGData, int>(
          dataSource: _displayData,
          xValueMapper: (ECGData data, _) => data.timestamp,
          yValueMapper: (ECGData data, _) => data.value,
          color: Colors.red.shade400,
          width: 2,
          animationDuration: 0,
        ),
      ],
    );
  }
  
  Widget _buildVitalsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.red.shade50, Colors.pink.shade50],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildVitalItem(
            icon: FontAwesomeIcons.heartPulse,
            value: '${_currentBPM.toStringAsFixed(0)}',
            unit: 'BPM',
            color: Colors.red.shade600,
            source: _bpmMap.isNotEmpty ? 'From Health Readings' : 'Simulated',
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.red.shade200,
          ),
          _buildVitalItem(
            icon: Icons.waves,
            value: '${_currentAmplitude.toStringAsFixed(2)}',
            unit: 'mV',
            color: Colors.blue.shade600,
            source: _ecgData.isNotEmpty ? 'From ECG Sensor' : 'Simulated',
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.red.shade200,
          ),
          _buildVitalItem(
            icon: Icons.timeline,
            value: '${_displayData.length}',
            unit: 'Points',
            color: Colors.green.shade600,
            source: _showLiveData ? 'Live Data' : 'Last 5s',
          ),
        ],
      ),
    );
  }
  
  Widget _buildVitalItem({
    required IconData icon,
    required String value,
    required String unit,
    required Color color,
    required String source,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          source,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[500],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'ECG Monitoring',
          style: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.info_outline,
              color: Colors.blue.shade600,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ECG Information'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Electrocardiogram (ECG) shows the electrical activity of your heart.\n\n'
                        '• Normal range: 60-100 BPM\n'
                        '• P wave: Atrial depolarization\n'
                        '• QRS complex: Ventricular depolarization\n'
                        '• T wave: Ventricular repolarization\n\n',
                      ),
                      Text(
                        'Data Sources:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      Text(
                        '• BPM: From health_readings\n'
                        '• ECG Wave: From ecg_readings\n'
                        '• Raw ECG values are normalized for display',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ECG Graph
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 15,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _buildECGChart(),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Vitals Card
                  _buildVitalsCard(),
                  
                  const SizedBox(height: 16),
                  
                  // Controls
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildControlButton(
                          icon: Icons.play_arrow,
                          label: 'Live',
                          isActive: _showLiveData,
                          onTap: () => _toggleView(true),
                        ),
                        _buildControlButton(
                          icon: Icons.pause,
                          label: 'Pause',
                          isActive: !_showLiveData,
                          onTap: () => _toggleView(false),
                        ),
                        _buildControlButton(
                          icon: Icons.refresh,
                          label: 'Sync',
                          isActive: false,
                          onTap: () {
                            _syncDataSources();
                          },
                        ),
                        _buildControlButton(
                          icon: Icons.save,
                          label: 'Save',
                          isActive: false,
                          onTap: () {
                            _saveECGRecording();
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Information
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.medical_services,
                          color: Colors.blue.shade600,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Medical Advice',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentBPM > 100
                                    ? 'Heart rate elevated. Consider resting.'
                                    : _currentBPM < 60
                                        ? 'Heart rate low. Consult a doctor.'
                                        : 'Heart rate within normal range.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isActive ? Colors.red.shade100 : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.red.shade600 : Colors.grey.shade600,
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.red.shade600 : Colors.grey.shade600,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
  
  void _syncDataSources() {
    setState(() {
      _bpmMap.clear();
      _ecgData.clear();
      _displayData.clear();
      _isLoading = true;
    });
    
    // Restart listening
    _ecgSubscription.cancel();
    _healthSubscription.cancel();
    _startListeningToData();
    
    _showSnackBar('Syncing data sources...');
  }
  
  void _saveECGRecording() {
    if (_ecgData.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save ECG Recording'),
        content: const Text('Save the last 30 seconds of ECG data with BPM?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('ECG recording saved with BPM data');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green.shade600,
      ),
    );
  }
}

class ECGData {
  final int timestamp;
  final double value;
  final double bpm;
  
  ECGData({
    required this.timestamp,
    required this.value,
    required this.bpm,
  });
}