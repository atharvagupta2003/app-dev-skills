# App development skills

Skills and subagents for building production mobile apps with Claude Code. Each skill is a short, practical guide distilled from building and shipping a real app: what to do, why, the gotchas that cost time, and the tests that keep it right. The agents are reusable roles that apply those skills.

It is for developers using Claude Code (or another coding agent that reads markdown guidance) on a mobile app with a Postgres backend, and for anyone who wants a worked process for agent assisted builds.

## The stack these skills assume

Expo and React Native with TypeScript, expo-router, React Query and Zustand on the client. Supabase (Postgres, row level security, Edge Functions on Deno, Storage, Realtime, Auth) on the server. Jest and React Native Testing Library, pgTAP, Deno tests and Maestro for testing. A large language model behind a server side broker for an in app assistant. GitHub Actions for CI and deploys, and EAS for builds.

## What is inside

There are 34 skills in `skills/`, 7 agents in `agents/`, and an authoring guide. [INDEX.md](INDEX.md) lists every skill with one line on what it covers.

**Mobile client (7)**
`expo-app-start-performance`, `expo-router-route-gate`, `react-native-android-keyboard`, `react-query-in-react-native`, `offline-outbox-and-sync`, `media-upload-pipeline`, `expo-local-android-builds`.

**Supabase and Postgres (11)**
`supabase-migrations-discipline`, `supabase-rls-and-function-access`, `postgres-concurrency-and-limits`, `supabase-edge-functions-router`, `supabase-storage-private-media`, `postgres-time-zones-and-clocks`, `background-jobs-and-sweeps`, `data-lifecycle-export-purge-deletion`, `privacy-sealing-and-inference`, `internal-console-act-as-test-accounts`, `temporary-auth-ban-lift`.

**Testing and release (8)**
`quality-gates-pipeline`, `pgtap-database-testing`, `deno-edge-function-testing`, `jest-react-native-testing`, `android-emulator-real-user-testing`, `independent-review-before-deploy`, `maestro-and-flow-tests`, `feature-flags-and-safe-rollout`.

**AI features and process (8)**
`llm-assistant-safety-layers`, `llm-context-allow-list`, `llm-red-team-gate`, `llm-cost-and-budgets`, `agent-orchestration-for-builds`, `spec-first-context-protocol`, `honest-status-reporting`, `milestone-loop-build-review-test`.

**Agents (7)**, described in [docs/agents.md](docs/agents.md): `mobile-ui-builder`, `backend-architect`, `mobile-qa`, `device-tester`, `independent-reviewer`, `context-curator`, `skills-scribe`.

**Authoring guide:** [AUTHORING.md](AUTHORING.md) covers the skill format, the quality bar, the writing style and the sanitising rules.

## Let Claude set it all up

You do not have to follow the install sections below by hand. Open Claude Code in your project and paste this:

```
Read https://raw.githubusercontent.com/atharvagupta2003/app-dev-skills/main/SETUP.md and follow it to set up the app development skills for me.
```

Claude reads [SETUP.md](SETUP.md), asks which parts you want, checks what is already on your machine, and then installs the rest: this plugin, the companion skills from the platform vendors, the MCP servers and the command line tools. It skips anything you already have and asks before running commands, as usual.

A few things stay with you, and Claude will list them at the end: signing in to your accounts (`supabase login`, `eas login`, `gh auth login`, and `/mcp` for the servers), installing Docker and Android Studio if you need them, and restarting Claude Code so everything loads.

The sections below describe the same steps if you would rather do them yourself.

## Install as a Claude Code plugin

The repository is a Claude Code plugin and its own marketplace. In Claude Code, run:

```
/plugin marketplace add atharvagupta2003/app-dev-skills
/plugin install app-dev-skills@app-dev-skills
```

Or from your shell:

```sh
claude plugin marketplace add atharvagupta2003/app-dev-skills
claude plugin install app-dev-skills@app-dev-skills
```

