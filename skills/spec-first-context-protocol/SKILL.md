---
name: spec-first-context-protocol
description: Keep a project's decisions and status in the repository. A feature spec written before the code, numbered decision records, a dated session log, one open questions list with proposed values, product numbers as settings rows, and "as built" notes after each milestone. Load at the start of a feature, when recording a decision, or when updating project context after a change.
---

# Spec first context protocol

## When to use this
- Starting any feature, before code.
- Making an architectural choice someone will later ask about.
- Finishing a milestone, a review round or a device test.
- Preparing questions for the product owner.

## Rules
1. **Read the feature spec before building; write it first if none exists.** Why: work built from memory of a chat cannot be checked against anything.
2. **Write acceptance criteria as testable rules.** Each rule maps to at least one test. Why: a rule with no test is a wish.
3. **Record each architectural choice as a numbered decision record.** Use a short template: status (Proposed, Accepted, Superseded), date, context, decision, consequences. For a change made in review, add an addendum rather than rewriting the record. Why: the reason for a choice is what gets lost first.
4. **Keep one dated session log.** Each entry says what was built, names the migrations or schema changes, gives the tests and their counts, and lists what was not done. Why: the next session starts from the log, not from memory.
5. **Keep one open questions list.** It holds decisions waiting on the owner, features kept dark because a value is missing, things not yet verified on a real device, and items for before launch. Why: scattered questions get lost.
6. **Give each owner question a recommendation.** Keep the question short, list the options, and state the recommendation and why. Why: the owner can then answer in one word.
7. **Mark proposed values as proposed, and keep them as rows.** Why: a proposed value nobody ratified quietly becomes the product.
8. **Never guess a pending value.** An absent row keeps the feature off. Why: a guessed default ships a decision nobody made.
9. **Keep product numbers as settings rows.** Caps, prices, timings and limits live in a table, so a change needs no release. Why: owners change numbers after launch, and a release for each change is slow.
10. **Record the owner's decisions verbatim, with their number.** Quote the rule the owner gave, and mark the decision decided. Why: a paraphrase drifts.
11. **Write an "as built" note after each milestone.** Say what differs from the plan and what was not done. Why: a plan goes stale the day it is built.
12. **Describe behaviour in specs, not prompts or copy.** Specs hold rules, threat models and acceptance criteria. Prompts and user copy live in the code, under review. Why: a spec that quotes prompts gets copied into other places.

## How to do it
Layout used by the source project (adapt the names):

```
context/
  specs/<feature>.md          rules, acceptance criteria, "as built" sections
  decisions/ADR-0001-...md    one decision each; numbers never reused
  session-log.md              dated entries, newest last
  open-questions.md           one list: owner decisions, dark features, device checks
```

Decision record:

```
---
status: Accepted
date: 2026-01-01
---
# ADR-0007: <the decision as one sentence>
## Context
## Decision
## Consequences
```

## Gotchas
- **Symptom:** a feature shipped with a number nobody confirmed. **Cause:** the spec gave the number as a default with no tag. **Fix:** tag it "proposed", make it a row, and list it under decisions to confirm.
- **Symptom:** the code differs from the spec. **Cause:** a deviation during the build. **Fix:** record it in the decision record with the choice made and why, under a "deviations, safest choice" heading. In one case two lines conflicted; the safer reading was chosen and written down.
- **Symptom:** an owner question sits unanswered for weeks. **Cause:** the question was long and had no recommendation. **Fix:** one line, the options, and a recommendation.
- **Symptom:** the session log does not show what is still missing. **Cause:** entries list only what was done. **Fix:** end every entry with "not done".
- **Symptom:** a spec's "decisions to confirm" list is never ticked. **Cause:** no one owns the list. **Fix:** list the open items in the open questions file, with an owner.

## Checklist
- [ ] Spec read, or written, before the code.
- [ ] Each rule has a test.
- [ ] A decision record for each architectural choice, numbered and dated.
- [ ] Session log entry with migrations, test counts and "not done".
- [ ] Open questions list updated; new owner questions have recommendations.
- [ ] Proposed values tagged and kept as rows.
- [ ] "As built" note after the milestone.

## Tests that prove it
- One test per spec rule, named after the rule. See `pgtap-database-testing` for database rules.
- A check that every settings key the code reads exists as a row in the migrations, and that a missing row fails closed.
- A check that decision record numbers are unique.

## Related skills
- `milestone-loop-build-review-test`: when the spec and "as built" notes are updated.
- `agent-orchestration-for-builds`: the spec is the source of the brief.
- `llm-cost-and-budgets`: numbers for model features.
