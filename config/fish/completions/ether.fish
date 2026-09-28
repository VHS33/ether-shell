# Tab completion for Ether Shell's `ether` command (fish loads this itself)

function __ether_walls
    for f in ~/Pictures/wallpapers/*
        test -f $f; and basename $f
    end
end

complete -c ether -f
complete -c ether -n __fish_use_subcommand -a doctor    -d 'Check the whole setup'
complete -c ether -n __fish_use_subcommand -a restart   -d 'Restart the shell'
complete -c ether -n __fish_use_subcommand -a wallpaper -d 'Set a wallpaper, or open the selector'
complete -c ether -n __fish_use_subcommand -a theme     -d 'Theme everything again from the wallpaper'
complete -c ether -n __fish_use_subcommand -a login     -d 'The login screen'
complete -c ether -n __fish_use_subcommand -a plugin    -d 'Your plugins: list, new, reload'
complete -c ether -n __fish_use_subcommand -a help      -d 'List the commands'

complete -c ether -n '__fish_seen_subcommand_from wallpaper' -a random -d 'A random one'
complete -c ether -n '__fish_seen_subcommand_from wallpaper' -a '(__ether_walls)' -d 'From ~/Pictures/wallpapers'
complete -c ether -n '__fish_seen_subcommand_from wallpaper' -F

complete -c ether -n '__fish_seen_subcommand_from login' -a install -d 'Use Ether Shell\'s login screen'
complete -c ether -n '__fish_seen_subcommand_from login' -a undo    -d 'Back to the one before'
complete -c ether -n '__fish_seen_subcommand_from login' -a status  -d 'Which one starts'

complete -c ether -n '__fish_seen_subcommand_from plugin; and not __fish_seen_subcommand_from list new reload' -a list   -d 'Your plugins, and whether they work'
complete -c ether -n '__fish_seen_subcommand_from plugin; and not __fish_seen_subcommand_from list new reload' -a new    -d 'Start one from a template'
complete -c ether -n '__fish_seen_subcommand_from plugin; and not __fish_seen_subcommand_from list new reload' -a reload -d 'Look for plugins again'
complete -c ether -n '__fish_seen_subcommand_from new' -l bar      -d 'A bar item'
complete -c ether -n '__fish_seen_subcommand_from new' -l launcher -d 'Launcher results'
complete -c ether -n '__fish_seen_subcommand_from new' -l widget   -d 'A desktop widget'
complete -c ether -n '__fish_seen_subcommand_from new' -l settings -d 'Settings of its own'
