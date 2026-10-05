import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/backup_document.dart';

class DataFile {
  const DataFile({required this.name, required this.content});

  final String name;
  final String content;
}

/// All platforms use a system picker; only selected files are accessed.
class DataFileService {
  DataFileService({bool? harmonyOS, bool? web, MethodChannel? channel})
    : _harmonyOS =
          harmonyOS ?? (!kIsWeb && defaultTargetPlatform.name == 'ohos'),
      _web = web ?? kIsWeb,
      _channel = channel ?? const MethodChannel('feed_reminder/data_files');

  final bool _harmonyOS;
  final bool _web;
  final MethodChannel _channel;

  Future<DataFile?> pickBackup() async {
    if (_harmonyOS) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickBackup',
      );
      if (result == null) return null;
      if (result['name'] is! String || result['content'] is! String) {
        throw const FormatException('读取的备份内容无效，请重新选择');
      }
      final content = result['content'] as String;
      _checkSize(utf8.encode(content).length);
      return DataFile(name: result['name'] as String, content: content);
    }
    final file = await FilePicker.pickFile(
      dialogTitle: '选择奶点记备份',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (file == null) return null;
    final length = file.lengthSync() ?? await file.length();
    if (length != null) _checkSize(length);
    // Bound reads too: a file may grow after the picker reported its size.
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      _checkSize(builder.length + chunk.length);
      builder.add(chunk);
    }
    try {
      return DataFile(
        name: file.name,
        content: utf8.decode(builder.takeBytes(), allowMalformed: false),
      );
    } on FormatException {
      throw const FormatException('文件不是有效的 UTF-8 备份');
    }
  }

  /// Native platforms return after writing; web returns after download dispatch.
  /// false means the picker was canceled.
  Future<bool> saveFile({
    required String suggestedName,
    required String content,
    required String extension,
    required String mimeType,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    _checkSize(bytes.length);
    if (_harmonyOS) {
      return await _channel.invokeMethod<bool>('saveFile', {
            'suggestedName': suggestedName,
            'content': content,
            'extension': extension,
            'mimeType': mimeType,
          }) ??
          false;
    }
    final result = await FilePicker.saveFile(
      fileName: suggestedName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: '保存奶点记文件',
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    // file_picker_web 4.0.0 dispatches a Blob download and returns null even
    // on success. Browser downloads have no completion/cancellation result;
    // the screen therefore reports dispatch rather than a completed save.
    return _web || result != null;
  }

  static void _checkSize(int bytes) {
    if (bytes > BackupDocument.maxBytes) {
      throw const FormatException('文件超过 10 MiB，请选择较小的备份');
    }
  }
}
