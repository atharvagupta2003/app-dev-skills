---
name: agent-orchestration-for-builds
description: How to run a software build with coding agents. One planning and reviewing agent, cheaper executors with complete briefs that say which rules may not change, one agent per working tree, holding changes back by path, health checks for long runs, and shell pitfalls. Load when splitting a build across subagents, writing a brief for an executor, or committing from a tree where agents have been working.
---

# Agent orchestration for builds

## When to use this
- Splitting a milestone across more than one agent.
- Writing a brief for an executor agent.
- Committing when other agents may have changed files.
- A long run has gone quiet, or a shell script did not do what it said.

## Rules
1. **One planner and reviewer; executors do the work.** The planner writes the spec and the briefs, reviews diffs and screenshots against the spec, runs the gates and makes the commits. It writes no feature code. Why: the planner's context is the scarce resource, and bulky tool output belongs with the executors.
2. **Match the executor to the work.** Use the top tier for design heavy or costly to get wrong work (schema design, the core rules, the assistant's safety design). Use a mid tier for well specified work (wiring, tests against a fixed interface, docs). Use the smallest tier for mechanical output (data files, boilerplate). Why: the owner asked for cheaper executors, and cheap executors infer intent worse, so their briefs must be fuller.
3. **Write every brief to stand alone.** State the goal, the constraints, what is already ruled out and why, the exact files the executor owns, the tests and gates it must run with their pass bar, what it must not touch, and what to return. Why: the executor sees only the brief.
4. **Two executors never own the same file, and one executor at a time installs packages.** Why: parallel edits to one file overwrite each other, and parallel installs corrupt the lockfile.
5. **Executors do not commit.** The planner stages by explicit path and commits in focused commits, one concern each. When two concerns share a file, group them into one commit so that every commit builds and passes on its own, rather than splitting the file into pieces that do not compile alone. Why: an executor's commit takes whatever else is in the tree, and a commit that does not build breaks bisecting for everyone after it. (The build's material records the grouping as the practice that worked. It was not measured against the alternative.)
6. **One agent per working tree.** When two agents must run at once, give each its own worktree. Why: two agents in one tree see each other's half finished edits. (Brief-sourced; not recorded in a log entry.)
7. **Never stash or reset while an agent is running.** Why: a reset erases another agent's work in progress. (Brief-sourced.)
8. **Check long runs on a schedule.** Use a timer or a monitor that reports progress, and treat silence as a question to answer. Why: a stuck agent looks like a slow one. (Brief-sourced; the method is a hypothesis.)
9. **Ask each agent for one final report, and do not accept interim hand backs as done.** The report states what changed, what was verified and how, what was not run, and what is open. Why: an agent handed back an interim report before its checks had finished. It was sent back with "do not hand back until every gate has finished". A partial report acted on as complete is how gaps reach a release.
10. **Relay the owner's decisions exactly.** Copy the owner's words into the spec and the brief, tagged with the decision number, and do not paraphrase. Why: a paraphrase drifts, and an executor builds the paraphrase.
11. **Hold changes back by path, and check the committed tree separately.** Keep the held paths in an array, commit the rest by explicit path, then check the committed revision in a clean worktree and run the gates there. Why: a held file must not reach a commit, and the working tree can hide a file that was never committed.
12. **Say in every brief whether the executor may change a rule.** Turning on a feature that is already built is the usual case. If a rule would have to change, the executor stops and reports both options. Why: an executor changed the basis of a time-based award while switching the feature on, because the brief named the goal but not the limits. The change was defensible, but it was a product decision. See [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md), rule 9.

## How to do it
Brief template. Fill every heading:

```
Goal: <one sentence: what done looks like>
Context: <spec path, and the owner decisions that apply, quoted>
Already ruled out: <approaches tried or rejected, and why>
You own: <exact file paths>
Do not touch: <paths, packages, migrations>
Rules that may not change: <list, or "none". If a rule must change, stop and report both options.>
Verify: <exact commands and the pass bar>
Return: <one final report with the sections above>
```

Holding paths back in zsh (an array, not a space separated string):

```sh
held=(docs/prompts/core.md src/prompts/core.ts)
# zsh: ${^held} expands each element as its own word, with no word splitting of the string
git restore --staged -- ${^held} 2>/dev/null
git diff --cached --name-only   # check the staged list before committing
```

## Gotchas
- **Symptom:** `git reset -- $paths`, meant to keep held files out of a commit, did nothing, and the held files were committed locally. The mistake was caught before pushing, and the commit was redone with an array. **Cause:** zsh does not word split an unquoted variable, so a list of several paths in one variable was passed as one word. **Fix:** keep the list in an array and expand it element by element (`${^held}` in zsh, or an explicit loop). Check the staged list afterwards.
- **Symptom:** a code formatter rewrote files across the repository. **Cause:** an agent ran it over the whole repository by mistake. **Fix:** restore the files, run formatters on the explicit list of changed files, and read the diff stat before committing.
- **Symptom:** background jobs and temporary folders were gone after the machine restarted, so the builds were restarted from scratch. **Cause:** background jobs and temporary folders do not survive a restart. **Fix:** write progress to a durable folder, and resume from the last checkpoint. Keep anything needed out of temporary folders.
- **Symptom:** an executor built the wrong thing. **Cause:** a vague brief, and a cheap executor filling the gaps. **Fix:** a complete brief with a concrete example, and planner review before commit.
- **Symptom:** two executors' changes conflict. **Cause:** two executors own one file. **Fix:** file ownership in each brief.
- **Symptom:** the main planner's context fills with test output. **Cause:** the planner ran the tests itself. **Fix:** delegate execution and read back the summary.

## Checklist
- [ ] Brief has goal, context, ruled out, owned files, not touched, rules that may not change, verify and return.
- [ ] No two executors own a file; one package installer at a time.
- [ ] One worktree per running agent.
- [ ] No stash or reset while an agent runs.
- [ ] One final report requested; interim reports not treated as done.
- [ ] Held paths in an array; commits by explicit path.
- [ ] Committed revision checked in a clean worktree.
- [ ] Diff and screenshots reviewed against the spec before "done".

## Tests that prove it
- A pre commit check that compares the staged list with the allowed list and fails on a held path.
- A script that checks out the committed revision into a fresh worktree and runs the gates there.
- A dry run of the path list in zsh with a path containing a space, to confirm the array form works.

## Related skills
- `milestone-loop-build-review-test`: the loop the planner runs.
- `honest-status-reporting`: how the final report is written.
- `spec-first-context-protocol`: the spec the brief quotes.
