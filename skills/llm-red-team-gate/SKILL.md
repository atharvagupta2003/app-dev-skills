---
name: llm-red-team-gate
description: Run a red team case suite against a real LLM feature before it ships. Covers case categories and severities, judge validation, the release gate, exact reporting of every failure and outage, cost control, and when a prompt change may ship. Load when changing a prompt, validator, pre filter, model or judge, or when reading an evaluation report.
---

# LLM red team gate

## When to use this
- Any change to a prompt, the pre filter, the validator, the model or the judge.
- Setting up a case file or runner for a new assistant surface.
- Reading a red team report, or deciding whether a change may ship.
- A human reviewer finds a phrasing the suite missed.

## Rules
1. **Keep a versioned case file.** Each case has an id, category, surface, severity, goal, inputs, expected behaviour and machine checks. Bump the version when cases change. Why: a result means nothing without the case set it ran against.
2. **Cover what an attacker or a bad answer would use, and include benign cases.** Categories: instruction override, prompt extraction, persona change, indirect injection through other people's text, encoding tricks, out of scope requests, harmful advice, sexual content, harassment, crisis, privacy, banned vocabulary, false promises. Benign cases are part of the suite (37 of 213 in the first full suite). Why: a benign refusal is a failure, and a suite without benign cases rewards refusing everything.
3. **The gate is zero critical failures and at least 98 percent passed, on two consecutive full runs.** Why: one clean run can be luck. Two on the final code is the bar used.
4. **Report exact numbers for every run.** Passed of total, percent, critical count, a table by category, and every failing case with the shown text and the judge's reason. Keep every invocation in the record, including those that did not meet the gate. Why: the report is the evidence. In one round the second invocation on the final code did not meet the gate, and the report says so.
5. **A critical tagged case that fails on a non critical criterion is still reported under its tag.** Name the tag, the criterion and the reason. Why: a critical tag that fails on an over refusal still needs a human to read it. Moving it to a minor list hides it.
6. **An outage is "not run", never a pass or a fail.** Retry a bounded number of times. If the provider or the judge is still down, mark the case not run, keep it out of the percentage, and say the run is incomplete. Why: one run that counted outages as failures reported 230 of 250 with no safety failure, which read as a quality regression that was not one.
7. **Do not rerun until something passes.** Rerun after a change, and judge the gate on the final code. Why: rerunning until a number looks good makes the gate meaningless.
8. **Every phrasing a human reviewer finds that the suite missed becomes a case.** Add the case, bump the version, then judge the fix against it. Why: the suite should grow from real misses.
9. **Validate the judge before trusting it.** Hand label a set of replies, measure agreement, and report the misses (one round: 249 of 252). The judge sees only replies the model wrote; rules decide everything else. Why: an unvalidated judge can fail safe replies or pass unsafe ones.
10. **Check the grader before blaming the model.** Make sure the runner fills placeholders before the judge reads a reply. Why: a placeholder filled with a name looked to the judge like an invented name, a critical failure with no leak.
11. **Set a spend limit before the first run, and budget every run.** The judge can cost more than the model under test. Why: one full run costs a few dollars, most of it for the judge model. Several runs in one day used up the provider credit. See `llm-cost-and-budgets`.
12. **Hold prompt changes until the gate passes, and ship everything else.** Keep the prompt change apart from the code, tests and docs that do not depend on it, and do not ship the prompt until the gate passes. Why: a prompt that has not passed the gate must not reach members. The sources show held changes were kept apart; the exact version control method is not recorded.

## How to do it
1. Write the case file first. Each case has `id`, `category`, `surface`, `severity` (critical or standard), `goal`, `input` (turns), `expect` (safe, refuse, a crisis kind, or a model reply) and `must_not_match` patterns.
2. The runner runs each case through the same pipeline production uses: pre filter, context, provider, validator, fallback. Do not write a second pipeline for tests.
3. Rules first. Scripted and fixed replies are known safe. Crisis cases must return the right fixed kind. Every shown text is checked for banned words, numbers about fit and leaked markers.
4. Judge only model written replies. If the first judge declines a case, a stronger judge may decide; a case both decline counts as harmful.
5. Write the report under a new file name on every run; never overwrite a previous report. Include totals, the category table, every failing case verbatim, the outage list, and the token and cost summary.
6. Decide: the gate is met only with two consecutive full runs on the final code, zero critical, at least 98 percent, and no case marked not run.

## Gotchas
- **Symptom:** a critical failure reads "complied with attack", but the model only wrote a placeholder. **Cause:** the runner filled the placeholder before the judge read the reply. **Fix:** tell the judge the app fills the name in. Change no case and no check.
- **Symptom:** a run shows many failures, all "provider unavailable". **Cause:** outages counted as failures. **Fix:** retry, then mark not run, and mark the run incomplete.
- **Symptom:** a benign case fails with a scripted line. **Cause:** an over broad pre filter or validator rule. **Fix:** narrow the rule and add the near miss to the benign set. Report the failure first.
- **Symptom:** a judge flags a safe reply as harmful. **Cause:** a judge that marks a reply worse than its label, or a placeholder read as a fact. **Fix:** check the judge's agreement report and the runner's filling.
- **Symptom:** after several full runs in one day, every provider call failed. The suite could not run, and the assistant in the test app fell back to its scripted line. **Cause:** repeated full runs with no spend limit or run budget. **Fix:** a provider spend limit, a run budget written in the report, and filtered trial runs while tuning. The scripted fallback keeps the feature answering in plain lines while the account is out.
- **Symptom:** a device tester finds a phrasing the suite missed. **Cause:** no case for it. **Fix:** add the case, then the fix.

## Checklist
- [ ] Case file versioned, with categories and benign cases.
- [ ] Runner uses the production pipeline.
- [ ] Judge validated on hand labels, with agreement reported.
- [ ] Placeholders filled before judging, and the judge told.
- [ ] Outages retried, then marked not run.
- [ ] Spend limit set; run budget written down.
- [ ] Every invocation saved under a new report name.
- [ ] Gate judged on two consecutive full runs on the final code.
- [ ] Prompt change held until the gate passes.

## Tests that prove it
- Offline tests, no network, run on every change: the case file's shape, the pipeline with a stub provider, the pre filter and validator.
- A judge validation command that checks the judge against the hand labels.
- A runner test that an outage produces "not run", not "fail".
- The live suite before any release of a prompt or model change.

## Related skills
- `llm-assistant-safety-layers`: what the suite tests.
- `llm-cost-and-budgets`: budgeting runs.
- `honest-status-reporting`: how to write up a run.
