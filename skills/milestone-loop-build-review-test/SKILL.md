---
name: milestone-loop-build-review-test
description: The loop used for each build milestone. Spec, build with tests, gates, independent review, fixes, focused commits, a push behind a switch, a hosted deploy, a release build tested on devices with two accounts, defects fed into the next round, and documents updated. Load when planning or running a milestone, or deciding what a review or device stage must cover.
---

# Milestone loop: build, review, test

## When to use this
- Starting a milestone or a round of fixes.
- Deciding what a review pass or device test must cover.
- Planning a release of a feature behind a switch.

## Rules
1. **Spec first, with acceptance criteria and open decisions tagged.** Why: every later stage checks against the spec.
2. **Build and test in the same change.** Unit tests for rules, database tests for each rule that touches data, edge tests for each endpoint, and the device flow written down. Why: tests written later describe the code rather than the spec.
3. **Run every gate and write down the counts.** Typecheck, lint, all suites, schema diff. Why: the counts show that nothing was skipped.
4. **Review by someone who did not build it, against the spec.** The reviewer reads the diff, the spec and the test output, and runs the paths they changed. Why: an author is blind to their own gaps.
5. **Fix in focused commits, then rerun the gates.** One concern per commit. Why: a review of a fix stays small.
6. **Push behind a switch.** The feature is off in production and on only for a test project or a tester group. Why: the code can be tested for real without members seeing it.
7. **Deploy to the hosted test project and check the rows after each flow.** Check the rows the flow should write, and the ones it should not. Why: a feature can look right on screen and write the wrong rows.
8. **Test a release build on devices with two accounts.** Any flow involving two people is incomplete until both sides have seen it live. Why: one device cannot show the other side's view or the live updates.
9. **Feed defects into the next round.** Each defect gets a severity, and a test or a red team case where possible. Why: the same defect must not come back.
10. **Update the documents in the same round.** Spec status, decision records, session log, open questions, the testing guide. Why: the next person reads documents, not memory.

## How to do it

| Stage | Output | Gate to move on |
|---|---|---|
| 1. Spec | Rules, acceptance criteria, tagged open decisions | Owner decisions recorded or tagged |
| 2. Build | Code, unit, database, edge and red team tests | A test for each rule |
| 3. Gates | Counts for every suite | All green, counts recorded |
| 4. Review | Findings against the spec | Findings fixed or logged |
| 5. Commit | Focused commits | Committed tree checked in a clean worktree |
| 6. Push behind switch | Feature off in production | Switch scope named |
| 7. Hosted deploy | Migrations applied, row checks | Rows checked after each flow |
| 8. Device round | Release build, two accounts, screenshots | Each flow seen on both sides |
| 9. Next round | Defect list, new cases | Severity assigned |
| 10. Documents | Spec, records, log, open questions | Updated in the same round |

## What each stage caught
Examples from the source project, in the order the stages ran:
- **Red team (stages 2 and 4):** an assistant offered a workaround after a block. That was a critical case the rules did not cover, and no unit test had caught it.
- **Independent review (stage 4):** a block rule matched everyday words; a skipped answer leaked into history; an old key could overwrite an edit; a view guard was missing. None were in the author's tests.
- **Device round on a release build (stage 8):** a safety reply used up a message allowance; an empty conversation stayed in the list; the same item could be reported twice; the keyboard covered edit sheets; the splash drew twice on cold start; a feature was unreachable in one mode.
- **Two account checks (stage 8):** a live update reached one side only; a copy promise ("final count") was made before it was true.
- **Not done at the time of the sources:** a real user pass over several days with two people, and a physical device test. Say so in the status.

## Gotchas
- **Symptom:** a feature passes every test and fails on a device. **Cause:** tests ran on one account and one device. **Fix:** the two account round in stage 8.
- **Symptom:** a fix creates a new over refusal elsewhere. **Cause:** the rule was fixed without its near miss list. **Fix:** add the near misses before the fix. See `llm-assistant-safety-layers`.
- **Symptom:** the review and the device round find the same defects. **Cause:** the reviewer read the code but did not run the flow. **Fix:** the reviewer runs the flows they changed.
- **Symptom:** a feature is switched on straight after release. **Cause:** "pushed" and "switched on" were treated as one step. **Fix:** keep them separate in the status. See `honest-status-reporting`.

## Checklist
- [ ] Spec with tagged decisions.
- [ ] Tests written with the code.
- [ ] Gates run; counts recorded.
- [ ] Independent review against the spec.
- [ ] Focused commits; committed tree checked.
- [ ] Feature behind a switch.
- [ ] Rows checked after each hosted flow.
- [ ] Release build round with two accounts.
- [ ] Defects with severity, fed into the next round.
- [ ] Documents updated.

## Tests that prove it
- One test per rule, named after the rule.
- A device round script: which account does what, on which screen, and what the other account must see.
- A red team run for any prompt, validator or model change (see `llm-red-team-gate`).

## Related skills
- `spec-first-context-protocol`: the spec and the documents.
- `llm-red-team-gate`: the red team stage.
- `honest-status-reporting`: how each stage is reported.
- `agent-orchestration-for-builds`: who does each stage.
