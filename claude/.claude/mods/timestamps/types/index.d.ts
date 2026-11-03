export type SentAt = number

declare module 'claude-code' {
  interface PluginState {
    timestamps: { sentAt: StateFamily<SentAt> }
  }
}
