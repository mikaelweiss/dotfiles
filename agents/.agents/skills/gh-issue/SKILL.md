---
name: gh-issue
description: Create GitHub Issue. Creates a well-structured GitHub issue with duplicate detection, codebase analysis, and proper labeling. Use when the user wants to create an issue, file a bug, or request a feature.
user-invocable: true
disable-model-invocation: true
---

# Create GitHub Issue

You are creating a GitHub issue based on the user's description. Follow this process carefully.

## Input
The user has provided the following issue description:
$ARGUMENTS

## Process

### Step 1: Understand the Issue
Read the description carefully. If it's unclear or ambiguous, ask clarifying questions before proceeding.

### Step 2: Search for Duplicates and Related Issues
Use `gh` CLI to search for existing issues:
```bash
gh issue list --search "relevant keywords" --state all
```

Search for:
1. **Duplicates**: Issues that describe the same problem or would be solved by the same fix
2. **Related issues**: Issues that are connected to this problem

Search using relevant keywords from the description. Be thorough.

### Step 3: Search the Codebase
Use Grep and Glob to find:
- Related files that would need to be modified
- Similar existing features
- Relevant data models and classes

**IMPORTANT**: Never include actual code in the issue. Only include:
- File paths
- Class/model names
- Brief descriptions of what exists

### Step 4: Ask Clarifying Questions (if needed)
After searching, if you discover:
- The functionality already exists (ask if user is seeing different behavior)
- The description is ambiguous given what you found
- There are multiple ways to interpret the issue
- You need more context to write a good spec

Then ask the user for clarification before proceeding.

### Step 5: Handle Duplicates
If you find a duplicate issue:
1. Tell the user you found a duplicate and link to it
2. Add a comment to the existing issue with any new/additional information from the user's description:
   ```bash
   gh issue comment <issue-number> --body "Additional context: ..."
   ```
3. Report back to the user what you did
4. **Do not create a new issue**

### Step 6: Determine Issue Metadata
Figure out the following by analyzing the issue:

**Label** (choose appropriate labels for the repo):
- `bug` - Something is broken or not working as expected
- `enhancement` or `feature` - New functionality or improvement
- Other repo-specific labels as appropriate

Check available labels:
```bash
gh label list
```

### Step 7: Prepare the Issue Summary
Create a summary with ALL of the following sections:

**Title**: Clear, concise title (action-oriented)

**Description**:
- Brief explanation of the issue
- Reference any related issues using #<issue-number>
- List of related files (NO CODE)
- Relevant data models/classes involved

**Behaviors**:
- [What it does, bullet by bullet]
- [Each bullet = one clear behavior or requirement]
- [Include edge cases inline where relevant]

**Out of Scope** (if applicable):
- [Things explicitly not included]

**Implementation Notes**:
- [Technical approach]
- [Files that need to be modified]
- [Key considerations]

### Step 8: Create the Issue
Create the issue immediately:
```bash
gh issue create --title "Title here" --body "Body here" --label "label1,label2"
```

1. Create the issue using `gh issue create` with appropriate labels
2. Report back the issue URL to the user

## Important Guidelines

- **SIMPLE**: Issues should be laser-focused and as simple as possible
- **COMPLETE**: Include all relevant information, even if it makes the issue longer
- **NO CODE**: Never include code snippets in the issue, only file paths and class names
- **CLARIFY**: When in doubt, ask the user
- **AUTO-CREATE**: Create the issue immediately without asking for approval
