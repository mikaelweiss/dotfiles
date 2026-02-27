---
name: skill-creator
description: Create new Claude Code skills through guided conversation. Use when the user wants to create a skill, write a skill, make a skill, or set up custom instructions for a specific domain or workflow.
user-invocable: true
---

# Skill Creator

Guide users through creating effective Claude Code skills via structured questioning. Never assume — always ask.

## Process

### Phase 1: Discovery

Ask questions to understand:

1. **Purpose** — What domain or task does this skill cover?
2. **Philosophy** — What principles or opinions should it encode?
3. **Anti-patterns** — What should it explicitly avoid?
4. **Triggers** — When should this skill auto-activate?
5. **Scope** — Project-specific (`.claude/skills/`) or global (`~/.claude/skills/`)?

Ask 3-5 questions at a time. Don't overwhelm. Iterate until the vision is clear.

### Phase 2: Research

If the skill relates to external documentation or tools:
- Use Context7 to find relevant library IDs
- Fetch any reference documentation needed
- Identify patterns from similar skills if they exist

### Phase 3: Write the Skill

Create the skill following this structure:

```
[scope]/skills/[skill-name]/
└── SKILL.md
```

## SKILL.md Format

```markdown
---
name: skill-name
description: Clear description of what this skill does and when to use it. Include trigger phrases users might say.
---

# Skill Title

[Opening statement — what is this skill's purpose and philosophy?]

## Core Principles

[The opinions and guidelines this skill encodes]

## Anti-Patterns

[What to explicitly avoid]

## Implementation Details

[Domain-specific guidance, patterns, tools, references]

## External References

[Library IDs for Context7, links to docs, etc. — fetch as needed, not upfront]
```

## Writing Effective Descriptions

The `description` field is critical — Claude uses it to decide when to apply the skill.

**Bad (too vague):**
```yaml
description: Helps with design
```

**Good (specific triggers):**
```yaml
description: Design philosophy and UI guidelines. Use when building, modifying, or reviewing any user interface element — views, components, layouts, animations, or interactions.
```

Include:
- What the skill does
- Specific actions it covers
- Natural phrases users might say
- When it should activate

## Best Practices

### Content
- Keep SKILL.md under 500 lines
- Use progressive disclosure — reference separate files for detailed docs
- Write in imperative form ("Use semantic colors" not "You should use semantic colors")
- Be opinionated — skills encode preferences, not just information

### Structure
- `name` must be lowercase with hyphens, match directory name
- `description` max 1024 chars — make every word count
- Group related guidance under clear headings
- End with external references (Context7 IDs, docs links)

### Optional Frontmatter Fields

```yaml
allowed-tools: Read, Grep, Glob          # Restrict available tools
model: claude-sonnet-4-20250514          # Force specific model
context: fork                             # Run in isolated sub-agent
user-invocable: true                      # Show in slash command menu
```

## Skill Locations

| Path | Scope |
|------|-------|
| `~/.claude/skills/` | Personal — all projects |
| `.claude/skills/` | Project — shared with team |

## Questions to Always Ask

1. What should this skill be called?
2. What's the core purpose in one sentence?
3. What opinions or principles should it enforce?
4. What should it explicitly avoid?
5. When should it activate? (trigger phrases)
6. Where should it live? (project vs global)
7. Are there external docs it should reference?
8. Any domain-specific terminology or patterns?

Adapt questions based on the domain. A design skill needs aesthetic philosophy. A testing skill needs methodology preferences. A deployment skill needs infrastructure context.

## After Creation

- Verify the skill triggers correctly by asking about its domain
- Iterate on the description if it activates too broadly or too narrowly
- Add reference files as needed for detailed guidance
