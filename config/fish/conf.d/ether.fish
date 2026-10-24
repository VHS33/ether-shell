# Ether Shell's additions to fish.  Updates replace this file, so put your
# own settings in ~/.config/fish/config.fish: fish reads it after this one,
# so anything there wins.  Each part runs only if its program is installed.
# The colours (fish's, the prompt's, fzf's) come from your wallpaper; see
# ~/.config/matugen/config-terminal.toml.
status is-interactive; or return

# the prompt (starship reads ~/.config/starship/ether.toml, which the theme
# writes; if your config.fish starts starship too, that's harmless)
if command -q starship
    starship init fish | source
end

# fzf: Ctrl+R searches your history, Ctrl+T finds a file, Alt+C goes into a
# folder.  Its colours are read from a file each time it runs; only used
# when the file is there (fzf won't start if it's pointed at a missing one).
if command -q fzf
    if not set -q FZF_DEFAULT_OPTS_FILE; and test -f ~/.config/ether/fzf-colors
        set -gx FZF_DEFAULT_OPTS_FILE ~/.config/ether/fzf-colors
    end
    fzf --fish 2>/dev/null | source
end

# zoxide: `z glass` goes to the folder you use most that matches (glassly),
# `zi` picks from a list
if command -q zoxide
    zoxide init fish | source
end

# abbreviations: typed, they expand in place (so you see the full command)
abbr -a er ether restart
abbr -a gs git status
abbr -a ga git add
abbr -a gc git commit
abbr -a gp git push
abbr -a gl git log --oneline -15
