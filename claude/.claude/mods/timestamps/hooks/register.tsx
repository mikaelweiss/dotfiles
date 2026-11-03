import { atom, memberOf, read } from 'claude-code'
import type { Register } from 'claude-code'

const sentAtRef = { plugin: 'timestamps', key: 'sentAt' } as const
const sentAt = atom(sentAtRef, 0)

const formatTime = (ms: number) =>
  new Date(ms).toLocaleTimeString([], {
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  })

export const register: Register = on => {
  on('session.append', async ($, e, next) => {
    const stored = await next(e)
    const isConversation = e.door === 'prompt' || e.door === 'response'
    if (isConversation && e.agentId === undefined && !('deny' in stored)) {
      await $.state.set({ ...sentAtRef, id: stored.uuid }, await $.clock.now())
    }

    return stored
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const at = await read($, memberOf(sentAt, e))
    if (!at) return next(e)
    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {await next(e)}
        <Text dimColor>  {formatTime(at)}</Text>
      </Box>
    )
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const at = await read($, memberOf(sentAt, e))
    if (!at || e.props.isSummary) return next(e)
    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="column">
        {await next(e)}
        <Text dimColor>  {formatTime(at)}</Text>
      </Box>
    )
  })
}
