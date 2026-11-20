---
name: honest-status-reporting
description: How to report the state of a build, a test run or a safety check so the reader can tell what was verified, what was not run and what is only inferred. Covers gates with counts, device checks, red team numbers, count differences checked against the working tree, "safe to push" versus "safe to switch on", defect lists and correcting earlier statements. Load before writing any status, handover, release note or "done" message.
---

# Honest status reporting

## When to use this
- Ending a task, a milestone, a session or a review round.
- Reporting a test, a gate or a red team run.
- Saying a build, feature or release is ready.
- Correcting something said earlier that proved wrong.

## Rules
1. **Split every claim into verified, not run, or inferred.** "Verified: X, by Y." "Not run: Z, because W." "Inferred: V, from reading the code." Why: readers act differently on each.
2. **Name every gate with its count.** For example: "unit 1821, database 4260, edge 149, schema diff clean." Why: "all green" hides what ran.
3. **Do not call a build ready until it has been launched and the feature used.** Run the real app on a simulator, emulator or device, or say it was not launched. Why: a typecheck shows the code compiles, not that a member can use the feature.
4. **Report "safe to push" and "safe to switch on" separately.** Safe to push: merged behind a switch, gates green. Safe to switch on: device tested through the real flow, and the owner has said yes. Why: code can be safe to merge and still unsafe for members.
5. **Give measured numbers with their sample and their limits.** Count, percent, sample size, and what the sample cannot show. Why: 98 percent of 265 cases is a narrower claim than it sounds.
6. **Report red team and evaluation results exactly.** Write "not met" when the bar was not met, name the run and the reason, and do not describe a run more favourably than its numbers. Why: one round had a clean pair of runs followed by a second invocation on the same code that did not meet the gate, and the report says so.
7. **List defects by severity, with exact steps.** For each: severity, steps to reproduce, observed result, expected result, and status. Why: "some issues on Android" cannot be triaged.
8. **Say what was not exercised.** A test that skipped the nudge, or the second action, is a gap, and it goes in the report. Why: passing the tested path reads as passing the feature.
9. **Correct earlier statements plainly.** Write "I said X. That was wrong. The state is Y." Do not quietly edit the earlier text. Why: a silent edit leaves the reader with the wrong claim.
10. **Say when a live check was blocked.** A blocked check is not a passed check. Why: "the live runs are blocked because the account has no credit" is a fact the owner needs now.
11. **Prove a fix for an intermittent failure with repeated full runs, and report the count.** Write the failure rate before the fix and the number of runs after it, for example "4 of 8 before, 0 of 10 after". Do not call it fixed after one clean run. Why: a first fix for a Jest exit warning was declared done after one clean run, and had to be retracted.

## How to do it
Report skeleton:

```
State: <one line: built, tested on X, not yet on a device>
Verified (how): <gates with counts; device or simulator, build, flow>
Not run (why): <each item with its reason>
Inferred: <each item, marked as inferred>
Safe to push: <yes or no, and why>
Safe to switch on: <yes or no, and what is still missing>
Defects: <severity, steps, observed, expected, status>
Corrections: <earlier statements that have changed>
```

Example wording (illustrative):
- "Met on two consecutive full runs: 265 of 265, then 264 of 265. Zero critical in both."
- "Not met. Run 2 passed 230 of 250 (92.0 percent) with zero critical. In that run, provider outages were counted as failures. The runner now reports outages as not run."
- "Not tested: the nudge flow on Android, physical devices, and real push delivery."
- "Correction: I said the two account test passed. It covered the first flow only. The second flow has not been run."

## Gotchas
- **Symptom:** a release is called done after a typecheck. **Cause:** the app was never launched. **Fix:** launch it, use the feature, and name the build.
- **Symptom:** a red team run looks good, but one failure is tagged critical. **Cause:** a critical case failing on a non critical criterion was moved to "minor". **Fix:** report the tag, the criterion and the reason.
- **Symptom:** a later reader believes the gate passed when it did not. **Cause:** the report kept only the best run. **Fix:** keep every run in the table.
- **Symptom:** "done" is reported while a device flow is untested. **Cause:** the device test was planned, not run. **Fix:** list it under "not run".
- **Symptom:** a count in a report does not match the suite. **Cause:** the numbers were typed by hand. **Fix:** copy the numbers from the runner's output.
- **Symptom:** an intermittent fault is reported as fixed, and it comes back in the next few runs. **Cause:** one clean run was treated as proof, and the fault appears in only some runs. **Fix:** run the full suite repeatedly, record each result, and state the rate before and after (rule 11). Then write a correction if the first claim was wrong.
- **Symptom:** local and CI test counts differ, for example by 15 tests, and the first guess is a platform difference. **Cause:** the local tree held test files that were never committed, so CI never ran them. **Fix:** check `git status` and the committed tree first. Compare the two file lists before you explain a difference by the platform.
- **Symptom:** a run is blamed on the code, but it was a crash in the runtime or the machine. **Cause:** no one read the OS crash reports first. **Fix:** read them before you report the cause (see [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md)).

## Checklist
- [ ] Every claim is verified, not run, or inferred.
- [ ] Each gate named with its count.
- [ ] Build launched, or the report says it was not.
- [ ] "Safe to push" and "safe to switch on" given separately.
- [ ] Measured numbers have their sample size.
- [ ] Every run in the record, including failed ones.
- [ ] Defects listed by severity, with steps.
- [ ] Earlier wrong statements corrected in the report.
- [ ] A count difference between two runs is checked against the working tree before it is explained.

## Tests that prove it
- The gate report is generated from the runner's output, not typed.
- A CI step that fails when a suite's summary has no count.

## Related skills
- `llm-red-team-gate`: the rule that outages are not run, and the numbers.
- `milestone-loop-build-review-test`: where status is written in the loop.
- `agent-orchestration-for-builds`: the executor's final report.
