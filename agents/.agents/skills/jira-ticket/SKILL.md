---
name: jira-ticket
description: Investigate a bug or feature and file a Jira ticket concrete enough for a human or an agent to finish without asking. Use when the user asks to create, file, or write a Jira ticket, or invokes /jira-ticket.
user-invocable: true
---

# File a Jira ticket

## Investigate

Read the code before writing anything. Find the root cause or the exact place the change lands, and the `file:line` behind each claim. Look for an existing pattern elsewhere in the codebase that solves the same problem, and name it.

## Settle scope

Ask the user only what the code cannot answer, as a numbered list, each with your recommendation. Typical questions: adjacent cases that share the root cause, and edge cases that might belong in a separate ticket. Anything the user rules out goes in the ticket as out of scope.

## Write the ticket

Title: a short command that states the result, for example "Show the invoice total in the customer's currency".

Description, in Markdown, in this order:

1. **Problem**: what happens today, who it hurts, and numbered steps to reproduce. End with the cause in one or two sentences.
2. **Goal**: what should happen instead.
3. **Done when**: a `- [ ]` checklist of acceptance criteria. Each one is something a test or a reviewer can confirm or refute.
4. **Pointers**: the files, endpoints, or screens the work touches with paths, the pattern to follow, constraints and gotchas the implementer must respect, and an "Out of scope" line for anything deliberately excluded.

Leave out wishes that belong in a different ticket. When a request covers several independent changes, write one ticket per change and link them.

## File it

Use the Atlassian MCP. Call `getAccessibleAtlassianResources` once for the `cloudId`, then `createJiraIssue` with the project key, issue type (Bug or Story), title, and the Markdown description. For SureStake work the project is `SS`.

Reply with the ticket key and link. No AI attribution in the ticket.
