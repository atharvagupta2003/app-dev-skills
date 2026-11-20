# Contributing

Thanks for helping. Contributions are new skills, corrections to existing skills, and improvements to the agent definitions.

## Before you write

- Read [AUTHORING.md](AUTHORING.md). It sets the skill format, the quality bar and the writing style.
- Follow its sanitising rules. Nothing may identify a private system, a product, a person or a machine: no secrets, project ids, emails, names, private URLs, local paths, business rules, prices or copy. Use neutral names in examples. If you are unsure whether something identifies a source, leave it out.
- Record only what you saw happen or tested. Mark anything unconfirmed as a hypothesis.

## Checks

- Each `skills/<name>/SKILL.md` has frontmatter with `name` (equal to the folder name) and `description`.
- `INDEX.md` lists every skill folder exactly once, and every link resolves.
- The counts in `README.md` match the folders.
- Search your change for private strings (emails, ids, keys, absolute paths) before you open a pull request.

## Commits

Use conventional commits (`docs:`, `feat:`, `fix:`, `chore:`), one logical change per commit, for example `docs(supabase-rls-and-function-access): add a grants check gotcha`. Say what changed and why in the body when it is not obvious.

## Licence

By contributing you agree your work is released under the [MIT licence](LICENSE).
