import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ModelDownloadService {
  static Future<String> modelsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/models');
    await modelsDir.create(recursive: true);
    return modelsDir.path;
  }

  static Future<bool> fileExists(String modelsDir, String filename) =>
      File('$modelsDir/$filename').exists();

  static Future<void> download(
    String url, {
    required String destPath,
    void Function(double progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send();
    if (response.statusCode != 200) {
      throw HttpException(
        'Download failed: HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    final total = response.contentLength ?? 0;
    int received = 0;

    final file = File(destPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } catch (e) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
  }

  static Future<void> deleteFile(String modelsDir, String filename) async {
    final file = File('$modelsDir/$filename');
    if (await file.exists()) await file.delete();
  }
}
