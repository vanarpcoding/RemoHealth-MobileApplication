import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'homepage.dart'; // Adjust or remove if HealthData is not needed

class Chatbot extends StatefulWidget {
  final HealthData? healthData;
  final List<String> anomalies;

  const Chatbot({
    super.key,
    this.healthData,
    required this.anomalies,
  });

  @override
  State<Chatbot> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<Chatbot> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  // List of map to hold chat history: {'sender': 'user' or 'bot', 'message': '...'}
  final List<Map<String, String>> _chatMessages = [];

  static const String _apiKey = ''; // Replace with your key
  static const String _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

  Future<String> _sendMessageToGemini(String message) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer apikey',
    };

    final body = jsonEncode({
      //'model': 'gemini-1.3-chat',
      //'model': 'google/gemini-pro',
      'model':'google/gemini-2.5-pro',
      'messages': [
        {'role': 'user', 'content': message}
      ],
      'max_tokens': 1000,
    });

    final response = await http.post(Uri.parse(_apiUrl), headers: headers, body: body);

print('Status code: ${response.statusCode}');
print('Response body: ${response.body}');

if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  print('Parsed JSON: $data');
  final content = data['choices'][0]['message']['content'];
  return content;
} else {
  final errorData = jsonDecode(response.body);
  print('Error response: $errorData');
  return 'Sorry, I am having trouble responding right now.';
}

  }

  String getRecommendation(String anomaly) {
    if (anomaly.contains("Heart Rate (too low)")) {
      return "A low heart rate (below 60 bpm) may indicate bradycardia. Please rest and consult a healthcare professional if you experience dizziness, fatigue, or fainting.";
    } else if (anomaly.contains("Heart Rate (too high)")) {
      return "A high heart rate (above 100 bpm) may suggest tachycardia. Avoid stimulants like caffeine, reduce stress, and seek medical advice if symptoms persist.";
    } else if (anomaly.contains("SpO2 (too low)")) {
      return "Low oxygen saturation (below 95%) could indicate a respiratory issue. Ensure proper ventilation, avoid exertion, and contact a doctor if you feel short of breath.";
    } else if (anomaly.contains("Temperature (too low)")) {
      return "A low temperature (below 36.1°C) may suggest hypothermia. Keep warm with blankets, avoid cold environments, and seek medical attention if symptoms worsen.";
    } else if (anomaly.contains("Temperature (too high)")) {
      return "A high temperature (above 37.2°C) may indicate a fever. Stay hydrated, rest, and consult a healthcare provider if the fever exceeds 38°C or persists.";
    }
    return "Please consult a healthcare professional for a thorough evaluation.";
  }

  void _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatMessages.add({'sender': 'user', 'message': text});
      _isLoading = true;
      _controller.clear();
    });

    final botResponse = await _sendMessageToGemini(text);

    setState(() {
      _chatMessages.add({'sender': 'bot', 'message': botResponse});
      _isLoading = false;
    });
  }

  Widget _buildChatBubble(Map<String, String> message) {
    bool isUser = message['sender'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message['message'] ?? '',
          style: TextStyle(color: isUser ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final healthData = widget.healthData;
    final anomalies = widget.anomalies;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Assistant'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text(
                  'Health Assessment',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Current Vital Signs:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Heart Rate: ${healthData?.bpm ?? "N/A"} bpm\n'
                  'Oxygen Level: ${healthData?.spo2.toStringAsFixed(1) ?? "N/A"} %\n'
                  'Temperature: ${healthData?.temperatureC.toStringAsFixed(1) ?? "N/A"} °C / '
                  '${healthData?.temperatureF.toStringAsFixed(1) ?? "N/A"} °F',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                if (anomalies.isNotEmpty) ...[
                  Text(
                    'Detected Anomalies:',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...anomalies.map((anomaly) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber,
                                color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                anomaly,
                                style:
                                    TextStyle(fontSize: 16, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                  Text(
                    'Recommended Actions:',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...anomalies.map((anomaly) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.local_hospital,
                                color: Colors.blue, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                getRecommendation(anomaly),
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      )),
                ] else ...[
                  const Text(
                    'No anomalies detected. Your vital signs are within normal ranges. Continue monitoring and consult a doctor for routine check-ups.',
                    style: TextStyle(fontSize: 16, color: Colors.green),
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Chat with your Health Assistant:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ..._chatMessages.map(_buildChatBubble).toList(),
                if (_isLoading)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                const SizedBox(height: 80), // To give space for input field
              ],
            ),
          ),
          // Input field fixed at bottom
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.grey.shade400,
                    offset: Offset(0, -1),
                    blurRadius: 4)
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration:
                        InputDecoration(hintText: 'Type your message...'),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.blue),
                  onPressed: _handleSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
