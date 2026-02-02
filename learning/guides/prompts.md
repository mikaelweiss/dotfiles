# Prompting for Code

A practical guide to writing effective prompts for AI-assisted coding.

**Philosophy:** Complexity kills. Always ask: *"What's the simplest thing that could possibly work?"*

---

## Core Principles

### 1. Simplicity Wins

The goal isn't impressive code—it's working code with minimal complexity. Prompt for the simplest solution.

```
❌ "Create a robust, scalable caching layer with TTL, LRU eviction, and Redis fallback"
✅ "Add in-memory caching for the API response. Simple object, no expiration needed yet."
```

If you need more later, add it later.

### 2. Clarity Over Cleverness

Most prompt failures come from ambiguity, not model limitations. A clear, simple prompt beats a clever one.

```
❌ "Make the auth better"
✅ "Add JWT token refresh when the access token expires"
```

### 3. One Task, One Prompt

LLMs do best with focused prompts. Implement one function, fix one bug, add one feature at a time.

```
❌ "Add authentication, set up the database, and create the API endpoints"
✅ "Add JWT authentication middleware to the Express app"
```

### 4. Design for Autonomy

Write prompts that let agents run to completion without intervention. This means:
- Clear success criteria
- Explicit boundaries
- No ambiguous decision points

```
❌ "Improve the error handling" (what does "improve" mean?)
✅ "Wrap database calls in try/catch. On error, log the error and return { success: false, error: message }."
```

### 5. Make Wrong Things Hard

Constrain the solution space so bad outcomes are difficult. Include what NOT to do.

```
Add form validation for the email field.
- Use the existing validateEmail helper from utils/
- Don't add new dependencies
- Don't modify the form's submit handler
```

### 6. Build In Verification

Prompt for outputs you can verify without reading every line.

```
Add the feature, then:
- Add a test that verifies the happy path
- Log the result to console so I can confirm it works
```

---

## Prompt Structure

### The Basic Formula

```
[Context] + [Task] + [Constraints]
```

**Context**: What exists, what you're working with
**Task**: What you want done
**Constraints**: Boundaries, preferences, requirements

### Example

```
Context:   "In the Express app at src/server.ts"
Task:      "add a health check endpoint"
Constraints: "at GET /health that returns { status: 'ok' }"
```

Combined:
> In the Express app at src/server.ts, add a health check endpoint at GET /health that returns { status: 'ok' }

---

## The Prompt Elements

Use these building blocks to construct prompts. Not all are needed for every prompt.

| Element | Purpose | Example |
|---------|---------|---------|
| **Role** | Set expertise level | "As a security expert..." |
| **Context** | Situate the task | "In a React 18 app using TypeScript..." |
| **Task** | What to do | "Create a custom hook for..." |
| **Input** | What to work with | "Given this API response: {...}" |
| **Output** | Expected format | "Return only the function, no explanation" |
| **Constraints** | Boundaries | "Without external dependencies" |
| **Examples** | Show, don't tell | "Like this: [example]" |

### Combining Elements

Simple task (Context + Task):
> In main.py, add logging for all database queries.

Medium task (Context + Task + Constraints):
> In the React component at src/Button.tsx, add a loading state. Use the existing Spinner component. Don't change the prop interface.

Complex task (Full structure):
> You're modifying a Node.js CLI tool. The tool parses markdown files and outputs JSON. Add a --watch flag that re-runs when files change. Use chokidar for file watching. Follow the existing flag pattern in src/cli.ts. Output should match the current JSON schema.

---

## Techniques That Work

### 1. XML Tags for Structure

Claude responds well to XML tags. Use them to separate sections clearly.

```
<context>
Express.js API with PostgreSQL
Authentication uses JWT
</context>

<task>
Add rate limiting to the /api/login endpoint
</task>

<constraints>
- 5 attempts per minute per IP
- Return 429 with retry-after header
- Don't add new dependencies
</constraints>
```

### 2. Few-Shot Examples

Show the pattern you want. One example is often enough.

```
Convert these function names to the project's naming convention.

Example:
Input: getUserData
Output: get_user_data

Now convert:
Input: fetchAllPosts
Output:
```

### 3. Chain of Thought

For complex problems, ask for reasoning before the answer.

```
Debug this function. First, explain what the function is trying to do.
Then identify potential issues. Finally, provide the fix.

function dedupe(arr) {
  return arr.filter((item, index) => arr.indexOf(item) === index);
}
```

### 4. Role-Based Framing

Set the expertise level for the response.

```
As a senior Python developer reviewing a junior's code, identify
issues in this function and explain why they matter:
```

### 5. Constraints as Guardrails

Explicitly state what you don't want.

```
Refactor this function to be more readable.
- Don't change the function signature
- Don't add new dependencies
- Keep the same behavior for edge cases
```

---

## Coding-Specific Patterns

### Bug Fixing

```
This function should [expected behavior] but instead [actual behavior].

[paste code]

[paste error message or incorrect output]
```

### Code Review

```
Review this code for:
1. Bugs or logic errors
2. Security issues
3. Performance problems

[paste code]
```

### Implementation

```
In [file path], implement [feature].

Requirements:
- [Requirement 1]
- [Requirement 2]

Follow the patterns in [reference file] for style.
```

