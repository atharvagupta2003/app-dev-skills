---
name: independent-review-before-deploy
description: How to get an independent review of a change before it reaches a server that real testers use, especially when every push to the main branch deploys automatically. Covers what to give a fresh reviewer (code and intent, not your conclusion), asking whether a push is safe, what reviews actually caught in one project, requiring a failing scenario and the smallest fix for each finding, reviewers who do not edit, and keeping held changes out of commits with a clean worktree check. Load before pushing a change that auto deploys, or when asked to review.
---

# Independent review before deploy

## When to use this
- A push to the main branch deploys to a server that testers or real users hit.
- A change touches shared code, a database rule, a deletion or purge, a limit, or anything that more than one feature depends on.
- You are about to say "this is safe" and have not tested the path a stranger would take.
- You have changes you are holding back, and need them out of the commit.

## Rules
1. **Give the reviewer the code, the intent and the test output. Do not give your conclusion.** Say what the change should do, which files changed, and how it was tested. Leave out "I think this is safe".
   Why: a reviewer handed your conclusion tends to confirm it. The reviews that caught the most were the ones that worked from the code and the intent.
2. **Ask "is it safe to push?" for any change that auto deploys.** Name the server, the people who use it, and what breaks for them if the change is wrong.
   Why: in one project every push to the main branch deployed to the hosted test project used by testers. A bug pushed there reached testers without a second look.
3. **Require each finding to come with a concrete failing scenario and the smallest fix.** A finding without a scenario is an opinion. A finding without a fix is a complaint.
   Why: a scenario can be tested, and the smallest fix keeps the review from becoming a rewrite.
4. **Reviewers do not edit the code.** The author makes the change, runs the gates again, and asks for a second look at the changed part.
   Why: an edited review is not a review. The reviewer's job is to find what the author missed, and an edit by the reviewer is unreviewed code.
5. **Keep held changes out of the commit, and prove the committed tree builds without them.** Check the committed state in a separate worktree, run the gates there, and never stash while another person or agent is working in the same tree.
   Why: a stash can take away another agent's work mid task, and a commit that only builds with a held change is broken for everyone who pulls it.
6. **Review before the first tester sees a feature, not after.** Switch new features off until the review has passed (see the feature flags skill).
   Why: a review that finds a problem after a tester has used it leaves data the tester created, and a fix must handle that data.

## How to do it

What to put in the review request:

```text
Change: <one sentence: what should now be true>
Scope: <commit range or branch, and the files>
Intent: <the spec or the decision it implements; link it>
Ran: <each gate, with pass or fail and the output line that proves it>
Not run: <anything that needs a device, a second account, or hosted data>
Ask: is it safe to push to the server testers use? For each finding give
  1. the failing scenario, step by step, with the data it needs
  2. the smallest change that fixes it
Do not edit files.
```

What a finding looks like when it is useful:

```text
Finding 2. Scenario: member A and member B both press "leave" in the same second.
A's request removes the shared row, B's request reads it before the removal and then
writes a row that points to it. Result: a dangling row that the list still shows.
Smallest fix: take the same lock in both functions, or re-read the row inside the write.
```

Holding a change out of a commit:

```bash
# see what is staged and what is held back
git status --short

# check the committed state on its own, in a separate worktree outside the repo.
# Nothing is stashed, so other work in the main tree is untouched.
git worktree add /path/outside/the/repo/check-head HEAD
(cd /path/outside/the/repo/check-head && npm ci && npx tsc --noEmit && npx jest --ci)
git worktree remove /path/outside/the/repo/check-head
```

Run the gates in the worktree, not in the working tree that holds the held changes. If a gate fails there, the commit depends on a held file, and the commit must be split again.

## Gotchas
Findings that reviews actually caught in one project. Each is a pattern to look for, not a rule about that project's code.

- **A fix for one feature changed behaviour for every user.** A navigation handler was made global to fix one screen, and it changed the back behaviour of every screen. The fix is to scope the handler to the screen, or to pin the old behaviour with tests first (see the Jest skill, rule 7).
- **A cleanup could delete a row that another request was writing.** A sweep ran over rows that a live request was still changing. The fix is to skip rows under an active change, and to test the sweep while a change is open.
- **A test would have purged a hosted database.** A purge test had no guard on which host it ran against. The fix refuses any host except the local one (see the Deno skill).
- **Private answers could be recovered from an aggregate.** A band computed from very few shared answers let one person infer the other's answers. The fix is a minimum sample size before any band is shown, and a frozen snapshot rather than a live value.
- **An award revealed hidden content.** An award and a recap showed a photo from a space whose photos were hidden. The fix is to check visibility in every place that shows an item, not only in the main list.
- **A check passed when a download failed.** A photo check returned a pass when the bytes could not be read. The fix binds the check to the bytes it read, and makes "no result" a fail, never a pass by default.
- **A per address limit could be spoofed.** The limit read a client-sent header. The fix reads the platform's header and keeps the per member cap as the hard limit.
- **A ban left a shared space in place.** A moderation action did not end the shared space it belonged to. The fix ends the space in the same action.

## Checklist
- [ ] The request gives the intent, the scope, the gate output, and what was not run.
- [ ] The request does not contain the author's conclusion.
- [ ] Every finding has a failing scenario and a smallest fix.
- [ ] The reviewer did not edit files.
- [ ] Each finding is fixed, or answered with a reason, and re-checked.
- [ ] Held changes are not in the commit, and the committed tree was built in a separate worktree.
- [ ] The change is behind a switch if testers should not see it yet.

## Tests that prove it
- Put a known bug into a scratch branch (for example a missing permission check) and confirm the review request surfaces it when it is given to a reviewer who has not seen the fix.
- After holding a change, check out the committed state in a worktree and run the gates there. They must pass without the held file.

## Related skills
- [quality-gates-pipeline](../quality-gates-pipeline/SKILL.md) for the gates the review request quotes.
- [feature-flags-and-safe-rollout](../feature-flags-and-safe-rollout/SKILL.md) for switching a reviewed change on in stages.
- [pgtap-database-testing](../pgtap-database-testing/SKILL.md) and [deno-edge-function-testing](../deno-edge-function-testing/SKILL.md) for the tests a reviewer should ask for.
