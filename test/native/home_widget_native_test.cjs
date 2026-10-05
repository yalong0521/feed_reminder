// Executes the actual non-UI ArkTS control flow with in-memory platform fakes.
// Node 24's type stripping is not an ArkTS compiler or a Harmony device test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const { test } = require('node:test');

const widgets = path.resolve(__dirname, '../../ohos/entry/src/main/ets/widgets');

function load(file, names, fakes) {
  const source = fs.readFileSync(path.join(widgets, file), 'utf8')
    .replace(/^import[^;]+;\r?\n/gm, '')
    .replace(/^export default /gm, '')
    .replace(/^export /gm, '');
  const executable = stripTypeScriptTypes(source, { mode: 'strip' });
  const context = vm.createContext({ console: { warn() {} }, ...fakes });
  vm.runInContext(`${executable}\nthis.loaded = {${names.join(',')}};`, context);
  return context.loaded;
}

function formAbility(store, update) {
  const { FeedReminderFormAbility } = load('FeedReminderFormAbility.ets', ['FeedReminderFormAbility'], {
    FormExtensionAbility: class { context = {}; },
    WidgetStore: store,
    WidgetViewData: class {},
    formBindingData: { createFormBindingData: value => value },
    formProvider: { updateForm: update },
    formInfo: { FormParam: { IDENTITY_KEY: 'id' } },
  });
  return { ability: new FeedReminderFormAbility(), completed: () => FeedReminderFormAbility.changes };
}

test('older FormExtension refresh converges after racing a newer app publication', async () => {
  let published = { totalAmount: '90 mL' };
  let visible = published;
  const writes = [];
  const form = formAbility({
    async changeForm() {},
    async readSnapshot() { return published; },
  }, async (_, data) => {
    writes.push(data.totalAmount);
    if (data.totalAmount === '90 mL') {
      published = { totalAmount: '120 mL' };
      visible = published; // The app's new update finishes first.
      await Promise.resolve();
    }
    visible = data; // The older FormExtension update then completes last.
  });
  form.ability.onUpdateForm('1');
  await form.completed();
  assert.deepEqual(writes, ['90 mL', '120 mL']);
  assert.equal(visible.totalAmount, '120 mL');
});

test('failed instance index repair does not block reading a committed snapshot', async () => {
  const writes = [];
  const form = formAbility({
    async changeForm() { throw Error('disk full'); },
    async readSnapshot() { return { totalAmount: '120 mL' }; },
  }, async (_, data) => writes.push(data.totalAmount));
  form.ability.onUpdateForm('1');
  await form.completed();
  assert.deepEqual(writes, ['120 mL']);
});

test('failed form update stops the reconciliation loop without losing future refreshes', async () => {
  let failing = true;
  let attempts = 0;
  const form = formAbility({
    async changeForm() {},
    async readSnapshot() { return { totalAmount: '120 mL' }; },
  }, async () => {
    attempts++;
    if (failing) throw Error('IPC unavailable');
  });
  form.ability.onUpdateForm('1');
  await form.completed();
  assert.equal(attempts, 1);
  failing = false;
  form.ability.onUpdateForm('1');
  await form.completed();
  assert.equal(attempts, 2);
});

function widgetStore(fileIo, update, preferences = {}) {
  return load('WidgetStore.ets', ['WidgetStore', 'WidgetSnapshot', 'WidgetViewData'], {
    preferences,
    fileIo,
    formProvider: { updateForm: update },
    formBindingData: { createFormBindingData: value => value },
  });
}
const context = { getApplicationContext: () => ({ filesDir: '/sandbox' }) };

for (const code of [16501001, 16500050]) {
  test(`refreshes remaining forms after error ${code} and ignores only removed identities`, async () => {
    const updated = [];
    const { WidgetStore, WidgetSnapshot } = widgetStore({
      async access() { return true; },
      async stat() { return { size: 10 }; },
      async readText() { return '["1","2"]'; },
    }, async id => {
      updated.push(id);
      if (id === '1') throw { code };
    });
    const snapshot = new WidgetSnapshot();
    snapshot.dateKey = '2026-10-03';
    const refresh = WidgetStore.refreshAll(context, snapshot);
    if (code === 16501001) await refresh;
    else await assert.rejects(refresh);
    assert.deepEqual(updated, ['1', '2']);
  });
}

