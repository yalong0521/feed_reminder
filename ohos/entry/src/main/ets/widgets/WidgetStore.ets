import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formProvider } from '@kit.FormKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class WidgetSnapshot {
  schemaVersion: number = 1;
  generatedAtMs: number = 0;
  dateKey: string = '';
  zoneOffsetMinutes: number = 0;
  latestTimeMs: number | null = null;
  latestTimeZoneOffsetMinutes: number | null = null;
  latestMilkAmountMl: number = 0;
  dayTotalMl: number = 0;
  dayCount: number = 0;
  nextFeedTimeMs: number | null = null;
  nextFeedTimeZoneOffsetMinutes: number | null = null;
  reminderAcknowledged: boolean = false;
}

export class WidgetViewData {
  ready: boolean = false;
  hasRecords: boolean = false;
  latestTime: string = '暂无记录';
  latestDate: string = '';
  latestClock: string = '暂无记录';
  latestAmount: string = '记录第一餐';
  summaryDate: string = '当日汇总';
  totalAmount: string = '—';
  feedCount: string = '—';
  nextReminder: string = '打开奶点记后显示记录';
  compactReminderLabel: string = '奶点记';
  compactReminderValue: string = '打开应用';
  updatedAt: string = '数据仅在本机保存';
}

const SNAPSHOT_STORE: string = 'feed_widget_snapshot_v1';
const FORM_STORE: string = 'feed_widget_instances_v1';

/** Preferences are single-process only. Each process owns its own preferences;
 * atomic JSON files publish read-only projections to the other process.
 */
export class WidgetStore {
  private static async fresh(context: common.Context, name: string): Promise<preferences.Preferences> {
    await preferences.removePreferencesFromCache(context, name);
    return preferences.getPreferences(context, { name: name });
  }

  static valid(snapshot: WidgetSnapshot): boolean {
    return snapshot.schemaVersion === 1 &&
      Number.isSafeInteger(snapshot.generatedAtMs) &&
      typeof snapshot.dateKey === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(snapshot.dateKey) &&
      Number.isInteger(snapshot.zoneOffsetMinutes) && Math.abs(snapshot.zoneOffsetMinutes) <= 840 &&
      (snapshot.latestTimeMs === null || Number.isSafeInteger(snapshot.latestTimeMs)) &&
      WidgetStore.validOptionalOffset(snapshot.latestTimeZoneOffsetMinutes) &&
      Number.isInteger(snapshot.latestMilkAmountMl) && snapshot.latestMilkAmountMl >= 0 &&
      snapshot.latestMilkAmountMl <= 2000 &&
      Number.isSafeInteger(snapshot.dayTotalMl) && snapshot.dayTotalMl >= 0 &&
      Number.isSafeInteger(snapshot.dayCount) && snapshot.dayCount >= 0 &&
      (snapshot.nextFeedTimeMs === null || Number.isSafeInteger(snapshot.nextFeedTimeMs)) &&
      WidgetStore.validOptionalOffset(snapshot.nextFeedTimeZoneOffsetMinutes) &&
      typeof snapshot.reminderAcknowledged === 'boolean';
  }

  private static validOptionalOffset(value: number | null | undefined): boolean {
    // Version 1 snapshots from earlier app versions have no per-instant offsets.
    return value === null || value === undefined ||
      (Number.isInteger(value) && Math.abs(value) <= 840);
  }

  static async saveSnapshot(context: common.Context, snapshot: WidgetSnapshot): Promise<void> {
    if (!WidgetStore.valid(snapshot)) throw new Error('Invalid widget snapshot');
    const store = await WidgetStore.fresh(context, SNAPSHOT_STORE);
    await store.put('snapshot', JSON.stringify(snapshot));
    await store.flush();
    await WidgetStore.publish(context, 'feed_widget_snapshot.json', JSON.stringify(snapshot));
  }

  static async readSnapshot(context: common.Context): Promise<WidgetViewData> {
    const raw = await WidgetStore.readPublished(context, 'feed_widget_snapshot.json');
    if (raw.length === 0) return new WidgetViewData();
    const snapshot = JSON.parse(raw) as WidgetSnapshot;
    if (!WidgetStore.valid(snapshot)) return new WidgetViewData();
    return WidgetStore.viewData(snapshot);
  }

  static async changeForm(context: common.Context, id: string, remove: boolean): Promise<void> {
    if (!/^-?\d{1,24}$/.test(id)) return;
    const store = await WidgetStore.fresh(context, FORM_STORE);
    if (remove) await store.delete(id);
    else await store.put(id, true);
    await store.flush();
    await WidgetStore.publish(context, 'feed_widget_instances.json', JSON.stringify(Object.keys(await store.getAll())));
  }

