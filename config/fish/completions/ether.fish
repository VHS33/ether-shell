# Tab completion for Ether Shell's `ether` command (fish loads this itself)

function __ether_walls
    for f in ~/Pictures/wallpapers/*
        test -f $f; and basename $f
    end
end

complete -c ether -f
complete -c ether -n __fish_use_subcommand -a doctor    -d 'Check the whole setup'
complete -c ether -n __fish_use_subcommand -a restart   -d 'Restart the shell'
complete -c ether -n __fish_use_subcommand -a perf      -d 'Where its memory and time go'
complete -c ether -n __fish_use_subcommand -a wallpaper -d 'Set a wallpaper, or open the selector'
complete -c ether -n __fish_use_subcommand -a theme     -d 'Theme everything again from the wallpaper'
complete -c ether -n __fish_use_subcommand -a login     -d 'The login screen'
complete -c ether -n __fish_use_subcommand -a plugin    -d 'Your plugins: list, reload'
complete -c ether -n __fish_use_subcommand -a help      -d 'List the commands'

complete -c ether -n '__fish_seen_subcommand_from wallpaper' -a random -d 'A random one'
complete -c ether -n '__fish_seen_subcommand_from wallpaper' -a '(__ether_walls)' -d 'From ~/Pictures/wallpapers'
complete -c ether -n '__fish_seen_subcommand_from wallpaper' -F

complete -c ether -n '__fish_seen_subcommand_from login' -a install -d 'Use Ether Shell\'s login screen'
complete -c ether -n '__fish_seen_subcommand_from login' -a undo    -d 'Back to the one before'
complete -c ether -n '__fish_seen_subcommand_from login' -a status  -d 'Which one starts'

complete -c ether -n '__fish_seen_subcommand_from plugin; and not __fish_seen_subcommand_from list reload' -a list   -d 'Your plugins, and whether they work'
complete -c ether -n '__fish_seen_subcommand_from plugin; and not __fish_seen_subcommand_from list reload' -a reload -d 'Look for plugins again'
