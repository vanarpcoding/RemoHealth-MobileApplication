import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static const String apiKey = '';
  static const String apiUrl = 'https://openrouter.ai/api/v1/chat/completions';

  Future<String> getGeminiResponse(String prompt) async {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': '',
    };

    final body = jsonEncode({
      //'model': 'gemini-1.3-chat',
      //'model': 'google/gemini-pro',
      'model': 'google/gemini-2.5-pro',
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'max_tokens': 1000,
    });

    final response =
        await http.post(Uri.parse(apiUrl), headers: headers, body: body);

    if (response.statusCode == 200) {
      final responseJson = jsonDecode(response.body);
      final content = responseJson['choices'][0]['message']['content'];
      return content;
    } else {
      throw Exception('Failed to load Gemini response');
    }
  }
}
