import { UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import {
  AbilityAware, AbilityPluginBinding, FlutterPlugin, FlutterPluginBinding,
  MethodCall, MethodCallHandler, MethodChannel, MethodResult
} from '@ohos/flutter_ohos';

const MAX_BYTES: number = 10 * 1024 * 1024;

class DataFileError extends Error {
  readonly code: string;
  constructor(code: string, message: string) { super(message); this.code = code; }
}

interface PickedBackup { name: string; content: string; }

/** Only operates on a URI explicitly chosen in the system document picker. */
export default class FeedReminderDataFiles implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private ability: UIAbility | undefined;
  private busy: boolean = false;

  getUniqueClassName(): string { return 'FeedReminderDataFiles'; }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'feed_reminder/data_files');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.ability = undefined;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void { this.ability = binding.getAbility(); }
  onDetachedFromAbility(): void { this.ability = undefined; }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'saveFile' && call.method !== 'pickBackup') {
      result.notImplemented();
      return;
    }
    if (this.busy) {
      result.error('file_picker_busy', '请先完成当前文件操作。', null);
      return;
    }
    this.busy = true;
    void this.perform(call, result);
  }

  private async perform(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const ability = this.ability;
      if (ability === undefined) throw new DataFileError('ability_unavailable', '请返回应用后操作文件。');
      const documentPicker = new picker.DocumentViewPicker(ability.context);
      if (call.method === 'saveFile') result.success(await this.saveFile(call, documentPicker));
      else result.success(await this.pickBackup(documentPicker));
    } catch (error) {
      if (error instanceof DataFileError) result.error(error.code, error.message, null);
      else {
        const businessError = error as BusinessError;
        result.error('data_file_failed', '文件操作失败，请重新选择文件后重试。', businessError.code?.toString() ?? '');
      }
    } finally {
      this.busy = false;
    }
  }

  private async saveFile(call: MethodCall, documentPicker: picker.DocumentViewPicker): Promise<boolean> {
    const name: string = call.argument('suggestedName');
    const content: string = call.argument('content');
    const extension: string = call.argument('extension');
    const mime: string = call.argument('mimeType');
    if (typeof name !== 'string' || name.length === 0 || name.length > 180 || /[\\/\x00-\x1f]/.test(name) ||
      typeof content !== 'string' ||
      !((extension === 'json' && mime === 'application/json') || (extension === 'csv' && mime === 'text/csv'))) {
      throw new DataFileError('invalid_arguments', '导出文件参数无效。');
    }
    // Method-channel string decoding may strip the initial BOM. Reintroduce it
    // at the final UTF-8 byte boundary so spreadsheet apps identify CSV Chinese.
    const fileContent = extension === 'csv' && !content.startsWith('\uFEFF') ? '\uFEFF' + content : content;
    const bytes = new util.TextEncoder().encodeInto(fileContent);
    if (bytes.byteLength > MAX_BYTES) throw new DataFileError('file_too_large', '文件不能超过 10 MiB。');
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [name];
    options.fileSuffixChoices = ['.' + extension];
    const uris = await documentPicker.save(options);
    if (uris.length === 0) return false;
    const file = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      let written = 0;
      while (written < bytes.byteLength) {
        const chunk = bytes.slice(written, Math.min(written + 65536, bytes.byteLength));
        const count = await fileIo.write(file.fd, chunk.buffer, { offset: written });
        if (count <= 0) throw new DataFileError('file_write_failed', '文件未能完整写入，请重新导出。');
        written += count;
      }
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    return true;
  }

  private async pickBackup(documentPicker: picker.DocumentViewPicker): Promise<PickedBackup | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['奶点记备份|.json'];
    const uris = await documentPicker.select(options);
    if (uris.length === 0) return null;
    const uri = uris[0];
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let content = '';
    try {
      const stat = await fileIo.stat(file.fd);
      if (!stat.isFile()) throw new DataFileError('invalid_file', '请选择 JSON 备份文件。');
      if (stat.size > MAX_BYTES) throw new DataFileError('file_too_large', '文件不能超过 10 MiB。');
      const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: false });
      let read = 0;
      while (read < stat.size) {
        const chunk = new ArrayBuffer(Math.min(65536, stat.size - read));
        const count = await fileIo.read(file.fd, chunk, { offset: read, length: chunk.byteLength });
        if (count <= 0) throw new DataFileError('file_changed', '文件读取期间发生变化，请重新选择。');
        read += count;
        try {
          content += decoder.decodeToString(new Uint8Array(chunk, 0, count), { stream: read < stat.size });
        } catch (_) {
          throw new DataFileError('invalid_encoding', '备份必须为有效的 UTF-8 文件。');
        }
      }
      if ((await fileIo.stat(file.fd)).size !== stat.size) {
        throw new DataFileError('file_changed', '文件读取期间发生变化，请重新选择。');
      }
    } finally {
      await fileIo.close(file);
    }
    const lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
    let name = '备份.json';
    try { name = decodeURIComponent(lastSegment) || name; } catch (_) { /* Keep a safe display name. */ }
    return { name: name, content: content };
  }
}
