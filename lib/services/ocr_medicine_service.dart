// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class OcrMedicineService {
  static const String _apiKey = 'YOUR_ANTHROPIC_API_KEY';
  static const String _model = 'claude-haiku-4-5-20251001';

  /// カメラ/ファイル選択を開き、base64画像を返す
  Future<({String base64, String mediaType})?> pickImage() async {
    final completer = Completer<({String base64, String mediaType})?>();

    js.context['_ocrImagePicked'] = js.JsFunction.withThis(
        (_, dynamic b64, dynamic mt) {
      if (!completer.isCompleted) {
        if (b64 == null) {
          completer.complete(null);
        } else {
          completer.complete(
              (base64: b64.toString(), mediaType: mt?.toString() ?? 'image/jpeg'));
        }
      }
    });

    js.context.callMethod('eval', [r'''
      (function() {
        var input = document.createElement('input');
        input.type = 'file';
        input.accept = 'image/*';
        input.style.display = 'none';
        document.body.appendChild(input);
        input.addEventListener('change', function(e) {
          var file = e.target.files && e.target.files[0];
          if (!file) {
            if (window._ocrImagePicked) { window._ocrImagePicked(null, null); window._ocrImagePicked = null; }
            document.body.removeChild(input);
            return;
          }
          var reader = new FileReader();
          reader.onload = function(ev) {
            var dataUrl = ev.target.result;
            var comma = dataUrl.indexOf(',');
            var base64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
            var mt = file.type || 'image/jpeg';
            if (window._ocrImagePicked) { window._ocrImagePicked(base64, mt); window._ocrImagePicked = null; }
            document.body.removeChild(input);
          };
          reader.onerror = function() {
            if (window._ocrImagePicked) { window._ocrImagePicked(null, null); window._ocrImagePicked = null; }
            document.body.removeChild(input);
          };
          reader.readAsDataURL(file);
        });
        input.addEventListener('cancel', function() {
          if (window._ocrImagePicked) { window._ocrImagePicked(null, null); window._ocrImagePicked = null; }
          try { document.body.removeChild(input); } catch(e) {}
        });
        input.click();
      })()
    ''']);

    return completer.future;
  }

  /// base64画像からClaude Vision APIで薬剤情報を抽出
  Future<List<Map<String, dynamic>>?> extractMedicines(
      String base64Image, String mediaType) async {
    if (_apiKey == 'YOUR_ANTHROPIC_API_KEY') {
      return _mockResult();
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 1024,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mediaType,
                    'data': base64Image,
                  },
                },
                {
                  'type': 'text',
                  'text': '''この薬袋・処方箋の画像から薬剤情報を抽出してください。
以下のJSON形式のみで返してください（説明文不要）：
[{"name":"薬品名","dosage":"用量・規格","frequency":"用法（例:朝昼夕食後）","purpose":"効能・目的"}]
薬品が複数ある場合は配列に追加してください。
情報が不明な場合は空文字列にしてください。
JSONのみ返し、他の文章は一切含めないでください。'''
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('OCR API error: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] as List?)?.first as Map<String, dynamic>?;
      final text = content?['text'] as String? ?? '';

      return _parseJsonResponse(text);
    } catch (e) {
      debugPrint('OCR extraction error: $e');
      return null;
    }
  }

  List<Map<String, dynamic>>? _parseJsonResponse(String text) {
    try {
      // JSON部分だけ抽出
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start < 0 || end < 0) return null;
      final jsonStr = text.substring(start, end + 1);
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) => (m['name'] as String? ?? '').isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('OCR JSON parse error: $e\nRaw: $text');
      return null;
    }
  }

  List<Map<String, dynamic>> _mockResult() {
    return [
      {
        'name': 'アムロジピン錠5mg「サワイ」',
        'dosage': '5mg 1錠',
        'frequency': '朝食後',
        'purpose': '高血圧症',
      },
      {
        'name': 'ロスバスタチン錠2.5mg',
        'dosage': '2.5mg 1錠',
        'frequency': '夕食後',
        'purpose': '高コレステロール血症',
      },
    ];
  }
}
