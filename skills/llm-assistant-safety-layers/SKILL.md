---
name: llm-assistant-safety-layers
description: Build the server side safety layers for an in app AI assistant that talks to users. A rules pre filter gives fixed crisis replies that never call the model, a context builder feeds the model, an output validator checks every reply, and a scripted fallback covers provider failure. Load when adding or changing an LLM feature that talks to users, or any crisis, abuse or safety handling in one.
---

# LLM assistant safety layers

## When to use this
- Adding an assistant, coach or nudge that shows model written text to users.
- Changing a prompt, the pre filter, the validator or the fallback text.
- Handling a crisis, abuse or safety topic on any surface a user can reach.
- Reviewing a red team failure that involved a refusal, a workaround or a safety reply.

## Rules
1. **Run the rules pre filter before any model call.** Crisis, abuse and obvious attacks get a fixed reply from the server with no model call. Why: a fixed reply is reviewed once and cannot drift; a model reply in a crisis cannot be guaranteed.
2. **The model returns a token, not the words.** For a crisis the model writes only a short kind token, and the server maps it to fixed copy. Why: the model's own words never carry a crisis response.
3. **Normalise before matching.** Apply Unicode normalisation, strip zero width characters, undo look alike letters and leetspeak, and decode base64 runs and scan the decoded text too. Why: people and attackers rephrase to get past plain word matching.
4. **Safety replies are free.** A fixed reply never counts against a message allowance, a daily cap, a budget or a charge. Why: a device test found a safety reply using up one of a conversation's 20 messages, although the screen promised safety replies were free.
5. **Run the safety path before any capacity check.** Full conversation, daily cap and balance checks come after the pre filter. Why: a "conversation full" refusal that ran first hid the safety reply from a member who needed it most.
6. **Aim each rule at the person's intent, not at a word.** Why: a block rule that matched everyday verbs (call, text, contact) refused people asking for ordinary help. The rule that held: a message saying the other person blocked, unmatched or reported the member, together with a way of reaching them.
7. **Every rule ships with near misses that must pass.** Keep a list of benign phrasings that look like the trigger, and assert they get a normal answer. Why: the red team counted benign refusals as failures, and several rules over fired in one round.
8. **Validate every model output before the member sees it.** On failure show the surface's scripted line. Never call the model again to fix a reply. Why: a retry doubles the cost and can fail the same way.
9. **Do not reject true statements as invented features.** Build the "feature does not exist" check from the real feature list, and tell the prompt what the product has and does not have (for example, the chat is text only). Why: one validator rule flagged a benign profile line as a false promise, and another flagged a true statement about where photos go.
10. **Keep safety replies to short lines a frightened person can scan.** Name only controls that exist, by their real label, and say how to leave or delete quietly. Why: the first versions were long; device testing led to short lines that name the real controls.
11. **Check every support number on its official site on the day you ship, and record the date.** Why: a number recalled from memory is unverified; a dated record makes a later audit possible.
12. **Never tell the other party.** Store safety events with the kind and a short excerpt for review. The other member is never told that a safety reply happened. Why: telling the other party can put the person in danger.
13. **Every surface has a scripted fallback.** If the provider is down, times out, refuses, or the output fails validation, the member sees a calm line with no error detail and no endless spinner. Why: the fallback is what the member gets whenever the provider is not working.

## How to do it
One pipeline, used by the edge function, the background jobs and the red team runner, so that they cannot disagree. The order inside it:

1. Normalise the input, then run the pre filter. A crisis or redirect returns the fixed reply and writes a safety event. Stop: no counters, no charge.
2. Check capacity (daily cap, budget, balance, conversation full). A refusal here returns a scripted line.
3. Build the context (see `llm-context-allow-list`), wrap untrusted text, and call the provider with a timeout and a bounded retry count.
4. If the model returned a safety token, return the fixed reply for that kind.
5. Validate the output. Pass: store it, show it, count usage. Fail: show the scripted line and count nothing.

```ts
// Illustrative shape; names are invented
export function answer(input: string, state: SurfaceState): Reply {
  const pre = preFilter(normalise(input));
  if (pre.kind === 'safety') return fixedReply(pre.kind); // free, and first
  if (!capacity(state).ok) return scripted('resting');     // a refusal, not an error
  const raw = callModel(buildContext(state, input));       // may fail
  if (!raw.ok) return scripted('fallback');
  if (raw.token) return fixedReply(raw.token);
  const v = validate(raw.text, state.surface);
  return v.ok ? { text: raw.text, counted: true } : scripted('validator');
}
```

## Gotchas
- **Symptom:** ordinary questions such as "how do I contact them" get a refusal. **Cause:** a rule matched a common verb without the intent aimed at the person. **Fix:** rewrite the rule around the intent, then add the phrasing to the near miss list.
- **Symptom:** a crisis message that also mentions a full conversation gets the full refusal. **Cause:** the capacity check ran before the pre filter. **Fix:** the pre filter runs first. This needed a pipeline change and was left open for a while; treat it as a must.
- **Symptom:** a safety reply lowers a member's remaining messages. **Cause:** usage was counted before the reply kind was known. **Fix:** count only model written replies that passed validation.
- **Symptom:** the assistant offers a workaround after the member was blocked, a critical red team failure. **Cause:** the model's variance on a path no rule covered. **Fix:** a pre filter rule with no model call, plus a red team case for each phrasing.
- **Symptom:** the assistant promises a feature the product does not have, such as a voice note. **Cause:** the feature list in the prompt was incomplete and the validator had no rule. **Fix:** list what exists and what does not, and add a validator rule for features outside the product.
- **Symptom:** a helpline number is wrong. **Cause:** it was never checked. **Fix:** check the official site, and record the date.
- **Symptom:** a provider outage shows an error or a spinner. **Cause:** one path has no scripted line. **Fix:** every path returns a scripted line.

## Checklist
- [ ] Pre filter runs before capacity checks and before any model call.
- [ ] Fixed safety replies write no usage, charge nothing, and ignore budgets.
- [ ] The model returns tokens for crisis, never crisis words.
- [ ] Every rule has a near miss list that passes.
- [ ] The validator checks features against the real feature list.
- [ ] Support numbers checked on official sites, with the date recorded.
- [ ] Each surface has a scripted fallback, including timeouts.
- [ ] Safety events store kind and a short excerpt; the other party is never told.

## Tests that prove it
- Pre filter unit tests: every trigger category, every normalisation trick, and the near miss list (must not trigger).
- Integration test with a stub provider: a crisis input makes zero provider calls and returns the right kind; a full conversation still gets the safety reply. See `deno-edge-function-testing`.
- Counter test: a safety reply leaves usage, caps and balance unchanged.
- Validator tests: a failing and a passing example per rule, including true statements.
- Outage test: timeout, error and refusal each return the scripted line.
- A red team run for every prompt or validator change (see `llm-red-team-gate`).

## Related skills
- `llm-context-allow-list`: what the model may see.
- `llm-cost-and-budgets`: fixed replies and budgets.
- `llm-red-team-gate`: proving the layers hold against the real model.
- `honest-status-reporting`: how to report safety test results.
