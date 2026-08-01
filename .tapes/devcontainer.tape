# Renders the devcontainer launch. Requires charmbracelet/vhs and docker.
Output .tapes/out/devcontainer.gif

Set FontSize 22
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 24

Type "just devcontainer-up"
Sleep 500ms
Enter
Sleep 15s
Type "just devcontainer-shell"
Sleep 500ms
Enter
Sleep 3s
Type "claude --version && jcode --version && opencode --version"
Sleep 500ms
Enter
Sleep 4s
