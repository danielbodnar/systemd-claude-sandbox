# Renders the install.sh decision trail. Requires charmbracelet/vhs.
Output .tapes/out/install.gif

Set FontSize 22
Set Width 1200
Set Height 600
Set Theme "Catppuccin Mocha"
Set Padding 24

Type "bash install.sh"
Sleep 500ms
Enter
Sleep 6s
