# Authoring guide

How skills in this repository are written. Every contributor, human or agent, follows this.

## What a skill is

A skill is a folder under `skills/` that teaches a coding agent, or a developer, how to do one kind of work well. It is built from real experience shipping a production mobile app, not from general advice.

```
skills/<skill-name>/
  SKILL.md          required: the guide itself
  references/       optional: longer material the guide links to
  examples/         optional: small, complete, sanitised code examples
```

Folder names are lower case with words joined by a single dash, for example `supabase-rls` or `expo-app-start`.

## SKILL.md format

Start with frontmatter, then the sections below in this order. Leave out a section only if it would be empty.

```markdown
---
name: <same as the folder name>
description: <one or two sentences: what this covers and when an agent should load it. Name the trigger words.>
---

# <Title>

## When to use this
Two to five bullets. Concrete situations.

## Rules
Numbered. Each rule is one instruction a reader can follow, then one line on why. The why comes from something that actually went wrong or went right.

## How to do it
The steps or patterns, with short code where it helps.

## Gotchas
Each one as: what you see, the real cause, the fix. These are the most valuable part. Be specific.

## Checklist
Tick boxes a reader runs before calling the work done.

## Tests that prove it
What to test and how, so the rule cannot silently break later.

## Related skills
Links to other skills in this repository.
```

## Quality bar

1. **Specific over general.** "Keyboard height on edge to edge Android leaves out the navigation bar, so position from the keyboard's top edge" is a learning. "Handle the keyboard properly" is not.
2. **Verified only.** Record what happened or was tested. Mark anything unconfirmed as a hypothesis.
3. **The rule, then the reason.** A reader should be able to judge an edge case from the reason.
4. **Short.** Aim for a SKILL.md a person can read in five minutes. Move long material to `references/`.
5. **No duplication.** One fact lives in one skill. Other skills link to it.
6. **Examples compile in principle.** Small, complete, and with invented names.

## Sanitising rules (this repository will be public)

Never include:

- Secrets of any kind: keys, tokens, passwords, signing material, connection strings.
- Identifiers of private systems: project ids or refs, bucket names, account ids, private URLs, bundle or package ids of the source app.
- People: names, email addresses, phone numbers, account handles, test account names.
- The source product's business rules, pricing, copy, content, roadmap or internal decisions. Describe it only as "a mobile app with accounts, matching, chat, media and an AI assistant" when context is needed.
- File paths from the author's machine.

Always:

- Rename tables, functions, screens and features in examples to neutral ones (`members`, `threads`, `items`, `HomeScreen`).
- Replace real numbers that are product settings with obviously invented ones.
- Keep vendor and tool names (Expo, React Native, Supabase, Postgres, Jest, Maestro, Deno) since those are what readers search for.

If you are unsure whether something identifies the source product or a person, leave it out.

## Writing style

Plain English. Short sentences. Second person ("do this"). No em dashes. Say what to do before saying what not to do.

## The inbox

`_inbox/` is for raw, unsorted notes: what happened, cause, fix, general rule. Skills are distilled from them. The raw log (`_inbox/learnings.md`) is gitignored and never committed, because raw notes carry the details this repository must not publish. See [_inbox/README.md](_inbox/README.md).
