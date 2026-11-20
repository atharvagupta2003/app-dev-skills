---
name: llm-cost-and-budgets
description: Keep an LLM feature's cost bounded. Covers per member daily caps, a monthly feature budget held by reservation under a lock, scripted replies when a budget is spent, free fixed replies, charging only for delivered replies, logging without content, and choosing a curated deterministic design when a model adds nothing. Load when adding a paid model call, setting caps or budgets, charging for assistant use, or deciding whether a feature needs a model.
---

# LLM cost and budgets

## When to use this
- Adding a model call, or a new surface on an existing assistant.
- Setting a per member daily cap or a monthly feature budget.
- Charging members for an assistant conversation.
- Choosing between a model written feature and a curated, rule chosen one.

## Rules
1. **Every number is a settings row.** Caps, prices, budgets and reserves live in rows, not code. A missing row turns the feature off. Why: a guessed default ships a cost nobody approved, and a row can change without a release.
2. **Reserve before the call, under one lock.** Take one lock for the feature, add this period's settled spend and every pending reservation, refuse if the total would reach the budget, then insert a pending usage row. Settle it with actual tokens afterwards. Why: without the lock, parallel requests all pass the same check.
3. **Reserve at the dearest recent cost, with a floor.** The cost of a call is known only after it runs. Reserve the dearest recent call and never less than a small minimum. Why: a new month has no history, and without a floor its first calls reserve nothing.
4. **A spent budget returns a scripted, kind line.** Say the feature is resting for now. Let the app show a resting state before the member sends. Why: a member should not meet a failure for a limit they could not see.
5. **Budgets never block safety.** Safety replies run before any cap or budget check, and cost nothing. See `llm-assistant-safety-layers`.
6. **Fixed and scripted replies write no usage row.** They do not count against caps, budgets or the member's message allowance. Why: the usage table measures model cost. Counting fixed text inflates the budget and punishes the safety replies.
7. **Charge for a delivered reply, once.** Charge on the first model reply that passed validation and was stored, under a key tied to the conversation. Never charge at start. Why: nothing is charged for a reply that was never delivered, and retries cannot charge twice. A ledger without refunds makes this order necessary.
8. **Log each provider call, not its content.** Log the function, surface, provider request id, model, outcome, tokens and duration. Never log message bodies, names, prompts or keys. Why: a log with content is a second copy of private data.
9. **Store the cost of each call in the smallest unit, at the price in force then.** Why: later price changes must not rewrite history, and monthly totals should match the provider's bill.
10. **Ask whether a model is needed.** A curated bank of items, chosen by simple rules, is cheaper, predictable and easy to test. Why: an activity suggestion feature was built as a bank of a few dozen written rows, picked by least shown first, season, occasion and day of week, with no model call. The trade-off is that the suggestions are generic, not tailored.
11. **Count every surface in the member's daily cap.** Why: one surface outside the cap becomes a way round it.
12. **Set the provider's spend limit, and use a key the organisation owns, before launch.** Why: a personal key that runs out or leaves takes the feature down for everyone.

## How to do it
Reservation sketch in SQL (names are invented; run it inside one function, after taking the feature lock):

```sql
select coalesce(sum(cost_micro_usd), 0) into spent
  from usage where period = current_period and status = 'settled';
select coalesce(sum(reserve_micro_usd), 0) into pending
  from usage where period = current_period and status = 'pending';
if spent + pending + reserve_for_next_call() > budget_row.amount then
  raise exception 'budget_reached';
end if;
insert into usage (member_id, status, reserve_micro_usd, period)
  values (p_member, 'pending', reserve_for_next_call(), current_period);
```

Order of checks in the function: fixed reply (free) first; then the daily cap and budget (reserve); then the provider call with a timeout; then validate; then settle the usage row and store the reply.

## Gotchas
- **Symptom:** the monthly budget is exceeded by a small amount. **Cause:** the cost is known only after the call. **Fix:** reserve at the dearest recent cost, accept an overrun bounded by the reservations, and say so in the spec.
- **Symptom:** a member is refused with a database error. **Cause:** a settings row is missing. **Fix:** an absent row means the feature is off, and the member gets a scripted line.
- **Symptom:** after several full test runs in one day, the provider credit was exhausted, every call failed, and the assistant stopped working for testers. **Cause:** a full run costs a few dollars, most of it for the judge model, and no spend limit or run budget was set. **Fix:** a provider spend limit, a run budget, and filtered trial runs while tuning. See `llm-red-team-gate`.
- **Symptom:** a safety reply is counted in the daily cap. **Cause:** usage was written for every reply. **Fix:** write usage only for model replies that passed validation.
- **Symptom:** a charge exists for a conversation that got no reply. **Cause:** the charge was made at start. **Fix:** move the charge to the first delivered reply.

## Checklist
- [ ] Caps, prices and budgets are rows; an absent row means off.
- [ ] Reservation under a lock; pending reservations counted; a floor applied.
- [ ] A spent budget gives a scripted resting line, and the app can show the state early.
- [ ] Fixed replies write no usage and cost nothing.
- [ ] Charge on the first delivered model reply only, idempotent per conversation.
- [ ] Logs hold ids, outcome, tokens and duration, never content.
- [ ] Provider spend limit set; the key belongs to the organisation.
- [ ] Asked whether a curated design would do before adding a model call.

## Tests that prove it
- Concurrency test: parallel calls at the budget edge; exactly the allowed number pass. See `postgres-concurrency-and-limits`.
- An absent budget row refuses with the resting line, not an error.
- A fixed reply leaves every usage count unchanged.
- Log test: a call's log entry has the allowed fields and none of the message text.
- Charge test: a provider failure charges nothing; a second send in the same conversation charges once.

## Related skills
- `llm-assistant-safety-layers`: safety replies are free.
- `llm-red-team-gate`: budgeting test runs.
- `spec-first-context-protocol`: keeping numbers as rows and marking them proposed.
