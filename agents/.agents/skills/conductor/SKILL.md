---
name: conductor
description: Build, configure, and troubleshoot Conductor workspaces, repository scripts, conductor.json, managed settings, files to copy, MCP, agent controls, and review workflows. Use when helping someone set up or operate Conductor.
license: Proprietary
compatibility: Conductor is a macOS app for running Claude Code and Codex agents locally in isolated git worktree workspaces.
---

<!-- conductor-skill-source-sha256: c684c125234673cf71cbd090b5c494ac295b2a1880f88fb1a906319a7e06bcdd -->

# Conductor

Conductor is a Mac app for running multiple coding agents in parallel. Each workspace is a separate git worktree and branch tied to a repository.

Use this skill to help users configure, operate, or troubleshoot Conductor. Keep guidance concise, operational, and grounded in documented behavior.

## When to use

Use this skill when helping with:

-   Creating or operating Conductor repositories, workspaces, branches, and git worktrees.
-   Writing or debugging `conductor.json`.
-   Writing setup, remote setup, run, or archive scripts.
-   Configuring files to copy into new workspaces.
-   Configuring app settings, repository settings, managed settings, providers, or privacy controls.
-   Controlling agent behavior, plan mode, fast mode, model reasoning, MCP, slash commands, todos, checkpoints, or instruction files.
-   Reviewing, testing, merging, or troubleshooting agent work in Conductor.

Do not claim support for Windows or Linux. Conductor is a macOS app.

## Core model

-   Conductor runs Claude Code and Codex agents.
-   Conductor runs agents locally on the user's Mac unless the documented cloud workspace path is explicitly involved.
-   Each repository has a root directory.
-   Each workspace is a git worktree with its own branch.
-   Workspaces are isolated development environments for agent work.
-   Agents run with the user's local permissions unless the user configures stricter controls.
-   Workspaces include a gitignored `.context` directory for shared agent context.
-   The repo root can contain a checked-in `conductor.json` file for shared repository settings.
-   Users can also configure personal repository settings in the Conductor app.

Useful docs:

-   https://conductor.build/docs/concepts/workspaces-and-branches
-   https://conductor.build/docs/concepts/workflow
-   https://conductor.build/docs/concepts/parallel-agents

## Workspace workflow

When explaining workspace behavior, keep the branch and worktree model explicit:

-   A repository is the top-level project Conductor knows about.
-   A workspace is a separate git worktree for that repository.
-   Each workspace has its own branch.
-   Agents work inside the workspace directory, not the main repository directory.
-   The `.context` directory is gitignored and can hold shared context for agents.

When a user is configuring a project for Conductor, verify that workspace commands can run from the workspace directory. If a project assumes it is running from the repository root, suggest using `CONDUCTOR_ROOT_PATH` or Spotlight testing.

## Repository configuration

Conductor supports shared repository configuration in `conductor.json`.

`conductor.json` facts:

-   Path: `conductor.json`
-   Scope: repository root.
-   Commit this file when teammates should share the configuration.
-   Personal Repository Settings on the user's machine override `conductor.json`.
-   To use the shared file, clear personal script overrides.

Supported `conductor.json` fields:

| Field                   | Type                                | Purpose                                                                   |
| ----------------------- | ----------------------------------- | ------------------------------------------------------------------------- |
| `scripts.setup`         | `string`                            | Command to run when Conductor creates a workspace.                        |
| `scripts.remoteSetup`   | `string`                            | Command to use instead of `scripts.setup` for remote or cloud workspaces. |
| `scripts.run`           | `string`                            | Command to run when the user clicks the Run button.                       |
| `scripts.archive`       | `string`                            | Command to run before Conductor archives a workspace.                     |
| `runScriptMode`         | `"concurrent"` or `"nonconcurrent"` | Controls whether more than one run script can run at the same time.       |
| `enterpriseDataPrivacy` | `boolean`                           | Disables features that require external AI providers.                     |

Example:

```json
{
    "scripts": {
        "setup": "pnpm install",
        "run": "pnpm dev",
        "archive": "./script/workspace-archive.sh"
    },
    "runScriptMode": "concurrent"
}
```

Docs:

-   https://conductor.build/docs/reference/conductor-json
-   https://conductor.build/docs/reference/scripts/share-with-teammates

## Scripts

Setup, run, and archive scripts run from the workspace directory.

Script facts:

-   Conductor uses non-interactive shells for scripts.
-   Although Conductor captures the login shell environment, most commands including setup and run scripts use `zsh`.
-   Use `CONDUCTOR_ROOT_PATH` when a workspace script needs a file from the repository root.
-   Use `CONDUCTOR_PORT` when multiple workspaces need separate local server ports.
-   Conductor allocates ten ports to each workspace: `CONDUCTOR_PORT` through `CONDUCTOR_PORT+9`.
-   Use `nonconcurrent` run script mode when a project depends on a single fixed port, single local database, or another shared resource.
-   When a run script starts multiple processes, keep them in the same process group with a tool such as `concurrently` instead of backgrounding commands with `&`.
-   When Conductor stops a process, it sends `SIGHUP`, waits up to 200ms, then sends `SIGKILL` if the process is still running.
-   Use Spotlight testing when a project cannot run cleanly from a workspace directory and needs to execute from the repository root.

Environment variables:

| Variable                   | Description                                                  |
| -------------------------- | ------------------------------------------------------------ |
| `CONDUCTOR_WORKSPACE_NAME` | Workspace name.                                              |
| `CONDUCTOR_WORKSPACE_PATH` | Workspace path.                                              |
| `CONDUCTOR_ROOT_PATH`      | Path to the repository root directory.                       |
| `CONDUCTOR_DEFAULT_BRANCH` | Name of the default branch, usually `main`.                  |
| `CONDUCTOR_PORT`           | First port in a range of 10 ports assigned to the workspace. |

