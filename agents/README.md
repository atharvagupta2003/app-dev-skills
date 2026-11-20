# Agents

Claude Code subagent definitions that match the skills in this repository. Each file is one agent: frontmatter (`name`, `description`, `tools`, `model`) followed by its system prompt. Each prompt names the skills it relies on, the inputs it expects in a brief, how it works, its hard rules and the exact report it returns.

## The agents

| Agent | Model | Tools | When to use |
|---|---|---|---|
| [mobile-ui-builder](mobile-ui-builder.md) | sonnet | Read, Edit, Write, Grep, Glob, Bash | Implement a screen, flow or component from an approved spec. |
| [backend-architect](backend-architect.md) | opus | Read, Edit, Write, Grep, Glob, Bash | Schema, migrations, row level security, Edge Functions, locks and races. |
| [mobile-qa](mobile-qa.md) | sonnet | Read, Edit, Write, Grep, Glob, Bash | Write and run unit, database and function tests and the gates; report honestly. |
| [device-tester](device-tester.md) | sonnet | Read, Write, Grep, Glob, Bash | Drive a release build on an emulator like a real user; return a pass, fail, not run table. |
| [independent-reviewer](independent-reviewer.md) | opus | Read, Grep, Glob | Review a diff before a deploy; failing scenarios and smallest fixes; never edits. |
| [context-curator](context-curator.md) | haiku | Read, Edit, Write, Grep, Glob | Keep specs, decision records, the session log and open questions in step with the code. |
| [skills-scribe](skills-scribe.md) | haiku | Read, Edit, Write, Grep, Glob | Record sanitised learnings into a skills repository. |

Tools follow least privilege. The reviewer has no Bash and no edit tools, so give it the diff as a patch file or in the brief. The scribe and the curator have no Bash and cannot commit.

## How an orchestrating session uses them

This follows `agent-orchestration-for-builds` and `milestone-loop-build-review-test`.

1. **Plan and review on the strongest model, execute on cheaper ones.** The main session writes the spec and the briefs, reviews diffs against the spec, runs or reads the gates and makes the commits. It writes no feature code. Design heavy work (schema, core rules, safety design) goes to the opus agents; well specified work goes to sonnet; mechanical and record keeping work goes to haiku.
2. **Write a complete brief for every delegation.** The agent sees only the brief. Fill in: goal, context (spec path, owner decisions quoted), already ruled out, files it owns, files it must not touch, rules that may not change, verify commands with the pass bar, and the report to return.
3. **One agent per worktree, one owner per file.** Two agents never own the same file, and only one installs packages at a time. When agents must run in parallel, give each its own git worktree. Never stash or reset while an agent runs.
4. **Hold files back by path.** Keep held paths in an array, stage the rest by explicit path, and check the committed revision in a clean worktree. Agents do not commit; the main session does, in focused commits.
5. **Ask for one final report.** Do not accept interim hand backs as done. Reports follow `honest-status-reporting`: verified, not run, inferred.
6. **Typical order for a milestone.** Spec (main session) then `backend-architect` and `mobile-ui-builder` on separate files, then `mobile-qa` for the gates, then `independent-reviewer` before any push that deploys, then `device-tester` on a release build, then `context-curator` and `skills-scribe` to record the result.

## Install

Copy the files into `.claude/agents/` in a project, or `~/.claude/agents/` for all projects. Adjust the `model` and `tools` lines to the models and tool servers you have.
