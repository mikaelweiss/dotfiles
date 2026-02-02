# Electron System

A scalable Electron architecture designed for AI leverage.

## Goals

1. **Constrained by design** - The wrong thing is hard to do
2. **Verifiable** - If it passes checks, you can trust it
3. **Skimmable** - Review structure, not every line
4. **AI-friendly** - Clear boundaries, explicit contracts

## Architecture Principles

### 1. Strict Process Separation
- Main process: system access, no UI logic
- Renderer process: UI only, no direct system access
- Preload: explicit bridge, nothing implicit

### 2. Typed IPC Contracts
Every IPC channel has a defined contract:
- What it accepts
- What it returns
- What errors it can produce

### 3. Small, Pure Modules
- Each module does one thing
- No hidden state
- Easy to test in isolation

### 4. Explicit State
- State is inspectable
- Changes are traceable
- No magic

## Structure

```
src/
├── main/           # Main process
│   ├── index.js    # Entry point
│   └── ipc/        # IPC handlers
├── renderer/       # Renderer process
│   ├── index.html
│   └── app/        # UI code
├── preload/        # Preload scripts
│   └── index.js
└── shared/         # Shared types/contracts
    └── ipc-contracts.js
```

## Building This System

This is a learning project. Build it incrementally:

1. Start with the minimal structure
2. Add one IPC contract with full typing
3. Add verification (tests that encode correctness)
4. Expand from there

The goal is not to finish - it's to learn what makes AI work well in this architecture.