  static async refreshAll(context: common.Context, snapshot: WidgetSnapshot): Promise<void> {
    const raw = await WidgetStore.readPublished(context, 'feed_widget_instances.json');
    const ids: string[] = raw.length === 0 ? [] : JSON.parse(raw) as string[];
    const data = WidgetStore.viewData(snapshot);
    let failed = false;
    // Keep refreshing the remaining instances if one was removed concurrently.
    for (const id of ids) {
      try {
        await formProvider.updateForm(id, formBindingData.createFormBindingData(data));
      } catch (error) {
        // A form removed between reading the index and updating it is already
        // gone. Do not turn that permanent absence into a retry on every tick.
        if ((error as BusinessError).code !== 16501001) failed = true;
      }
    }
    if (failed) throw new Error('One or more widgets could not be refreshed');
  }

  static viewData(snapshot: WidgetSnapshot): WidgetViewData {
    const data = new WidgetViewData();
    data.ready = true;
    data.hasRecords = snapshot.latestTimeMs !== null;
    data.summaryDate = snapshot.dateKey + ' 汇总';
    data.totalAmount = snapshot.dayTotalMl.toString() + ' mL';
    data.feedCount = snapshot.dayCount.toString() + ' 次';
    if (snapshot.latestTimeMs !== null) {
      data.latestTime = WidgetStore.time(snapshot.latestTimeMs,
        snapshot.latestTimeZoneOffsetMinutes ?? snapshot.zoneOffsetMinutes);
      data.latestDate = data.latestTime.substring(0, 5);
      data.latestClock = data.latestTime.substring(6);
      data.latestAmount = snapshot.latestMilkAmountMl === 0 ? '未记录奶量' :
        snapshot.latestMilkAmountMl.toString() + ' mL';
    }
    data.nextReminder = !data.hasRecords ? '记录后开始下一次提醒' :
      snapshot.reminderAcknowledged ? '本次提醒已停止' :
        snapshot.nextFeedTimeMs === null ? '暂无下次提醒' :
          '下次 ' + WidgetStore.time(snapshot.nextFeedTimeMs,
            snapshot.nextFeedTimeZoneOffsetMinutes ?? snapshot.zoneOffsetMinutes);
    if (!data.hasRecords) {
      data.compactReminderValue = '暂无记录';
    } else if (snapshot.reminderAcknowledged) {
      data.compactReminderLabel = '本次提醒';
      data.compactReminderValue = '已停止';
    } else if (snapshot.nextFeedTimeMs === null) {
      data.compactReminderLabel = '下次喂奶';
      data.compactReminderValue = '暂无提醒';
    } else {
      const nextTime = WidgetStore.time(snapshot.nextFeedTimeMs,
        snapshot.nextFeedTimeZoneOffsetMinutes ?? snapshot.zoneOffsetMinutes);
      data.compactReminderLabel = '下次喂奶 · ' + nextTime.substring(0, 5);
      data.compactReminderValue = nextTime.substring(6);
    }
    const offset = snapshot.zoneOffsetMinutes;
    const zone = 'UTC' + (offset >= 0 ? '+' : '-') +
      WidgetStore.pad(Math.floor(Math.abs(offset) / 60)) + ':' + WidgetStore.pad(Math.abs(offset) % 60);
    data.updatedAt = '更新于 ' + WidgetStore.time(snapshot.generatedAtMs, offset) + ' · ' + zone;
    return data;
  }

  private static pad(value: number): string {
    return value.toString().padStart(2, '0');
  }

  private static async publish(context: common.Context, name: string, content: string): Promise<void> {
    const path = context.getApplicationContext().filesDir + '/' + name;
    // Each filename has one writer process and writes are serialized there.
    // Readers see either complete old or complete new content after rename.
    const staging = path + '.pending';
    const file = await fileIo.open(staging, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      // The projections contain ASCII only (timestamps, IDs, booleans, numbers).
      let written = 0;
      while (written < content.length) {
        const count = await fileIo.write(file.fd, content.substring(written), { offset: written });
        if (count <= 0) throw new Error('Incomplete widget projection');
        written += count;
      }
      await fileIo.fsync(file.fd);
    } finally {
      await fileIo.close(file);
    }
    await fileIo.rename(staging, path);
  }

  private static async readPublished(context: common.Context, name: string): Promise<string> {
    const path = context.getApplicationContext().filesDir + '/' + name;
    // Missing means the app has not published a consented snapshot / no widget
    // has been added yet. Other I/O failures propagate, keeping last rendered data.
    if (!await fileIo.access(path)) return '';
    const stat = await fileIo.stat(path);
    if (stat.size > 131072) throw new Error('Invalid widget projection size');
    return fileIo.readText(path);
  }

  private static time(epoch: number, offsetMinutes: number): string {
    const date = new Date(epoch + offsetMinutes * 60000);
    return WidgetStore.pad(date.getUTCMonth() + 1) + '/' + WidgetStore.pad(date.getUTCDate()) +
      ' ' + WidgetStore.pad(date.getUTCHours()) + ':' + WidgetStore.pad(date.getUTCMinutes());
  }
}