That installs all 34 skills and 7 agents. Skills load on their own when a task matches; you can also call one directly, for example `/app-dev-skills:quality-gates-pipeline`. Agents show up in `/agents` and can be delegated to by name. To get updates, run `/plugin marketplace update app-dev-skills`. To try a local checkout without installing, start Claude Code with `claude --plugin-dir path/to/app-dev-skills`.

## Install the companion skills

These skills are lessons from one real build. They sit on top of the general platform knowledge that the platform vendors publish and do not repeat it. The build they came from had the vendor skills below installed, so install the ones that match your stack from their original sources:

| Stack | Source | Install |
| --- | --- | --- |
| Supabase and Postgres | [supabase/agent-skills](https://github.com/supabase/agent-skills) | `npx skills add supabase/agent-skills` |
| Expo | [Expo Skills](https://docs.expo.dev/skills/) | `npx skills add expo/skills` |
| React Native | [software-mansion-labs/skills](https://github.com/software-mansion-labs/skills) | `npx skills add software-mansion-labs/skills` |
| Maestro flow tests | [tovimx/maestro-mobile-testing-skill](https://github.com/tovimx/maestro-mobile-testing-skill) | `npx skills add tovimx/maestro-mobile-testing-skill` |

In Claude Code, Expo also ships an official plugin in the `claude-plugins-official` marketplace, which registers the Expo MCP server as well; see the Expo page above. Each of these is owned and licensed by its publisher. None of their content is copied into this repository, and this repository is not affiliated with or endorsed by them.

## Connect the MCP servers and CLIs

The skills tell the agent what to do; these give it the hands to do it. Connect the ones that match your stack. Nothing here is required to read the skills, but the agents work best when they can run the tools the skills refer to.

**MCP servers.** Add each one from your shell, then run `/mcp` inside Claude Code to sign in where a server asks for it.

| Server | What the agent uses it for | Connect |
| --- | --- | --- |
| Supabase | Inspect tables, apply migrations, read logs and advisors, deploy functions | `claude mcp add --transport http supabase https://mcp.supabase.com/mcp` |
| Expo | Expo docs, EAS builds and workflows | `claude mcp add --transport http expo https://mcp.expo.dev/mcp` (already included if you installed the Expo plugin) |
| Sentry | Read crashes and errors from test builds | `claude mcp add --transport http sentry https://mcp.sentry.dev/mcp` |
| Metro | Console logs, network calls and component tree of the running app | `claude mcp add metro-mcp -- npx -y metro-mcp` |
| Playwright | Click through web pages such as an internal console | `claude mcp add playwright -- npx -y @playwright/mcp@latest` |
| XcodeBuildMCP | Build and drive the app on an iOS simulator (macOS only) | `claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` |

Point the Supabase server at a development or test project, never at production. Its documentation covers limiting it to one project and to read only mode.

**CLIs.** The skills run these directly. Install commands are for macOS with Homebrew; each tool's own site covers other systems.

| CLI | Used by | Install |
| --- | --- | --- |
| Supabase CLI (needs Docker for the local stack) | Migrations, local database, pgTAP tests, function deploys | `brew install supabase/tap/supabase` |
| Deno | Edge function checks and tests | `brew install deno` |
| EAS CLI | Local and cloud app builds | `npm install -g eas-cli` |
| GitHub CLI | Watching CI runs, pull requests | `brew install gh` |
| Android platform tools (`adb`) and an emulator | Real user testing on a device | `brew install --cask android-platform-tools`, or Android Studio for the emulator |
| Maestro | Flow tests on a simulator or emulator | `curl -fsSL "https://get.maestro.mobile.dev" \| bash` |

Sign in once for each (`supabase login`, `eas login`, `gh auth login`) so the agent does not stall on a login prompt. Keep keys and tokens out of the repository and out of chat; the skills assume secrets live only in environment files that git ignores.

## Manual install

If you want only some skills, or want to edit them for your project, copy them instead.

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

Skills link to each other by name in their Related skills section, so copy related ones together.

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
