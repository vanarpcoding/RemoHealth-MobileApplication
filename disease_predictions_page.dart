import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

class DiseasePredictionsPage extends StatefulWidget {
  const DiseasePredictionsPage({super.key});

  @override
  State<DiseasePredictionsPage> createState() => _DiseasePredictionsPageState();
}

class _DiseasePredictionsPageState extends State<DiseasePredictionsPage> {
  List<Map<String, dynamic>> _predictions = [];
  bool _isLoading = true;
  bool _hasData = false;
  String? _error;
  late DatabaseReference _databaseRef;
  StreamSubscription? _predictionsSubscription;

  @override
  void initState() {
    super.initState();
    _databaseRef = FirebaseDatabase.instance.ref();
    _loadDiseasePredictions();
  }

  @override
  void dispose() {
    _predictionsSubscription?.cancel();
    super.dispose();
  }

  // FIXED: Safe type conversion helper
  Map<String, dynamic> _convertMap(dynamic data) {
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return {};
  }

  // FIXED: Convert list safely
  List<Map<String, dynamic>> _convertList(dynamic data) {
    if (data is List) {
      return data.map((item) {
        if (item is Map) {
          return item.cast<String, dynamic>();
        }
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }

  Future<void> _loadDiseasePredictions() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = 'No user logged in';
        });
        return;
      }

      final predictionsPath = 'users/${user.uid}/disease_predictions';
      print('🔍 Loading disease predictions from: $predictionsPath');

