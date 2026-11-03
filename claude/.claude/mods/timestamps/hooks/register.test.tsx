import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const NOW = Date.UTC(2026, 10, 3, 21, 4, 5)
const DAY = 24 * 60 * 60 * 1000

const userRow = (requestId: string) =>
  ({
    plugin: 'timestamps',
    component: 'UserMessage',
    requestId,
    props: { text: 'hi', origin: { kind: 'composer' }, isExpanded: false },
  }) as const

const replyRow = (requestId: string) =>
  ({
    plugin: 'timestamps',
    component: 'AssistantMessage',
    requestId,
    props: { text: 'hello', isFirstOfReply: true },
  }) as const

const timeOf = (ms: number) =>
  new Date(ms).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })

const drawEngineRow = (on: On) =>
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine row</Text>
  })

test('a sent prompt and reply show their time and are saved', async ($, on) => {
  drawEngineRow(on)
  const clock = mock.clock(on, { now: NOW })
  const saved: Record<string, unknown> = {}
  for (const key of ['stamps:ab', 'stamps:cd']) {
    on('store.set', { key }, (_, e, next) => {
      saved[e.key] = e.value
      return next(e)
    })
  }
  mock.store(on)
  mock.session(on)

  await $.session.append({
    door: 'prompt',
    origin: { kind: 'composer' },
    uuid: 'ab-prompt',
    message: { type: 'user', role: 'user', content: [{ type: 'text', text: 'hi' }] },
  })
  await $.session.append({
    door: 'response',
    origin: { kind: 'model', model: 'test' },
    uuid: 'cd-reply',
    message: { type: 'assistant', role: 'assistant', content: [{ type: 'text', text: 'hello' }] },
  })
  await clock.settle()

  for (const row of [userRow('ab-prompt'), replyRow('cd-reply')]) {
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ ...row, surface })
      expect(await ui.find({ type: 'Text', text: /engine row/ })).toBeDefined()
      expect((await ui.find({ type: 'Text', text: /\d:\d\d:\d\d/ }))?.text.trim()).toBe(timeOf(NOW))
      await ui.unmount()
    }
  }
  expect(saved).toEqual({ 'stamps:ab': { 'ab-prompt': NOW }, 'stamps:cd': { 'cd-reply': NOW } })
})

test('a resumed session shows the saved time', async ($, on) => {
  drawEngineRow(on)
  mock.store(on, { 'stamps:ef': { 'ef-old': NOW - DAY } })

  const ui = await $.ui.mount({ ...userRow('ef-old'), surface: 'terminal' })

  expect((await ui.find({ type: 'Text', text: /\d:\d\d:\d\d/ }))?.text.trim()).toBe(timeOf(NOW - DAY))
  await ui.unmount()
})

test('session start drops stamps older than 90 days', async ($, on) => {
  drawEngineRow(on)
  const clock = mock.clock(on, { now: NOW })
  mock.store(on, {
    'stamps:aa': { 'aa-stale': NOW - 91 * DAY, 'aa-fresh': NOW - DAY },
    'stamps:bb': { 'bb-stale': NOW - 100 * DAY },
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await clock.settle()

  for (const [id, shown] of [['aa-stale', false], ['aa-fresh', true], ['bb-stale', false]] as const) {
    const ui = await $.ui.mount({ ...userRow(id), surface: 'terminal' })
    const stamp = await ui.find({ type: 'Text', text: /\d:\d\d:\d\d/ })
    expect(stamp !== undefined).toBe(shown)
    await ui.unmount()
  }
})

test('a row with no stamp is drawn as the engine draws it', async ($, on) => {
  drawEngineRow(on)
  mock.store(on)

  const ui = await $.ui.mount({ ...userRow('zz-none'), surface: 'terminal' })

  expect(await ui.find({ type: 'Text', text: /engine row/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\d:\d\d/ })).toBeUndefined()
  await ui.unmount()
})
