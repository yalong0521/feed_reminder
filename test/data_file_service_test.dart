import 'dart:convert';

import 'package:feed_reminder/models/backup_document.dart';
import 'package:feed_reminder/services/data_file_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DownloadPicker extends FilePickerPlatform {
  Object? failure;
  Uint8List? receivedBytes;
  PlatformFile? picked;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['json']);
    if (failure != null) throw failure!;
    return picked;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (failure != null) throw failure!;
    receivedBytes = bytes;
    // The installed web implementation returns null after anchor.click().
    return null;
  }
}

final class _StreamFile extends PlatformFile {
  _StreamFile(this.stream, {this.reportedSize});

  final Stream<Uint8List> stream;
  final int? reportedSize;
  bool opened = false;

  @override
  String get name => 'backup.json';
  @override
  Uri get uri => Uri.parse('file:///backup.json');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => reportedSize;
  @override
  Future<int?> length() async => reportedSize;
  @override
  Future<Uint8List> readAsBytes() => throw UnimplementedError();
  @override
  Stream<Uint8List> readAsByteStream() {
    opened = true;
    return stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('feed_reminder/data_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = DataFileService(harmonyOS: true);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native streamed import handles cancellation, split UTF-8 and failures',
    () async {
      final previous = FilePickerPlatform.instance;
      final picker = _DownloadPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final native = DataFileService(harmonyOS: false, web: false);
      expect(await native.pickBackup(), isNull);
      final bytes = utf8.encode('\uFEFF{"备注":"奶量"}');
      picker.picked = _StreamFile(
        Stream.fromIterable([
          for (final byte in bytes) Uint8List.fromList([byte]),
        ]),
      );
      expect((await native.pickBackup())!.content, '{"备注":"奶量"}');
      picker.picked = _StreamFile(
        Stream.value(Uint8List.fromList([0xc3, 0x28])),
      );
      await expectLater(native.pickBackup(), throwsFormatException);
      picker.picked = _StreamFile(Stream.error(StateError('read failed')));
      await expectLater(native.pickBackup(), throwsStateError);
    },
  );

  test(
    'native importer rejects reported size before read and bounds growing stream',
    () async {
      final previous = FilePickerPlatform.instance;
      final picker = _DownloadPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final native = DataFileService(harmonyOS: false, web: false);
      final oversize = _StreamFile(
        const Stream.empty(),
        reportedSize: BackupDocument.maxBytes + 1,
      );
      picker.picked = oversize;
      await expectLater(native.pickBackup(), throwsFormatException);
      expect(oversize.opened, isFalse);
      var stopped = false;
      var chunksRead = 0;
      Stream<Uint8List> growing() async* {
        try {
          for (var i = 0; i < 12; i++) {
            chunksRead++;
            yield Uint8List(1024 * 1024);
          }
        } finally {
          stopped = true;
        }
      }

      picker.picked = _StreamFile(growing(), reportedSize: 1);
      await expectLater(native.pickBackup(), throwsFormatException);
      expect(chunksRead, 11);
      expect(stopped, isTrue);
    },
  );

  test(
    'web null result is a dispatched download while native null is cancel',
    () async {
      final previous = FilePickerPlatform.instance;
      final picker = _DownloadPicker();
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      Future<bool> save(bool web) => DataFileService(web: web).saveFile(
        suggestedName: 'records.csv',
        content: '\uFEFF奶量,未记录\r\n',
        extension: 'csv',
        mimeType: 'text/csv',
      );
      expect(await save(true), isTrue);
      expect(picker.receivedBytes, utf8.encode('\uFEFF奶量,未记录\r\n'));
      expect(await save(false), isFalse);
      picker.failure = UnsupportedError('download unavailable');
      expect(save(true), throwsUnsupportedError);
    },
  );

  test(
    'Harmony file bridge identifies CSV for native BOM restoration',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'saveFile');
        expect(call.arguments, {
          'suggestedName': 'records.csv',
          // StandardMethodCodec strips a leading BOM while decoding strings.
          // The Harmony bridge restores it when extension is csv.
          'content': '记录\r\n',
          'extension': 'csv',
          'mimeType': 'text/csv',
        });
        return true;
      });
      expect(
        await service.saveFile(
          suggestedName: 'records.csv',
          content: '\uFEFF记录\r\n',
          extension: 'csv',
          mimeType: 'text/csv',
        ),
        isTrue,
      );
    },
  );

  test(
    'Harmony picker cancel is distinct from failure and saved result',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'saveFile' ? false : null,
      );
      expect(await service.pickBackup(), isNull);
      expect(
        await service.saveFile(
          suggestedName: 'backup.json',
          content: '{}',
          extension: 'json',
          mimeType: 'application/json',
        ),
        isFalse,
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'READ_FAILED'),
      );
      expect(service.pickBackup(), throwsA(isA<PlatformException>()));
    },
  );

  test(
    'Harmony result is validated before exposing imported content',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'name': 'test.json', 'content': '{}'},
      );
      final file = await service.pickBackup();
      expect(file!.name, 'test.json');
      expect(file.content, '{}');
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'name': 'test.json', 'content': 10},
      );
      expect(service.pickBackup(), throwsFormatException);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'name': 'test.json',
          'content': 'x' * (BackupDocument.maxBytes + 1),
        },
      );
      expect(service.pickBackup(), throwsFormatException);
    },
  );
}