Docs:

-   https://conductor.build/docs/reference/scripts
-   https://conductor.build/docs/reference/scripts/setup
-   https://conductor.build/docs/reference/scripts/run
-   https://conductor.build/docs/reference/scripts/spotlight-testing
-   https://conductor.build/docs/reference/shells
-   https://conductor.build/docs/reference/environment-variables

## Settings

Conductor has app settings, repository settings, and provisional managed settings.

Managed settings:

-   Path: `~/.conductor/settings.json`
-   Schema: https://conductor.build/schemas/settings.json
-   Status: managed settings are provisional.
-   Managed values override local database settings.
-   Managed values disable matching controls in Settings.
-   Managed values are used when Conductor launches agents.

Supported managed settings fields:

| Field                   | Type      | Purpose                                                                 |
| ----------------------- | --------- | ----------------------------------------------------------------------- |
| `enterpriseDataPrivacy` | `boolean` | Enable enterprise data privacy.                                         |
| `claudeExecutablePath`  | `string`  | Override the Claude Code executable path.                               |
| `defaultModel`          | `string`  | Set the default model. Supported values are defined by the JSON Schema. |

When helping with settings, distinguish:

-   Shared repository settings in `conductor.json`.
-   Personal repository settings in the Conductor app.
-   Managed settings in `~/.conductor/settings.json`.

Docs:

-   https://conductor.build/docs/reference/settings
-   https://conductor.build/docs/guides/providers
-   https://conductor.build/docs/reference/privacy
-   https://conductor.build/docs/reference/security-and-permissions
-   https://conductor.build/schemas/settings.json

## Agent behavior

Use documented controls when guiding users through agent behavior:

-   Plan mode.
-   Fast mode.
-   Model reasoning controls.
-   Codex personality.
-   Checkpoints.
-   MCP.
-   Slash commands.
-   Todos.
-   Instruction files.

Do not invent unsupported agent settings, providers, APIs, or behavior. If a user needs exact options, send them to the relevant reference page.

Docs:

-   https://conductor.build/docs/reference/agent-behavior
-   https://conductor.build/docs/concepts/agent-modes
-   https://conductor.build/docs/reference/checkpoints
-   https://conductor.build/docs/reference/mcp
-   https://conductor.build/docs/reference/slash-commands
-   https://conductor.build/docs/reference/todos

## Review and merge

When helping users review agent work, cover the operational path:

-   Inspect changes in the diff viewer.
-   Run checks from Conductor when configured.
-   Review pull request state, comments, CI status, and deployments.
-   Confirm the workspace is ready before merging.
-   Keep review guidance focused on testing the changes and resolving comments.

Docs:

-   https://conductor.build/docs/guides/review-and-merge
-   https://conductor.build/docs/reference/diff-viewer
-   https://conductor.build/docs/reference/checks

## Troubleshooting

Start with the smallest concrete failure mode:

-   If scripts fail, confirm they run from the workspace directory.
-   If shell behavior differs from the user's terminal, account for non-interactive shells and `zsh`.
-   If multiple workspaces conflict, check fixed ports, shared databases, and `runScriptMode`.
-   If local servers conflict, use `CONDUCTOR_PORT`.
-   If a script needs repo-root files, use `CONDUCTOR_ROOT_PATH`.
-   If a project cannot run from a workspace directory, use Spotlight testing.
-   If privacy or permissions are involved, distinguish local agent permissions from configured stricter controls.
-   If workspace nesting or path issues appear, check the troubleshooting and FAQ docs.

Docs:

-   https://conductor.build/docs/faq
-   https://conductor.build/docs/troubleshooting/issues
-   https://conductor.build/docs/reference/shells

## References

Core docs:

-   Workspaces and branches: https://conductor.build/docs/concepts/workspaces-and-branches
-   Workflow: https://conductor.build/docs/concepts/workflow
-   Parallel agents: https://conductor.build/docs/concepts/parallel-agents
-   `conductor.json`: https://conductor.build/docs/reference/conductor-json
-   Scripts: https://conductor.build/docs/reference/scripts
-   Setup scripts: https://conductor.build/docs/reference/scripts/setup
-   Run scripts: https://conductor.build/docs/reference/scripts/run
-   Spotlight testing: https://conductor.build/docs/reference/scripts/spotlight-testing
-   Files to copy: https://conductor.build/docs/reference/files-to-copy
-   Shells: https://conductor.build/docs/reference/shells
-   Environment variables: https://conductor.build/docs/reference/environment-variables
-   Settings: https://conductor.build/docs/reference/settings
-   Providers: https://conductor.build/docs/guides/providers
-   Privacy: https://conductor.build/docs/reference/privacy
-   Security and permissions: https://conductor.build/docs/reference/security-and-permissions
-   Managed settings schema: https://conductor.build/schemas/settings.json
-   Agent behavior: https://conductor.build/docs/reference/agent-behavior
-   Agent modes: https://conductor.build/docs/concepts/agent-modes
-   Checkpoints: https://conductor.build/docs/reference/checkpoints
-   MCP: https://conductor.build/docs/reference/mcp
-   Slash commands: https://conductor.build/docs/reference/slash-commands
-   Todos: https://conductor.build/docs/reference/todos
-   Review and merge: https://conductor.build/docs/guides/review-and-merge
-   Diff viewer: https://conductor.build/docs/reference/diff-viewer
-   Checks: https://conductor.build/docs/reference/checks
-   FAQ: https://conductor.build/docs/faq
-   Troubleshooting: https://conductor.build/docs/troubleshooting/issues
