import 'dart:convert';
import 'package:http/http.dart' as http;

class HealthApiService {
  static const apiUrl = 'https://health-model-api-1.onrender.com';
  static const apiKey = '';

  Future<String> sendToModel(double heartRate, double spo2, double temp) async {
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      },
      body: jsonEncode({
        'heart_rate': heartRate,
        'spo2': spo2,
        'temperature_C': temp,
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return result['prediction'].toString();
    } else {
      throw Exception('Error: ${response.body}');
    }
  }
}
