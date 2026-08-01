# Renders the tunnel starting and answering a health check.
# Requires charmbracelet/vhs and bun.
Output .tapes/out/mcp-tunnel.gif

Set FontSize 22
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 24

Type "just tunnel-dev &"
Sleep 500ms
Enter
Sleep 3s
Type "curl -s localhost:8787/healthz | jq"
Sleep 500ms
Enter
Sleep 4s
