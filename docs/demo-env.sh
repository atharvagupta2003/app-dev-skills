# Shell setup for the demo recording. Sourced (hidden) by demo.tape.
export PS1='$ '
mark() { perl -MTime::HiRes=time -e 'printf "%.3f", time' > "$DEMO_MARKS/start"; }
claude() {
  command claude --plugin-dir "$PLUGIN_DIR" --setting-sources project \
    --settings "$DEMO_SETTINGS" --strict-mcp-config --mcp-config "$EMPTY_MCP" \
    --model sonnet --permission-mode dontAsk --tools "Skill,Read,Edit,Write,Glob,Grep,Bash" "$@"
}
