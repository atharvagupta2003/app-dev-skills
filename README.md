# App development skills

Skills and subagents for building production mobile apps with Claude Code. Each skill is a short, practical guide distilled from building and shipping a real app: what to do, why, the gotchas that cost time, and the tests that keep it right. The agents are reusable roles that apply those skills.

It is for developers using Claude Code (or another coding agent that reads markdown guidance) on a mobile app with a Postgres backend, and for anyone who wants a worked process for agent assisted builds.

## The stack these skills assume

Expo and React Native with TypeScript, expo-router, React Query and Zustand on the client. Supabase (Postgres, row level security, Edge Functions on Deno, Storage, Realtime, Auth) on the server. Jest and React Native Testing Library, pgTAP, Deno tests and Maestro for testing. A large language model behind a server side broker for an in app assistant. GitHub Actions for CI and deploys, and EAS for builds.

## What is inside

There are 32 skills in `skills/`, 7 agents in `agents/`, and an authoring guide. [INDEX.md](INDEX.md) lists every skill with one line on what it covers.

**Mobile client (7)**
`expo-app-start-performance`, `expo-router-route-gate`, `react-native-android-keyboard`, `react-query-in-react-native`, `offline-outbox-and-sync`, `media-upload-pipeline`, `expo-local-android-builds`.

**Supabase and Postgres (9)**
`supabase-migrations-discipline`, `supabase-rls-and-function-access`, `postgres-concurrency-and-limits`, `supabase-edge-functions-router`, `supabase-storage-private-media`, `postgres-time-zones-and-clocks`, `background-jobs-and-sweeps`, `data-lifecycle-export-purge-deletion`, `privacy-sealing-and-inference`.

**Testing and release (8)**
`quality-gates-pipeline`, `pgtap-database-testing`, `deno-edge-function-testing`, `jest-react-native-testing`, `android-emulator-real-user-testing`, `independent-review-before-deploy`, `maestro-and-flow-tests`, `feature-flags-and-safe-rollout`.

**AI features and process (8)**
`llm-assistant-safety-layers`, `llm-context-allow-list`, `llm-red-team-gate`, `llm-cost-and-budgets`, `agent-orchestration-for-builds`, `spec-first-context-protocol`, `honest-status-reporting`, `milestone-loop-build-review-test`.

**Agents (7)**, described in [agents/README.md](agents/README.md): `mobile-ui-builder`, `backend-architect`, `mobile-qa`, `device-tester`, `independent-reviewer`, `context-curator`, `skills-scribe`.

**Authoring guide:** [AUTHORING.md](AUTHORING.md) covers the skill format, the quality bar, the writing style and the sanitising rules.

## Quick start with Claude Code

For one project:

```sh
mkdir -p .claude/skills .claude/agents
cp -R path/to/app-dev-skills/skills/* .claude/skills/
cp path/to/app-dev-skills/agents/*.md .claude/agents/
```

For all your projects:

```sh
mkdir -p ~/.claude/skills ~/.claude/agents
cp -R path/to/app-dev-skills/skills/* ~/.claude/skills/
cp path/to/app-dev-skills/agents/*.md ~/.claude/agents/
```

You can copy only the skills you need. Skills link to each other by name in their Related skills section, so copy related ones together.

## How skills are loaded

Each `skills/<name>/SKILL.md` starts with frontmatter holding a `name` (the folder name) and a `description`. The description says what the skill covers and when it applies, with the trigger words. Claude Code reads the descriptions up front and loads the full skill when the task matches. Agents name the skills they depend on in their prompts, so a delegated agent loads the right ones. Some skills have `references/` and `examples/` folders that the guide links to.

## A suggested workflow

1. **Spec.** Write the feature spec and acceptance criteria before code: [spec-first-context-protocol](skills/spec-first-context-protocol/SKILL.md), recorded by the `context-curator` agent.
2. **Build.** Split the work with complete briefs: [agent-orchestration-for-builds](skills/agent-orchestration-for-builds/SKILL.md). Use `backend-architect` for the database and functions and `mobile-ui-builder` for screens.
3. **Gates.** Run the fixed gates one at a time and record the counts: [quality-gates-pipeline](skills/quality-gates-pipeline/SKILL.md), run by `mobile-qa`.
4. **Independent review.** Before any push that deploys, get a read only review that returns failing scenarios and smallest fixes: [independent-review-before-deploy](skills/independent-review-before-deploy/SKILL.md), done by `independent-reviewer`.
5. **Device test.** Drive a release build like a real user and report pass, fail or not run: [android-emulator-real-user-testing](skills/android-emulator-real-user-testing/SKILL.md), done by `device-tester`.
6. **Report honestly.** State what was verified, not run and inferred: [honest-status-reporting](skills/honest-status-reporting/SKILL.md). The whole loop is in [milestone-loop-build-review-test](skills/milestone-loop-build-review-test/SKILL.md).
7. **Record learnings.** Fold what you learned back into the skills, with the `skills-scribe` agent and the rules in [AUTHORING.md](AUTHORING.md).

## Adapting it to a different stack

The process skills (orchestration, spec first, honest reporting, the milestone loop, independent review, quality gates, red team) are stack neutral in method; swap the commands. For another backend, keep the principles in the Supabase and Postgres skills (access at the database, one lock order, migrations as the only route) and replace the Supabase specifics. For another client framework, keep the testing and offline guidance and rewrite the Expo specifics. Edit the `tools` and `model` lines in the agent files to match what you have, and keep the report formats, since the skills refer to them. Follow [AUTHORING.md](AUTHORING.md) when you change or add a skill.

## How these were made

The skills were distilled from building a production mobile app with coding agents: each rule comes from something that went wrong or right during a build, review or device test. All project specifics were removed and examples use neutral names. Anything unconfirmed is marked as a hypothesis in the skill that holds it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AUTHORING.md](AUTHORING.md).

## Licence

MIT. See [LICENSE](LICENSE).
