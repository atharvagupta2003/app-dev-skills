---
name: llm-context-allow-list
description: Decide exactly what an AI assistant may see about a user, and enforce it in SQL, in code and in tests. Covers untrusted text written by other users, other people's private data, sealed content, shared spaces, server side scope and private, deletable conversations. Load before writing any function that gathers facts for a model prompt.
---

# LLM context allow list

## When to use this
- Writing a function that gathers facts for a prompt.
- Adding a field, table or feature the assistant could read.
- Handling text another user wrote (names, titles, messages, shared list items).
- Designing a shared space or a two person feature where one person's data must stay private.

## Rules
1. **The model is told only what is on an explicit allow list.** Write the list in the feature spec before the code. Why: the model cannot leak what it was never given, so the list is the privacy control.
2. **Enforce the list in SQL and again in code.** The SQL function returns only the named columns; the code copies only the named fields from its result. Why: either layer alone can be changed by accident.
3. **Test the list at three levels.** A database test asserts the exact set of keys; an in process test checks the request that would reach the provider; an offline test injects a forbidden field and asserts it never reaches the request. Why: each level catches a different mistake.
4. **Wrap every string another user controls as untrusted.** Names, titles, messages, list items and profile text are JSON encoded with a source and trust label, and instruction shaped spans are replaced before encoding. Why: a planted instruction in someone's name or message is an attack path.
5. **Never send another person's private data.** That covers their answers (sealed or not yet revealed), their chats, their precise location, their scores as numbers, internal ids, and sensitive traits. Why: the assistant once received one person's private preferences and described them to the other person as shared interests.
6. **Leave out private preferences even when they look harmless.** A field that describes what one person wants becomes a guess about the other person as soon as it is shown as shared. Why: a judge graded that output as an unsupported guess about the partner.
7. **Shared content is visible only while the shared thing is live.** When a shared space is frozen, the assistant sees names only; when it is closed, it sees only the member's own data.
8. **The server decides the scope.** The member, the shared space and the assistant's mode are resolved from the session on the server. The client never names the other party or chooses the surface. Why: a client supplied id is a route to someone else's data. Reads that involve a shared space resolve it from the session, not from a parameter.
9. **The model writes placeholders for names.** It writes a placeholder such as `{name}`, and the server fills it in after validation. Why: the model never sees the name, so it cannot repeat or invent it. The red team runner must tell the judge that the name is filled in, or the judge reads it as invented.
10. **Conversations are private and deletable.** Only the owner can read a conversation, and the owner can hard delete it with its messages. Safety records keep only the kind and a short excerpt. Why: a member may be sharing a phone with the person they are describing.
11. **Keep sensitive fields out of logs.** Log the call, never its content. Why: logs are read by more people and kept longer than the database.

## How to do it
1. In the spec, list each allowed field with its owner, source table and trust label. Mark everything else as "never".
2. Write the SQL function to return exactly those columns, filtered by the session's member. Use a fixed column list, never `select *`.
3. In code, build the context by naming each field. Do not spread the SQL result into the prompt.
4. Wrap untrusted strings:

```ts
// Illustrative; names are invented
const facts = {
  member: { first_name: wrapUntrusted(row.first_name, 'member_name') },
  shared_items: rows.map((r) => ({ title: wrapUntrusted(r.title, 'partner_written') })),
};
```

5. Send the facts only as the result of a context call the server makes itself, with tool use turned off for the model, so the model cannot call anything.

## Gotchas
- **Symptom:** the model presents one person's private preference as something both share. **Cause:** the preference was on the allow list. **Fix:** remove it. Describe only shared facts.
- **Symptom:** a new column leaks after a schema change. **Cause:** the context function used `select *` or a spread. **Fix:** explicit column lists, and an exact key set test that fails when a column is added.
- **Symptom:** a partner's unrevealed answer appears in a reply. **Cause:** the query did not check reveal state. **Fix:** the query returns only the member's own answer, and a partner's answer only after the rules reveal it to both.
- **Symptom:** an instruction inside a name changes the reply. **Cause:** the name was sent raw. **Fix:** wrap and redact instruction shaped spans, and send names as placeholders where the output is about the name.
- **Symptom:** a link or handle from someone's text is repeated back. **Cause:** their text was sent unchanged. **Fix:** replace links and handles in other people's text before the model reads it.

## Checklist
- [ ] Allowed fields listed in the spec, with owner and trust label.
- [ ] SQL returns explicit columns; a test asserts the exact key set.
- [ ] Code names each field; no spread of raw rows.
- [ ] Every other user's string is wrapped, and instruction spans are redacted.
- [ ] Scope is resolved on the server from the session.
- [ ] Frozen and closed states limit what is visible.
- [ ] Offline test: a forbidden field injected into the input never reaches the provider request.
- [ ] The owner can delete a conversation and its messages.

## Tests that prove it
- Database test: the exact key set of the context function; another person's private answers, chats and sealed items are absent. See `pgtap-database-testing`.
- In process test: the request built from a fixture with sealed items and private data contains none of them.
- Offline test: a forbidden field injected into the raw facts is absent from the request body.
- Red team cases for injection through names and shared items (see `llm-red-team-gate`).

## Related skills
- `llm-assistant-safety-layers`: the pipeline that calls this context builder.
- `llm-red-team-gate`: cases for injection and privacy.
- `spec-first-context-protocol`: where the allow list is written down.
