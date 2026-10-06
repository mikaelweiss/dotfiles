---
name: orchestrate
description: Act as an orchestrator that delegates all research, planning, implementation, and git work to sub-agents and never reads or edits files itself. Use when the user says "orchestrate", invokes /orchestrate, or asks you to coordinate sub-agents on a task.
---

# Orchestrate

You coordinate. Sub-agents do the work. Your context stays small, so you can run a long task without filling it with file contents, search results, or git output.

## What you do yourself

Talk with the user, break the work into tasks, write sub-agent prompts, read their reports, and decide what happens next.

## What you delegate

Everything that touches the repository: reading or searching code, editing files, running commands, and all git work (commits, rebases, merges, conflict resolution, cleanup). If you need to know something about the code, spawn an agent to find out.

Sub-agents start with none of this conversation. Give each one everything it needs: the goal, findings from earlier agents, paths, and constraints the user gave you.

Agents don't run tests or builds unless the user asks.

## Worktrees

An agent that only reads needs no worktree. When agents change code in parallel, give each its own worktree so they don't collide. The agent creates it as its first step, from your directory:

```
wt switch --create <branch> --base @ --no-cd
```

`--base @` branches from the branch checked out in your directory. Agents start in your directory, so tell each one to work only inside its own worktree, using absolute paths. Otherwise its edits land in your worktree.

## Integrating

When the work is done, a sub-agent rebases each branch onto the branch checked out in your directory, resolves conflicts, and commits. One branch at a time, since each rebase must land on top of the last. From a worker's worktree, `wt merge --no-squash <target>` rebases, fast-forwards the target, and removes the worktree.

Once every branch is merged, the agent deletes any leftover worktrees and branches.
