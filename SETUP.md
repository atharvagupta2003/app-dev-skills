# Setup instructions for Claude

This file is written for Claude Code. A developer has asked you to set up the app development skills plugin and the tools it works with. Follow the steps in order. The human readable version of the same information is in [README.md](README.md).

## Ground rules

- Check before you install. Skip anything that is already present, and never reinstall or downgrade a tool that is already there.
- Ask once, at the start, which parts the developer wants (step 1). Do not install parts they did not choose.
- Show the commands you are about to run for a step and let the normal permission prompts apply. Do not try to bypass them.
- Never ask for a password, token or key in chat, and never write one into a file. Sign ins are done by the developer in their own terminal or browser (step 6).
- Do not change the developer's project files. This setup only installs tools and Claude Code configuration.
- If a command fails, read the error, try the documented alternative once, and otherwise record it for the final report and carry on with the next item.
- Commands below are for macOS with Homebrew. On Linux or Windows, use the install method from the tool's own site, linked in README.md, and say which method you used.

## Step 1: Ask what to set up

Ask the developer one question with these choices, all selected by default:

1. The plugin itself (34 skills and 7 agents)
2. Companion skills from the platform vendors (Supabase, Expo, React Native, Maestro)
3. MCP servers (Supabase, Expo, Sentry, Metro, Playwright, and XcodeBuildMCP on macOS)
4. Command line tools (Supabase CLI, Deno, EAS CLI, GitHub CLI, Android platform tools, Maestro)

Also ask whether MCP servers should be added for this project only or for every project on the machine. Use `--scope project` for the first and `--scope user` for the second.

## Step 2: Check what is already there

Run these and note the results. They change nothing.

```sh
claude --version
claude plugin list
claude plugin marketplace list
claude mcp list
for t in node npm brew docker supabase deno eas gh adb maestro; do printf "%s: " "$t"; command -v "$t" || echo missing; done
```

Node and npm are required for most of what follows. If they are missing, stop and tell the developer to install Node first.

## Step 3: Install the plugin

```sh
claude plugin marketplace add atharvagupta2003/app-dev-skills
claude plugin install app-dev-skills@app-dev-skills
```

If the developer is working from a local checkout instead, add the marketplace by path: `claude plugin marketplace add path/to/app-dev-skills`.

## Step 4: Install the companion skills

Run from the developer's project folder, so the skills land in that project. Install only the ones that match their stack.

```sh
npx skills add supabase/agent-skills
npx skills add expo/skills
npx skills add software-mansion-labs/skills
npx skills add tovimx/maestro-mobile-testing-skill
```

The `skills` tool may ask which agent and which skills to install. Choose Claude Code, and let the developer answer anything else.

## Step 5: Add the MCP servers

Skip any server that `claude mcp list` already shows. Add `--scope project` or `--scope user` as chosen in step 1.

```sh
claude mcp add --transport http supabase https://mcp.supabase.com/mcp
claude mcp add --transport http expo https://mcp.expo.dev/mcp
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
claude mcp add metro-mcp -- npx -y metro-mcp
claude mcp add playwright -- npx -y @playwright/mcp@latest
claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp
```

Add XcodeBuildMCP only on macOS with Xcode installed. Add Sentry only if the developer uses Sentry.

Tell the developer to point the Supabase server at a development or test project and never at production.

## Step 6: Install the command line tools

Install only what step 2 reported as missing.

```sh
brew install supabase/tap/supabase
brew install deno
npm install -g eas-cli
brew install gh
brew install --cask android-platform-tools
curl -fsSL "https://get.maestro.mobile.dev" | bash
```

Docker is needed for the local Supabase stack and an Android emulator comes with Android Studio. Both are large desktop installs: do not install them yourself. If they are missing, say so in the report with the download pages.

## Step 7: Hand over the sign ins

You cannot complete these, because each opens a browser or asks for credentials. List the ones that apply and ask the developer to run them. In Claude Code they can type `!` before a command to run it in the session.

```sh
supabase login
eas login
gh auth login
```

For the MCP servers that need an account (Supabase, Expo, Sentry), the developer runs `/mcp` in Claude Code and signs in to each.

## Step 8: Verify and report

Run the checks from step 2 again. Then give the developer a short report:

- what was installed, what was already there and what was skipped by their choice
- anything that failed, with the error and the next thing to try
- the sign ins that are still theirs to do
- a reminder to restart Claude Code, or run `/reload-plugins`, so the new plugin, skills and servers load

After the restart, they can confirm the plugin works by typing `/app-dev-skills:` and checking that the skills are listed, and by opening `/agents`.
