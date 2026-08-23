# hfget demo — regenerate the GIF with:  vhs demo.tape
# Runs real commands in an isolated .demo/ sandbox (its own state dir), so it
# never touches your real ~/.hfget queue.

Output demo.gif

Set Shell "bash"
Set FontSize 15
Set Width 1000
Set Height 620
Set Padding 24
Set TypingSpeed 35ms
Set Theme { "name": "hfget", "background": "#0E1417", "foreground": "#E7EDEE", "cursor": "#33C7C0", "selection": "#20303A", "black": "#0E1417", "brightBlack": "#5B6E72", "red": "#E5766B", "brightRed": "#F08C82", "green": "#4FC585", "brightGreen": "#66D69A", "yellow": "#E0A052", "brightYellow": "#EDB877", "blue": "#5AA9E6", "brightBlue": "#7CC0F2", "magenta": "#B58AE6", "brightMagenta": "#C7A6EE", "cyan": "#33C7C0", "brightCyan": "#7FE3DC", "white": "#C8D2D4", "brightWhite": "#FFFFFF" }

Hide
Type `export PS1='\[\e[36m\]❯\[\e[0m\] '`
Enter
Type "export HFGET_NOCAFFEINE=1 HFGET_QUEUE_NOSTART=1 HFGET_QUEUE_NOWAIT=1"
Enter
Type "export HFGET_DEST=.demo/models HFGET_STATE_DIR=.demo/state"
Enter
Type "rm -rf .demo && mkdir -p .demo"
Enter
Type "clear"
Enter
Show

Sleep 600ms
Type "# download a model — it streams straight into your folder"
Enter
Sleep 400ms
Type "./hfget download sshleifer/tiny-gpt2 --verify -y"
Enter
Sleep 8s

Type "clear"
Enter
Sleep 400ms
Type "# stored as a tidy mirror:  <your folder>/<org>/<model>/"
Enter
Sleep 400ms
Type "find .demo/models -type f | sort"
Enter
Sleep 3s

Type "clear"
Enter
Sleep 400ms
Type "# or line several up and let them download in the background"
Enter
Sleep 400ms
Type "./hfget add sshleifer/tiny-distilroberta-base -y"
Enter
Sleep 4500ms
Type "./hfget status"
Enter
Sleep 4s

Hide
Type "rm -rf .demo"
Enter
Show
