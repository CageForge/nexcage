#!/bin/bash
# Bash completion for nexcage

_nexcage() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local commands="create start stop delete list state kill exec run help version"
    local global_opts="--debug --log-level --log-file --config --help"

    case "$prev" in
        --log-level)
            COMPREPLY=( $(compgen -W "trace debug info warn error fatal" -- "$cur") )
            return 0
            ;;
        --log-file|--config)
            COMPREPLY=( $(compgen -f -- "$cur") )
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
            --log-level|--log-file|--config) ((i++)) ;;
            -*) ;;
            *) cmd="${COMP_WORDS[i]}"; break ;;
        esac
    done

    if [ -z "$cmd" ]; then
        COMPREPLY=( $(compgen -W "$commands $global_opts" -- "$cur") )
        return 0
    fi

    case "$cmd" in
        start|stop|delete|state|kill|exec)
            # Container names from pct; empty when not run as root
            local names
            names=$(pct list 2>/dev/null | awk 'NR > 1 {print $NF}')
            local extra=""
            [ "$cmd" = kill ] && extra="--signal -s"
            COMPREPLY=( $(compgen -W "$names --name --help $extra" -- "$cur") )
            ;;
        create|run)
            COMPREPLY=( $(compgen -W "--name --help" -- "$cur") )
            ;;
        *)
            COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            ;;
    esac
    return 0
}

complete -F _nexcage nexcage
