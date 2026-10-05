// Runs the actual non-UI ArkTS channel flow with platform fakes.
// Node type stripping does not replace ArkTS compilation or device verification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');
const { test } = require('node:test');

function createPlugin(vibrator, foreground = true, now = () => 1000) {
  const channels = [];
  const source = fs.readFileSync(path.resolve(__dirname,
    '../../ohos/entry/src/main/ets/plugins/FeedReminderHaptics.ets'), 'utf8')
    .replace(/^import[^;]+;\r?\n/gm, '')
    .replace(/^export default /gm, '');
  const context = vm.createContext({
    vibrator,
    Date: { now },
    MethodChannel: class {
      constructor(_, name) { this.name = name; channels.push(this); }
      setMethodCallHandler(handler) { this.handler = handler; }
    },
  });
  vm.runInContext(`${stripTypeScriptTypes(source, { mode: 'strip' })}\n` +
    'this.plugin = new FeedReminderHaptics();', context);
  const plugin = context.plugin;
  const binding = { getBinaryMessenger() { return {}; } };
  plugin.onAttachedToEngine(binding);
  if (foreground) plugin.setForeground(true);
  return { plugin, binding, channels };
}

function invoke(plugin, method) {
  return new Promise((resolve, reject) => plugin.onMethodCall({ method }, {
    success: resolve,
    error: reject,
    notImplemented() { resolve('notImplemented'); },
  }));
}

const plain = value => JSON.parse(JSON.stringify(value));

test('registers the haptics channel and removes its handler on detach', () => {
  const { plugin, binding, channels } = createPlugin({});
  assert.equal(channels[0].name, 'feed_reminder/haptics');
  assert.equal(channels[0].handler, plugin);
  plugin.onDetachedFromEngine(binding);
  assert.equal(channels[0].handler, null);
});

test('uses one restrained touch preset per action and caches support by effect', async () => {
  const queries = [];
  const pulses = [];
  const { plugin } = createPlugin({
    async isSupportEffect(effect) { queries.push(effect); return true; },
    async startVibration(effect, attributes) { pulses.push(plain({ effect, attributes })); },
  });
  for (const action of ['selection', 'success', 'warning']) {
    assert.equal(await invoke(plugin, action), null);
  }
  assert.deepEqual(queries, ['haptic.effect.soft', 'haptic.effect.hard']);
  assert.equal(pulses.length, 3);
  for (const pulse of pulses) {
    assert.equal(pulse.effect.type, 'preset');
    assert.equal(pulse.effect.count, 1);
    assert.ok(pulse.effect.intensity > 0 && pulse.effect.intensity <= 55);
    assert.deepEqual(pulse.attributes, { usage: 'touch' });
  }
  assert.ok(pulses[0].effect.intensity < pulses[1].effect.intensity);
});

test('unsupported presets fall back once to short touch durations', async () => {
  const pulses = [];
  let queries = 0;
  const { plugin } = createPlugin({
    async isSupportEffect() { queries++; return false; },
    async startVibration(effect, attributes) { pulses.push(plain({ effect, attributes })); },
  });
  for (const action of ['selection', 'success', 'warning', 'selection']) {
    assert.equal(await invoke(plugin, action), null);
  }
  assert.equal(queries, 2);
  assert.deepEqual(pulses.map(p => p.effect), [8, 20, 35, 8].map(duration => ({ type: 'time', duration })));
  assert.ok(pulses.every(p => p.attributes.usage === 'touch'));
});

test('a capability query failure completes the channel without vibrating', async () => {
  let pulses = 0;
  const { plugin } = createPlugin({
    async isSupportEffect() { throw Error('service unavailable'); },
    async startVibration() { pulses++; },
  });
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(await invoke(plugin, 'success'), null);
  assert.equal(pulses, 0);
});

test('a rejected capability query retries only on the next action and caches recovery', async () => {
  let queries = 0;
  const pulses = [];
  const { plugin } = createPlugin({
    async isSupportEffect() {
      queries++;
      if (queries === 1) throw Error('service temporarily unavailable');
      return true;
    },
    async startVibration(effect, attributes) { pulses.push(plain({ effect, attributes })); },
  });
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(queries, 1);
  assert.equal(pulses.length, 0);

  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(queries, 2);
  assert.equal(pulses.length, 1);
  assert.equal(pulses[0].effect.type, 'preset');
  assert.deepEqual(pulses[0].attributes, { usage: 'touch' });

  assert.equal(await invoke(plugin, 'success'), null);
  assert.equal(queries, 2);
  assert.equal(pulses.length, 2);
});

test('synchronous permission failures never escape or trigger fallback', async () => {
  let pulses = 0;
  const { plugin } = createPlugin({
    isSupportEffect() { throw Error('permission denied'); },
    async startVibration() { pulses++; },
  });
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(pulses, 0);
});

