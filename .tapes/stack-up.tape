# Renders the compose stack bring-up. Requires charmbracelet/vhs and docker.
Output .tapes/out/stack-up.gif

Set FontSize 22
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 24

Type "just build"
Sleep 500ms
Enter
Sleep 8s
Type "just up"
Sleep 500ms
Enter
Sleep 4s
Type "just ps"
Sleep 500ms
Enter
Sleep 4s
