#!/bin/bash
# Bash completion for nexcage

_nexcage() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="create start stop delete list state kill exec features ps images pull rmi pause resume update snapshot snapshots rollback delsnapshot run health help version"
    local global_opts="--debug --log-level --log-file --log --log-format --config --root --runtime --systemd-cgroup --help --version"

    case "$prev" in
        --log-level)
            COMPREPLY=( $(compgen -W "trace debug info warn error fatal" -- "$cur") )
            return 0
            ;;
        --log-file|--log|--config)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --log-format)
            COMPREPLY=( $(compgen -W "text json" -- "$cur") )
            return 0
            ;;
        --root)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --runtime)
            COMPREPLY=( $(compgen -W "lxc crun" -- "$cur") )
            return 0
            ;;
        -s|--signal)
            COMPREPLY=( $(compgen -W "SIGTERM SIGKILL SIGINT SIGHUP SIGUSR1 SIGUSR2 SIGCONT SIGSTOP" -- "$cur") )
            return 0
            ;;
    esac

    # The command is the first word that is not a global option or its value
    local i cmd=""
    for ((i = 1; i < COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
            --log-level|--log-file|--config|--root|--runtime|--log|--log-format) ((i++)) ;;
            -*) ;;
            *) cmd="${COMP_WORDS[i]}"; break ;;
        esac
    done

    if [ -z "$cmd" ]; then
        COMPREPLY=( $(compgen -W "$commands $global_opts" -- "$cur") )
        return 0
    fi

    case "$cmd" in
        start|stop|delete|state|kill|exec|pause|resume|update|snapshot|snapshots|rollback|delsnapshot)
            # Container names from pct; empty when not run as root
            local names
            names=$(pct list 2>/dev/null | awk 'NR > 1 {print $NF}')
            local extra=""
            [ "$cmd" = kill ] && extra="--signal -s --all -a"
            [ "$cmd" = delete ] && extra="--force -f"
            [ "$cmd" = exec ] && extra="--process --tty -t --detach -d --cwd --user --console-socket --pid-file"
            [ "$cmd" = snapshots ] && extra="--format"
            [ "$cmd" = snapshot ] && extra="--description"
            [ "$cmd" = rollback ] && extra="--start"
            [ "$cmd" = update ] && extra="--resources -r --memory --memory-swap --memory-reservation --cpu-quota --cpu-period --cpu-share --cpu-shares --cpuset-cpus --cpuset-mems --pids-limit --blkio-weight --cpu-rt-period --cpu-rt-runtime --kernel-memory --kernel-memory-tcp"
            COMPREPLY=( $(compgen -W "$names --name --help $extra" -- "$cur") )
            ;;
        ps)
            # ps answers for crun containers only, and pct lists none of them
            COMPREPLY=( $(compgen -W "--name --help --format" -- "$cur") )
            ;;
        create|run)
            local extra="--bundle --storage"
            [ "$cmd" = create ] && extra="--bundle --console-socket --pid-file --node --storage --memory --memory-swap --cpu-quota --cpu-period --cpu-share --cores --ip --gw --vlan --firewall --onboot --tags --mp"
            COMPREPLY=( $(compgen -W "--name --help $extra" -- "$cur") )
            ;;
        pull)
            COMPREPLY=( $(compgen -W "--node --storage --filename --help" -- "$cur") )
            ;;
        images|rmi)
            COMPREPLY=( $(compgen -W "--node --help" -- "$cur") )
            ;;
        *)
            COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            ;;
    esac
    return 0
}

complete -F _nexcage nexcage