test('a rejected touch pulse completes once, does not retry, and permits later actions', async () => {
  let pulses = 0;
  const { plugin } = createPlugin({
    async isSupportEffect() { return true; },
    async startVibration() {
      pulses++;
      if (pulses === 1) throw Error('touch feedback disabled');
    },
  });
  assert.equal(await invoke(plugin, 'warning'), null);
  assert.equal(pulses, 1);
  assert.equal(await invoke(plugin, 'success'), null);
  assert.equal(pulses, 2);
});

test('fallback device failure also completes without a second pulse', async () => {
  let pulses = 0;
  const { plugin } = createPlugin({
    async isSupportEffect() { return false; },
    async startVibration() { pulses++; throw Error('no vibrator'); },
  });
  assert.equal(await invoke(plugin, 'success'), null);
  assert.equal(pulses, 1);
});

test('overlapping actions are dropped instead of queued', async () => {
  let release;
  let pulses = 0;
  const { plugin } = createPlugin({
    isSupportEffect() { return new Promise(resolve => { release = resolve; }); },
    async startVibration() { pulses++; },
  });
  const first = invoke(plugin, 'selection');
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(await invoke(plugin, 'success'), null);
  release(true);
  assert.equal(await first, null);
  assert.equal(pulses, 1);
});

test('slow capability queries drop stale feedback while allowing the next gesture', async () => {
  let release;
  let pulses = 0;
  let queries = 0;
  let now = 1000;
  const { plugin } = createPlugin({
    isSupportEffect() {
      queries++;
      return new Promise(resolve => { release = resolve; });
    },
    async startVibration() { pulses++; },
  }, true, () => now);
  const stale = invoke(plugin, 'selection');
  now += 200;
  release(true);
  assert.equal(await stale, null);
  assert.equal(pulses, 0);
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(pulses, 1);
  assert.equal(queries, 1);
});

test('detaching cancels pending feedback and reattaching probes capabilities afresh', async () => {
  let release;
  let pulses = 0;
  let queries = 0;
  const { plugin, binding } = createPlugin({
    isSupportEffect() {
      queries++;
      if (queries === 1) return new Promise(resolve => { release = resolve; });
      return Promise.resolve(true);
    },
    async startVibration() { pulses++; },
  });
  const pending = invoke(plugin, 'selection');
  plugin.onDetachedFromEngine(binding);
  plugin.onAttachedToEngine(binding);
  plugin.setForeground(true);
  release(true);
  assert.equal(await pending, null);
  assert.equal(pulses, 0);
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(queries, 2);
  assert.equal(pulses, 1);
});

test('an old rejected query cannot clear a successful cache after reattachment', async () => {
  let rejectOld;
  let queries = 0;
  let pulses = 0;
  const { plugin, binding } = createPlugin({
    isSupportEffect() {
      queries++;
      if (queries === 1) return new Promise((_, reject) => { rejectOld = reject; });
      return Promise.resolve(true);
    },
    async startVibration() { pulses++; },
  });
  const oldAction = invoke(plugin, 'selection');
  plugin.onDetachedFromEngine(binding);
  plugin.onAttachedToEngine(binding);
  plugin.setForeground(true);

  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(queries, 2);
  assert.equal(pulses, 1);

  rejectOld(Error('old engine query failed'));
  assert.equal(await oldAction, null);
  assert.equal(pulses, 1);
  assert.equal(await invoke(plugin, 'success'), null);
  assert.equal(queries, 2);
  assert.equal(pulses, 2);
});

test('engine attachment alone does not allow vibration before entering the foreground', async () => {
  let queries = 0;
  let pulses = 0;
  const { plugin } = createPlugin({
    async isSupportEffect() { queries++; return true; },
    async startVibration() { pulses++; },
  }, false);
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(queries, 0);
  plugin.setForeground(true);
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(pulses, 1);
});

test('backgrounding cancels pending feedback without replaying it on return', async () => {
  let release;
  let pulses = 0;
  const { plugin } = createPlugin({
    isSupportEffect() { return new Promise(resolve => { release = resolve; }); },
    async startVibration() { pulses++; },
  });
  const pending = invoke(plugin, 'selection');
  plugin.setForeground(false);
  assert.equal(await invoke(plugin, 'success'), null);
  plugin.setForeground(true);
  release(true);
  assert.equal(await pending, null);
  assert.equal(pulses, 0);
  assert.equal(await invoke(plugin, 'selection'), null);
  assert.equal(pulses, 1);
});

test('unknown methods and detached channels do not access the vibrator', async () => {
  const { plugin, binding } = createPlugin({
    isSupportEffect() { throw Error('must not be called'); },
  });
  assert.equal(await invoke(plugin, 'unknown'), 'notImplemented');
  plugin.onDetachedFromEngine(binding);
  assert.equal(await invoke(plugin, 'selection'), null);
});
