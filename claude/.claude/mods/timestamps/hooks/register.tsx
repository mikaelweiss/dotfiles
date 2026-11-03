import { atom, memberOf, read } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

const sentAtRef = { plugin: 'timestamps', key: 'sentAt' } as const
const sentAt = atom(sentAtRef, 0)

const KEEP_MS = 90 * 24 * 60 * 60 * 1000
const MAX_STAMPS = 50_000
const BUCKET_PREFIX = 'stamps:'

type Bucket = Record<string, number>

// The store is one 4 MiB JSON blob, so stamps live in 256 buckets keyed by
// the message id's first two characters: drawing a row parses one bucket.
const bucketKey = (uuid: string) => BUCKET_PREFIX + uuid.slice(0, 2).toLowerCase()

const readBucket = async ($: EngineInterface, key: string): Promise<Bucket> => {
  const value = await $.store.get(key)
  return value && typeof value === 'object' ? (value as Bucket) : {}
}

// Appends arrive concurrently and each bucket write is read-modify-write.
let pendingWrite: Promise<void> = Promise.resolve()

const persist = ($: EngineInterface, uuid: string, at: number) => {
  pendingWrite = pendingWrite.then(async () => {
    const key = bucketKey(uuid)
    await $.store.set(key, { ...(await readBucket($, key)), [uuid]: at })
  }).catch(() => {})
  return pendingWrite
}

const prune = async ($: EngineInterface) => {
  const now = await $.clock.now()
  const keys = (await $.store.keys()).filter(key => key.startsWith(BUCKET_PREFIX))
  const buckets = await Promise.all(keys.map(async key => [key, await readBucket($, key)] as const))
  const kept = new Set(
    buckets
      .flatMap(([, bucket]) => Object.entries(bucket))
      .filter(([, at]) => typeof at === 'number' && now - at < KEEP_MS)
      .sort(([, a], [, b]) => b - a)
      .slice(0, MAX_STAMPS)
      .map(([uuid]) => uuid),
  )
  for (const [key, bucket] of buckets) {
    const entries = Object.entries(bucket).filter(([uuid]) => kept.has(uuid))
    if (entries.length === Object.keys(bucket).length) continue
    if (entries.length === 0) await $.store.delete(key)
    else await $.store.set(key, Object.fromEntries(entries))
  }
}

const stampOf = async ($: EngineInterface, e: Parameters<typeof memberOf>[1]) => {
  const live = await read($, memberOf(sentAt, e))
  if (live) return live
  const stored = (await readBucket($, bucketKey(e.requestId)))[e.requestId]
  return typeof stored === 'number' ? stored : 0
}

const formatTime = (ms: number) =>
  new Date(ms).toLocaleTimeString([], {
    hour: 'numeric',
    minute: '2-digit',
    second: '2-digit',
  })

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    void prune($).catch(() => {})
    return next(e)
  })

  on('session.append', async ($, e, next) => {
    const stored = await next(e)
    const isConversation = e.door === 'prompt' || e.door === 'response'
    if (isConversation && e.agentId === undefined && !('deny' in stored)) {
      const at = await $.clock.now()
      await $.state.set({ ...sentAtRef, id: stored.uuid }, at)
      void persist($, stored.uuid, at)
    }

    return stored
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const at = await stampOf($, e)
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
    const at = await stampOf($, e)
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