### Refactoring

```
Refactor this [function/class/module] to [goal].

Current code:
[paste code]

Constraints:
- Maintain the same public interface
- Keep all existing tests passing
```

### Explaining Code

```
Explain what this code does, focusing on:
1. The main purpose
2. Key algorithms or patterns used
3. Any non-obvious behavior

[paste code]
```

---

## Common Mistakes

### Being Too Vague

```
❌ "Fix the bug"
✅ "The login function returns undefined when the password is correct.
   It should return the user object."
```

### Overloading the Prompt

```
❌ "Build a full authentication system with login, signup, password
   reset, email verification, OAuth, and admin panel"
✅ Start with: "Add email/password login to the Express app"
   Then: "Add signup with email verification"
   Then: "Add password reset flow"
```

### No Context About Existing Code

```
❌ "Add a delete button"
✅ "In src/components/UserCard.tsx, add a delete button that calls
   the existing deleteUser mutation from src/api/users.ts"
```

### Assuming the AI Knows Your Codebase

```
❌ "Use our standard error handling"
✅ "Use the AppError class from src/utils/errors.ts with appropriate
   error codes from the ErrorCode enum"
```

### Not Specifying Output Format

```
❌ "Write tests for this function"
✅ "Write Jest tests for this function. Include tests for:
   - Happy path with valid input
   - Edge case with empty array
   - Error case with null input"
```

---

## Quick Reference

### Prompt Checklist

Before sending a prompt, check:

- [ ] Is this the simplest version of the task?
- [ ] Is the task focused (one thing at a time)?
- [ ] Is there enough context (files, frameworks, existing patterns)?
- [ ] Are constraints explicit (what NOT to do)?
- [ ] Can this be misinterpreted? (if yes, add specificity)
- [ ] How will I verify it worked?
- [ ] Could an agent run this without asking questions?

### Templates

**Quick Implementation:**
```
In [file], add [feature]. [One sentence of detail].
```

**Detailed Implementation:**
```
<context>
[Tech stack, relevant files, existing patterns]
</context>

<task>
[What to implement]
</task>

<requirements>
- [Requirement 1]
- [Requirement 2]
</requirements>

<constraints>
- [What to avoid]
</constraints>
```

**Debug:**
```
[Brief description of the bug]

Expected: [what should happen]
Actual: [what happens instead]

Code:
[relevant code]

Error:
[error message if any]
```

**Code Review:**
```
Review this code. Focus on [specific concerns or "general quality"].
Flag only issues you're confident about.

[code]
```

---

## Prompting for Autonomous Agents

When writing prompts for agents that run without supervision, the stakes are higher. Your prompt is the only guidance they get.

### The Autonomy Test

Before sending a prompt to an autonomous agent, ask:

1. **Can this be misinterpreted?** If yes, add specificity.
2. **Are there decision points?** Make the decision in the prompt, or provide clear criteria.
3. **How will I know it worked?** Include verification steps.
4. **What could go wrong?** Add constraints to prevent it.

### Encode Your Philosophy

Agents should think like you. Include your principles:

```
<philosophy>
- Prefer simple solutions over clever ones
- Don't add dependencies unless absolutely necessary
- If unsure, do less rather than more
</philosophy>

<task>
Add user preferences storage
</task>
```

### Constrained Architecture

Design prompts where the wrong thing is hard to do:

```
Add a new API endpoint following these constraints:
- Must use the existing route handler pattern in src/routes/
- Must use the existing error format from src/utils/errors.ts
- Must have a corresponding test file
- No direct database access—use existing repository methods only
```

The agent can't easily deviate because you've boxed in the solution.

### Verifiable Outputs

Prompt for results you can check quickly:

```
Implement the feature. When done:
1. Run the tests and ensure they pass
2. Add a curl command I can run to verify the endpoint works
3. List the files you modified
```

Now you can verify in 30 seconds instead of reading all the code.

### Parallel-Safe Prompts

If multiple agents might work on the same codebase:

```
Add the notification feature.
- Work only in src/notifications/
- Don't modify any files outside that directory
- Create new files rather than modifying existing shared utilities
```

---

## Going Deeper

### Iteration

Your first prompt often won't be perfect. Refine:

1. Try the prompt
2. Note what was wrong or missing in the output
3. Add specificity where it went wrong
4. Repeat

### Context Windows

Modern models have large context windows. Use them:

- Paste relevant code files
- Include example outputs
- Add documentation snippets

But don't dump everything—include what's *relevant*.

### When to Break Tasks Down

Break into multiple prompts when:
- The task touches multiple files for different reasons
- You need to make decisions between steps
- The output of step 1 informs step 2

Keep as single prompt when:
- It's a cohesive change
- All parts are interdependent
- The task is well-defined

---

## The Simplicity Check

Before finalizing any prompt, ask:

> "What's the simplest thing that could possibly work?"

If your prompt is asking for more than that, trim it down.

---

## Sources

- [Anthropic Prompting Best Practices](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [XML Tags for Structured Prompts](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags)
- [Prompt Engineering Guide](https://www.promptingguide.ai/)
- [The Prompt Engineering Playbook for Programmers](https://addyo.substack.com/p/the-prompt-engineering-playbook-for)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