      // Listen for real-time updates
      _predictionsSubscription = _databaseRef
          .child(predictionsPath)
          .onValue
          .listen((DatabaseEvent event) {
        try {
          if (event.snapshot.exists) {
            final data = event.snapshot.value;
            print('📦 Received predictions data');

            if (data is Map<Object?, Object?>) {
              final predictionsList = <Map<String, dynamic>>[];
              
              data.forEach((key, value) {
                if (value is Map<Object?, Object?>) {
                  // FIXED: Convert Map<Object?, Object?> to Map<String, dynamic>
                  final predictionData = _convertMap(value);
                  predictionData['id'] = key?.toString() ?? '';
                  
                  // FIXED: Convert nested maps safely
                  if (predictionData.containsKey('anomaly_analysis')) {
                    predictionData['anomaly_analysis'] = _convertMap(predictionData['anomaly_analysis']);
                    if (predictionData['anomaly_analysis'].containsKey('anomaly_details')) {
                      predictionData['anomaly_analysis']['anomaly_details'] = 
                          _convertList(predictionData['anomaly_analysis']['anomaly_details']);
                    }
                  }
                  
                  if (predictionData.containsKey('all_predictions')) {
                    predictionData['all_predictions'] = _convertList(predictionData['all_predictions']);
                  }
                  
                  if (predictionData.containsKey('health_report')) {
                    predictionData['health_report'] = _convertMap(predictionData['health_report']);
                    if (predictionData['health_report'].containsKey('key_findings')) {
                      predictionData['health_report']['key_findings'] = 
                          _convertList(predictionData['health_report']['key_findings']);
                    }
                    if (predictionData['health_report'].containsKey('recommendations')) {
                      predictionData['health_report']['recommendations'] = 
                          List<String>.from(predictionData['health_report']['recommendations'] ?? []);
                    }
                    if (predictionData['health_report'].containsKey('earliest_anomaly_detected')) {
                      predictionData['health_report']['earliest_anomaly_detected'] = 
                          _convertMap(predictionData['health_report']['earliest_anomaly_detected']);
                    }
                  }
                  
                  predictionsList.add(predictionData);
                }
              });

              // Sort by timestamp (newest first)
              predictionsList.sort((a, b) {
                final timestampA = a['timestamp'] ?? 0;
                final timestampB = b['timestamp'] ?? 0;
                return timestampB.compareTo(timestampA);
              });

              setState(() {
                _predictions = predictionsList;
                _hasData = predictionsList.isNotEmpty;
                _isLoading = false;
              });

              print('✅ Loaded ${_predictions.length} anomaly-based predictions');
            }
          } else {
            setState(() {
              _hasData = false;
              _isLoading = false;
            });
            print('📭 No predictions found at path');
          }
        } catch (e) {
          print('❌ Error processing predictions data: $e');
          setState(() {
            _error = 'Error processing data: $e';
            _isLoading = false;
          });
        }
      }, onError: (error) {
        print('❌ Error listening to predictions: $error');
        setState(() {
          _error = 'Failed to load predictions: $error';
          _isLoading = false;
        });
      });

    } catch (e) {
      print('❌ Error loading predictions: $e');
      setState(() {
        _error = 'Error loading predictions: $e';
        _isLoading = false;
      });
    }
  }

  // UPDATED: Convert Unix timestamp (seconds) to local DateTime
  DateTime? _getLocalDateTime(dynamic timestamp) {
    try {
      if (timestamp == null) return null;
      
      // Handle int/double Unix timestamp (in seconds)
      if (timestamp is int || timestamp is double) {
        final ts = timestamp.toDouble();
        // If timestamp is in milliseconds (like 1698765432000), convert to seconds
        if (ts > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: false);
        } else {
          // Timestamp is already in seconds (like 1698765432)
          return DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt(), isUtc: false);
        }
      }
      
      // Handle string (could be Unix timestamp string)
      if (timestamp is String) {
        final numValue = num.tryParse(timestamp);
        if (numValue != null) {
          if (numValue > 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(numValue.toInt(), isUtc: false);
          } else {
            return DateTime.fromMillisecondsSinceEpoch((numValue * 1000).toInt(), isUtc: false);
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error converting timestamp: $e');
      return null;
    }
  }

  // UPDATED: Format timestamp relative to now (using Unix timestamp)
  String _formatTimestamp(dynamic timestamp) {
    final localDate = _getLocalDateTime(timestamp);
    if (localDate == null) return 'Recently';
    
    final now = DateTime.now();
    final difference = now.difference(localDate);
    
    if (difference.inDays > 365) {
      return DateFormat('MMM yyyy').format(localDate);
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // UPDATED: Format detailed timestamp (using Unix timestamp)
  String _formatDetailedTimestamp(dynamic timestamp) {
    final localDate = _getLocalDateTime(timestamp);
    if (localDate == null) return 'Unknown time';
    
    return DateFormat('MMM dd, yyyy - hh:mm a').format(localDate);
  }

  // REMOVED: _getHumanTime function as we don't have human_time anymore

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Analyzing Health Data...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Detecting anomalies and disease patterns',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No Anomalies Detected',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Your vital signs are within normal ranges. Disease predictions are generated only when anomalies are detected.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _loadDiseasePredictions,
            icon: const Icon(Icons.refresh),
            label: const Text('Check Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red[400],
          ),
          const SizedBox(height: 20),
          Text(
            'Error Loading Predictions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red[600],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _error ?? 'Unknown error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _loadDiseasePredictions,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'moderate':
        return Colors.amber;
      case 'low':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  IconData _getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.warning_amber;
      case 'high':
        return Icons.error_outline;
      case 'moderate':
        return Icons.info_outline;
      case 'low':
        return Icons.info_outline;
      default:
        return Icons.check_circle_outline;
    }
  }

  Widget _buildAnomalyChips(dynamic anomalies) {
    if (anomalies is! List || anomalies.isEmpty) return const SizedBox();
    
    final anomalyList = _convertList(anomalies);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: anomalyList.take(5).map((anomaly) {
            final vital = anomaly['vital']?.toString() ?? 'Unknown';
            final type = anomaly['type']?.toString() ?? 'unknown';
            final value = anomaly['value']?.toString() ?? '';
            final timestamp = anomaly['timestamp'];
            final timeStr = _formatTimestamp(timestamp);
            
            return Chip(
              label: Text('$vital: $value'),
              backgroundColor: _getSeverityColor(anomaly['severity']?.toString() ?? 'Normal').withOpacity(0.1),
              labelStyle: TextStyle(
                fontSize: 12,
                color: _getSeverityColor(anomaly['severity']?.toString() ?? 'Normal'),
              ),
              avatar: CircleAvatar(
                backgroundColor: _getSeverityColor(anomaly['severity']?.toString() ?? 'Normal'),
                radius: 10,
                child: Text(
                  type[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              deleteIcon: Icon(
                Icons.access_time,
                size: 14,
                color: Colors.grey[600],
              ),
              onDeleted: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$vital anomaly detected'),
                        Text(
                          timeStr,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            );
          }).toList(),
        ),
        if (anomalyList.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${anomalyList.length - 5} more anomalies',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPredictionCard(Map<String, dynamic> prediction) {
    final overallSeverity = prediction['overall_severity']?.toString() ?? 'Normal';
    final timestamp = prediction['timestamp'];
    final predictions = _convertList(prediction['all_predictions'] ?? []);
    final healthReport = _convertMap(prediction['health_report'] ?? {});
    final anomalyAnalysis = _convertMap(prediction['anomaly_analysis'] ?? {});
    final anomalyDetails = _convertList(anomalyAnalysis['anomaly_details'] ?? []);
    final anomalyCount = anomalyAnalysis['anomaly_count'] ?? 0;
    final anomalyPatterns = prediction['anomaly_patterns'] is List ? 
        List<String>.from(prediction['anomaly_patterns'] ?? []) : [];
    final earliestAnomaly = _convertMap(healthReport['earliest_anomaly_detected'] ?? {});

    return GestureDetector(
      onTap: () {
        _showPredictionDetails(prediction);
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getSeverityColor(overallSeverity).withOpacity(0.1),
                _getSeverityColor(overallSeverity).withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with severity and time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getSeverityColor(overallSeverity),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _getSeverityIcon(overallSeverity),
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              overallSeverity.toUpperCase(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _getSeverityColor(overallSeverity),
                              ),
                            ),
                            Text(
                              _formatTimestamp(timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[500],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Anomaly Summary
                if (anomalyCount > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.warning,
                                color: Colors.blue[600],
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$anomalyCount Anomaly${anomalyCount != 1 ? 'ies' : ''} Detected',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                        if (earliestAnomaly['timestamp'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'First anomaly: ${_formatTimestamp(earliestAnomaly['timestamp'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildAnomalyChips(anomalyDetails),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Disease Predictions Summary
                if (predictions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green[100]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.medical_services,
                                color: Colors.green[600],
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${predictions.length} Condition${predictions.length != 1 ? 's' : ''} Predicted',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...predictions.take(2).map((disease) {
                          final diseaseName = disease['disease_name']?.toString() ?? 'Unknown';
                          final confidence = (disease['confidence'] ?? 0) * 100;
                          final severity = disease['severity']?.toString() ?? 'Normal';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getSeverityColor(severity),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    diseaseName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getSeverityColor(severity).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${confidence.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _getSeverityColor(severity),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (predictions.length > 2)
                          GestureDetector(
                            onTap: () {
                              _showPredictionDetails(prediction);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Text(
                                    '+ ${predictions.length - 2} more conditions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.arrow_forward,
                                    size: 14,
                                    color: Colors.blue[600],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Action Required
                if (healthReport['action_required']?.toString() != null &&
                    healthReport['action_required'].toString() != 'None')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(overallSeverity).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _getSeverityColor(overallSeverity),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: _getSeverityColor(overallSeverity),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Action Required',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getSeverityColor(overallSeverity),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                healthReport['action_required'].toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _getSeverityColor(overallSeverity),
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
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(
            begin: 0.1,
            end: 0,
            duration: 300.ms,
          ),
    );
  }

  void _showPredictionDetails(Map<String, dynamic> prediction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return PredictionDetailsSheet(prediction: prediction);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Disease Predictions',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiseasePredictions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _error != null
              ? _buildErrorState()
              : !_hasData
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _loadDiseasePredictions,
                      color: Theme.of(context).primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _predictions.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildPredictionCard(_predictions[index]),
                          );
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_predictions.isNotEmpty) {
            _showPredictionsSummary();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No predictions available for summary'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        icon: const Icon(Icons.insights),
        label: const Text('Summary'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showPredictionsSummary() {
    final criticalCount = _predictions
        .where((p) => (p['overall_severity']?.toString() ?? '').toLowerCase() == 'critical')
        .length;
    final highCount = _predictions
        .where((p) => (p['overall_severity']?.toString() ?? '').toLowerCase() == 'high')
        .length;
    final moderateCount = _predictions
        .where((p) => (p['overall_severity']?.toString() ?? '').toLowerCase() == 'moderate')
        .length;
    
    // Fixed: Handle both int and num types from Firebase
    final totalAnomalies = _predictions.fold<int>(0, (sum, p) {
      final anomalyAnalysis = _convertMap(p['anomaly_analysis'] ?? {});
      final count = anomalyAnalysis['anomaly_count'];
      if (count is int) {
        return sum + count;
      } else if (count is num) {
        return sum + count.toInt();
      }
      return sum;
    });

    // Fixed: Handle list length properly
    final totalDiseases = _predictions.fold<int>(0, (sum, p) {
      final predictionsList = _convertList(p['all_predictions'] ?? []);
      return sum + predictionsList.length;
    });

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Health Analysis Summary',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[900],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Stats Grid
                  SizedBox(
                    height: 180,
                    child: GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _buildStatCard(
                          icon: Icons.warning,
                          count: totalAnomalies,
                          label: 'Total Anomalies',
                          color: Colors.blue,
                        ),
                        _buildStatCard(
                          icon: Icons.medical_services,
                          count: totalDiseases,
                          label: 'Conditions',
                          color: Colors.green,
                        ),
                        _buildStatCard(
                          icon: Icons.assignment,
                          count: _predictions.length,
                          label: 'Reports',
                          color: Colors.purple,
                        ),
                        _buildStatCard(
                          icon: Icons.timeline,
                          count: _predictions.length,
                          label: 'Analyses',
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Severity Distribution
                  Text(
                    'Severity Distribution',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSeverityStat(
                        count: criticalCount,
                        label: 'Critical',
                        color: Colors.red,
                      ),
                      _buildSeverityStat(
                        count: highCount,
                        label: 'High',
                        color: Colors.orange,
                      ),
                      _buildSeverityStat(
                        count: moderateCount,
                        label: 'Moderate',
                        color: Colors.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required int count,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityStat({
    required int count,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}

class PredictionDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> prediction;

  const PredictionDetailsSheet({super.key, required this.prediction});

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'moderate':
        return Colors.amber;
      case 'low':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  // FIXED: Safe type conversion helper
  Map<String, dynamic> _convertMap(dynamic data) {
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return {};
  }

  // FIXED: Convert list safely
  List<Map<String, dynamic>> _convertList(dynamic data) {
    if (data is List) {
      return data.map((item) {
        if (item is Map) {
          return item.cast<String, dynamic>();
        }
        return <String, dynamic>{};
      }).toList();
    }
    return [];
  }

  // UPDATED: Convert Unix timestamp to local DateTime
  DateTime? _getLocalDateTime(dynamic timestamp) {
    try {
      if (timestamp == null) return null;
      
      // Handle int/double Unix timestamp (in seconds)
      if (timestamp is int || timestamp is double) {
        final ts = timestamp.toDouble();
        // If timestamp is in milliseconds (like 1698765432000), convert to seconds
        if (ts > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: false);
        } else {
          // Timestamp is already in seconds (like 1698765432)
          return DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt(), isUtc: false);
        }
      }
      
      // Handle string (could be Unix timestamp string)
      if (timestamp is String) {
        final numValue = num.tryParse(timestamp);
        if (numValue != null) {
          if (numValue > 1000000000000) {
            return DateTime.fromMillisecondsSinceEpoch(numValue.toInt(), isUtc: false);
          } else {
            return DateTime.fromMillisecondsSinceEpoch((numValue * 1000).toInt(), isUtc: false);
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error converting timestamp: $e');
      return null;
    }
  }

  // UPDATED: Format timestamp relative to now
  String _formatTimestamp(dynamic timestamp) {
    final localDate = _getLocalDateTime(timestamp);
    if (localDate == null) return 'Recently';
    
    final now = DateTime.now();
    final difference = now.difference(localDate);
    
    if (difference.inDays > 365) {
      return DateFormat('MMM yyyy').format(localDate);
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // UPDATED: Format detailed timestamp
  String _formatDetailedTimestamp(dynamic timestamp) {
    final localDate = _getLocalDateTime(timestamp);
    if (localDate == null) return 'Unknown time';
    
    return DateFormat('MMM dd, yyyy - hh:mm a').format(localDate);
  }

  @override
  Widget build(BuildContext context) {
    final overallSeverity = prediction['overall_severity']?.toString() ?? 'Normal';
    final timestamp = prediction['timestamp'];
    final predictions = _convertList(prediction['all_predictions'] ?? []);
    final healthReport = _convertMap(prediction['health_report'] ?? {});
    final anomalyAnalysis = _convertMap(prediction['anomaly_analysis'] ?? {});
    final anomalyDetails = _convertList(anomalyAnalysis['anomaly_details'] ?? []);
    final anomalyCount = anomalyAnalysis['anomaly_count'] ?? 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getSeverityColor(overallSeverity),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.medical_services,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Disease Prediction Report',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                        ),
                        Text(
                          _formatDetailedTimestamp(timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Anomaly Analysis Section
              if (anomalyCount > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anomaly Analysis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$anomalyCount Anomalies Detected',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[900],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...anomalyDetails.map((anomaly) {
                            final vital = anomaly['vital']?.toString() ?? 'Unknown';
                            final type = anomaly['type']?.toString() ?? 'unknown';
                            final value = anomaly['value']?.toString() ?? '';
                            final timestamp = anomaly['timestamp'];
                            final time = _formatTimestamp(timestamp);
                            final severity = anomaly['severity']?.toString() ?? 'Normal';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _getSeverityColor(severity).withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: _getSeverityColor(severity),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          vital[0].toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$vital: $value',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.access_time,
                                                size: 12,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                time,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '${type.toUpperCase()}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Chip(
                                      label: Text(
                                        severity,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: _getSeverityColor(severity),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),

              // Disease Predictions Section
              if (predictions.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Predicted Conditions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...predictions.map((disease) {
                      final diseaseName = disease['disease_name']?.toString() ?? 'Unknown';
                      final confidence = (disease['confidence'] ?? 0) * 100;
                      final severity = disease['severity']?.toString() ?? 'Normal';
                      final category = disease['category']?.toString() ?? 'General';
                      final description = disease['description']?.toString() ?? '';
                      final symptoms = disease['symptoms'] is List ? 
                          List<String>.from(disease['symptoms'] ?? []) : [];
                      final recommendations = disease['recommendations'] is List ? 
                          List<String>.from(disease['recommendations'] ?? []) : [];
                      final anomalyPattern = disease['anomaly_pattern']?.toString() ?? '';
                      final anomalyTimestamp = disease['earliest_anomaly_time'];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(severity).withOpacity(0.1),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          diseaseName,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[900],
                                          ),
                                        ),
                                        Text(
                                          category,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getSeverityColor(severity),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${confidence.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Body
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Description
                                  if (description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Text(
                                        description,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  
                                  // Anomaly Info
                                  if (anomalyPattern.isNotEmpty || anomalyTimestamp != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (anomalyPattern.isNotEmpty)
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.timeline,
                                                  size: 16,
                                                  color: Colors.blue[600],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Triggered by: $anomalyPattern',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          if (anomalyTimestamp != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.access_time,
                                                    size: 16,
                                                    color: Colors.blue[600],
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'First anomaly: ${_formatTimestamp(anomalyTimestamp)}',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  
                                  // Symptoms
                                  if (symptoms.isNotEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Symptoms:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: symptoms.map((symptom) {
                                            return Chip(
                                              label: Text(
                                                symptom.toString(),
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                              backgroundColor: Colors.orange[50],
                                              side: BorderSide(
                                                color: Colors.orange[100]!,
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  
                                  const SizedBox(height: 16),
                                  
                                  // Recommendations
                                  if (recommendations.isNotEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Recommendations:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey[800],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ...recommendations.map((rec) {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 8),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.check_circle,
                                                  size: 16,
                                                  color: Colors.green[500],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    rec.toString(),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey[700],
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 24),
                  ],
                ),

              // Overall Recommendations
              if (healthReport['recommendations'] is List)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall Recommendations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ...List<String>.from(healthReport['recommendations'] ?? []).map((rec) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.arrow_forward,
                                    size: 16,
                                    color: Colors.green[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      rec.toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}