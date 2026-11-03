import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

const SENT_AT = Date.UTC(2026, 10, 3, 21, 4, 5)

const USER_ROW = {
  plugin: 'timestamps',
  component: 'UserMessage',
  requestId: 'm1',
  props: { text: 'hi', origin: { kind: 'composer' }, isExpanded: false },
} as const

const REPLY_ROW = {
  plugin: 'timestamps',
  component: 'AssistantMessage',
  requestId: 'm2',
  props: { text: 'hello', isFirstOfReply: true },
} as const

const drawEngineRow = (on: On) =>
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text>engine row</Text>
  })

test('a stamped prompt and reply show their time under the row', async ($, on) => {
  drawEngineRow(on)
  on('state.get', () => ({ value: { value: SENT_AT, version: 1 } }))
  const expected = new Date(SENT_AT).toLocaleTimeString([], {
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  })

  for (const row of [USER_ROW, REPLY_ROW]) {
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ ...row, surface })
      expect(await ui.find({ type: 'Text', text: /engine row/ })).toBeDefined()
      const stamp = await ui.find({ type: 'Text', text: /\d:\d\d:\d\d/ })
      expect(stamp?.text.trim()).toBe(expected)
      await ui.unmount()
    }
  }
})

test('a row with no stamp is drawn as the engine draws it', async ($, on) => {
  drawEngineRow(on)

  const ui = await $.ui.mount({ ...USER_ROW, surface: 'terminal' })

  expect(await ui.find({ type: 'Text', text: /engine row/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\d:\d\d/ })).toBeUndefined()
  await ui.unmount()
})
