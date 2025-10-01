import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CloudinaryHelper {
  final String cloudName;
  final String? uploadPreset; // unsigned preset name (optional)

  CloudinaryHelper({required this.cloudName, this.uploadPreset});

  /// Uploads a local file unsigned to Cloudinary and returns secure_url on success.
  Future<String?> uploadUnsigned(File file) async {
    if (uploadPreset == null) throw Exception('uploadPreset is required for unsigned uploads');
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset!;
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return map['secure_url'] as String?;
    } else {
      // ignore: avoid_print
      print('cloudinary: upload failed ${resp.statusCode} ${resp.body}');
      return null;
    }
  }

  /// Upload using a server-signed flow. The [signServerUrl] should be the
  /// URL of your signing server (e.g. https://yourserver.com/sign). The helper
  /// requests a signature for the provided params (timestamp, folder, etc.) and
  /// uploads the file to Cloudinary with the returned signature and api_key.
  Future<String?> uploadSigned(File file, {required Uri signServerUrl, Map<String, String>? extraParams}) async {
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final params = <String, String>{'timestamp': timestamp};
    if (extraParams != null) params.addAll(extraParams);

    // Request signature from signing server
    final signResp = await http.post(signServerUrl, headers: {'Content-Type': 'application/json'}, body: jsonEncode(params));
    if (signResp.statusCode != 200) {
      // ignore: avoid_print
      print('cloudinary: signing server failed ${signResp.statusCode} ${signResp.body}');
      return null;
    }
    final signMap = jsonDecode(signResp.body) as Map<String, dynamic>;
    final signature = signMap['signature'] as String?;
    final apiKey = signMap['api_key'] as String?;
    if (signature == null || apiKey == null) {
      // ignore: avoid_print
      print('cloudinary: signing server returned invalid payload: ${signResp.body}');
      return null;
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/auto/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['timestamp'] = timestamp;
    request.fields['signature'] = signature;
    request.fields['api_key'] = apiKey;
    extraParams?.forEach((k, v) => request.fields[k] = v);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      return map['secure_url'] as String?;
    } else {
      // ignore: avoid_print
      print('cloudinary: signed upload failed ${resp.statusCode} ${resp.body}');
      return null;
    }
  }
}