test('failed snapshot fsync closes staging file and never replaces committed projection', async () => {
  let closed = false;
  let renamed = false;
  const { WidgetStore, WidgetSnapshot } = widgetStore({
    OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
    async open() { return { fd: 1 }; },
    async write(_, content) { return Math.min(7, content.length); },
    async fsync() { throw Error('disk full'); },
    async close() { closed = true; },
    async rename() { renamed = true; },
  }, async () => {}, {
    async removePreferencesFromCache() {},
    async getPreferences() { return { async put() {}, async flush() {} }; },
  });
  const snapshot = new WidgetSnapshot();
  snapshot.dateKey = '2026-10-03';
  await assert.rejects(WidgetStore.saveSnapshot(context, snapshot));
  assert.equal(closed, true);
  assert.equal(renamed, false);
});

for (const scenario of [
  { name: 'spring forward', now: '2026-03-08T07:30:00Z', nowOffset: -240,
    meal: '2026-03-08T06:30:00Z', mealOffset: -300, mealLabel: '03/08 01:30',
    next: '2026-03-08T08:30:00Z', nextOffset: -240, nextLabel: '03/08 04:30' },
  { name: 'fall back', now: '2026-11-01T05:00:00Z', nowOffset: -240,
    meal: '2026-11-01T04:30:00Z', mealOffset: -240, mealLabel: '11/01 00:30',
    next: '2026-11-01T06:30:00Z', nextOffset: -300, nextLabel: '11/01 01:30' },
]) {
  test(`card keeps per-instant local times across ${scenario.name}`, () => {
    const { WidgetStore, WidgetSnapshot } = widgetStore({}, async () => {});
    const snapshot = new WidgetSnapshot();
    snapshot.dateKey = scenario.now.substring(0, 10);
    snapshot.generatedAtMs = Date.parse(scenario.now);
    snapshot.zoneOffsetMinutes = scenario.nowOffset;
    snapshot.latestTimeMs = Date.parse(scenario.meal);
    snapshot.latestTimeZoneOffsetMinutes = scenario.mealOffset;
    snapshot.nextFeedTimeMs = Date.parse(scenario.next);
    snapshot.nextFeedTimeZoneOffsetMinutes = scenario.nextOffset;
    assert.equal(WidgetStore.valid(snapshot), true);
    const data = WidgetStore.viewData(snapshot);
    assert.equal(data.latestTime, scenario.mealLabel);
    assert.equal(data.nextReminder, `下次 ${scenario.nextLabel}`);
    assert.equal(data.latestDate, scenario.mealLabel.substring(0, 5));
    assert.equal(data.latestClock, scenario.mealLabel.substring(6));
    assert.equal(data.compactReminderLabel, `下次喂奶 · ${scenario.nextLabel.substring(0, 5)}`);
    assert.equal(data.compactReminderValue, scenario.nextLabel.substring(6));
  });
}

test('legacy projections keep the published timezone and reject invalid new offsets', () => {
  const { WidgetStore, WidgetSnapshot } = widgetStore({}, async () => {});
  const snapshot = new WidgetSnapshot();
  snapshot.dateKey = '2026-10-03';
  snapshot.zoneOffsetMinutes = 480;
  snapshot.latestTimeMs = Date.parse('2026-10-02T23:30:00Z');
  snapshot.nextFeedTimeMs = Date.parse('2026-10-03T02:30:00Z');
  delete snapshot.latestTimeZoneOffsetMinutes;
  delete snapshot.nextFeedTimeZoneOffsetMinutes;
  assert.equal(WidgetStore.valid(snapshot), true);
  const data = WidgetStore.viewData(snapshot);
  assert.equal(data.latestTime, '10/03 07:30');
  assert.equal(data.nextReminder, '下次 10/03 10:30');
  assert.equal(data.latestDate, '10/03');
  assert.equal(data.latestClock, '07:30');
  assert.equal(data.compactReminderLabel, '下次喂奶 · 10/03');
  assert.equal(data.compactReminderValue, '10:30');
  snapshot.nextFeedTimeZoneOffsetMinutes = 841;
  assert.equal(WidgetStore.valid(snapshot), false);
});

test('compact card preserves the private placeholder and distinguishes reminder states', () => {
  const { WidgetStore, WidgetSnapshot, WidgetViewData } = widgetStore({}, async () => {});
  const placeholder = new WidgetViewData();
  assert.equal(placeholder.ready, false);
  assert.equal(placeholder.compactReminderLabel, '奶点记');
  assert.equal(placeholder.compactReminderValue, '打开应用');
  assert.equal(placeholder.latestDate, '');
  assert.equal(placeholder.latestClock, '暂无记录');

  const snapshot = new WidgetSnapshot();
  snapshot.dateKey = '2026-10-05';
  const empty = WidgetStore.viewData(snapshot);
  assert.equal(empty.ready, true);
  assert.equal(empty.compactReminderLabel, '奶点记');
  assert.equal(empty.compactReminderValue, '暂无记录');
  assert.equal(empty.latestDate, '');
  assert.equal(empty.latestClock, '暂无记录');

  snapshot.latestTimeMs = Date.parse('2026-10-05T01:30:00Z');
  const noReminder = WidgetStore.viewData(snapshot);
  assert.equal(noReminder.compactReminderLabel, '下次喂奶');
  assert.equal(noReminder.compactReminderValue, '暂无提醒');

  snapshot.reminderAcknowledged = true;
  snapshot.nextFeedTimeMs = Date.parse('2026-10-05T04:30:00Z');
  const stopped = WidgetStore.viewData(snapshot);
  assert.equal(stopped.compactReminderLabel, '本次提醒');
  assert.equal(stopped.compactReminderValue, '已停止');

  snapshot.latestTimeMs = null;
  const emptyWithStaleReminder = WidgetStore.viewData(snapshot);
  assert.equal(emptyWithStaleReminder.compactReminderLabel, '奶点记');
  assert.equal(emptyWithStaleReminder.compactReminderValue, '暂无记录');
});

for (const scenario of [
  { name: 'next local day and year', offset: 480,
    meal: '2026-12-31T15:30:00Z', mealDate: '12/31', mealClock: '23:30',
    next: '2026-12-31T17:30:00Z', nextDate: '01/01', nextClock: '01:30' },
  { name: 'previous local day and year', offset: -480,
    meal: '2027-01-01T06:30:00Z', mealDate: '12/31', mealClock: '22:30',
    next: '2027-01-01T07:30:00Z', nextDate: '12/31', nextClock: '23:30' },
]) {
  test(`compact date and clock stay paired across ${scenario.name}`, () => {
    const { WidgetStore, WidgetSnapshot } = widgetStore({}, async () => {});
    const snapshot = new WidgetSnapshot();
    snapshot.dateKey = '2027-01-01';
    snapshot.zoneOffsetMinutes = 0;
    snapshot.latestTimeMs = Date.parse(scenario.meal);
    snapshot.latestTimeZoneOffsetMinutes = scenario.offset;
    snapshot.nextFeedTimeMs = Date.parse(scenario.next);
    snapshot.nextFeedTimeZoneOffsetMinutes = scenario.offset;
    const data = WidgetStore.viewData(snapshot);
    assert.equal(data.latestDate, scenario.mealDate);
    assert.equal(data.latestClock, scenario.mealClock);
    assert.equal(data.compactReminderLabel, `下次喂奶 · ${scenario.nextDate}`);
    assert.equal(data.compactReminderValue, scenario.nextClock);
  });
}

test('native launch action remains available until one atomic Dart read', () => {
  const signals = [];
  const { FeedReminderHomeWidget } = load('../plugins/FeedReminderHomeWidget.ets', ['FeedReminderHomeWidget'], {
    MethodChannel: class {
      setMethodCallHandler() {}
      invokeMethod(method, payload) { signals.push([method, payload]); }
    },
  });
  const plugin = new FeedReminderHomeWidget();
  const consumed = [];
  const read = () => plugin.onMethodCall({ method: 'getPendingAction' }, {
    success: value => consumed.push(value),
  });
  FeedReminderHomeWidget.receiveWant({ parameters: { feedWidgetAction: 'record_feed' } }, false);
  plugin.onAttachedToEngine({ getBinaryMessenger() {} });
  read();
  read();
  assert.deepEqual(consumed, ['record_feed', null]);
  FeedReminderHomeWidget.receiveWant({ parameters: { feedWidgetAction: 'open_timer' } }, true);
  FeedReminderHomeWidget.receiveWant({ parameters: { feedWidgetAction: 'delete_history' } }, true);
  assert.deepEqual(signals, [['widgetAction', null]]);
  read();
  read();
  assert.deepEqual(consumed, ['record_feed', null, 'open_timer', null]);
});
