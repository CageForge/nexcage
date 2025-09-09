#!/bin/bash
# Bash completion for proxmox-lxcri

_proxmox_lxcri() {
    local cur prev opts commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Available commands
    commands="create start stop delete list state checkpoint restore run spec kill pause resume exec ps events update features generate-config help version"
    
    # Global options
    opts="--config --root --log --log-format --debug --systemd-cgroup --bundle --pid-file --console-socket --help --version"
    
    # Command-specific options
    case "${COMP_WORDS[1]}" in
        create)
            case "$prev" in
                --bundle|-b)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    return 0
                    ;;
                --config)
                    COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
                    return 0
                    ;;
            esac
            COMPREPLY=( $(compgen -W "--bundle --config --debug --pid-file --console-socket" -- "$cur") )
            return 0
            ;;
        checkpoint)
            case "$prev" in
                --image-path)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    return 0
                    ;;
                --config)
                    COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
                    return 0
                    ;;
            esac
            COMPREPLY=( $(compgen -W "--image-path --config --debug" -- "$cur") )
            return 0
            ;;
        restore)
            case "$prev" in
                --image-path)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    return 0
                    ;;
                --snapshot)
                    # Complete with ZFS snapshot names if available
                    if command -v zfs >/dev/null 2>&1; then
                        local snapshots=$(zfs list -t snapshot -H -o name 2>/dev/null | grep checkpoint- | cut -d@ -f2)
                        COMPREPLY=( $(compgen -W "$snapshots" -- "$cur") )
                    fi
                    return 0
                    ;;
                --config)
                    COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
                    return 0
                    ;;
            esac
            COMPREPLY=( $(compgen -W "--image-path --snapshot --config --debug" -- "$cur") )
            return 0
            ;;
        run)
            case "$prev" in
                --bundle|-b)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    return 0
                    ;;
                --config)
                    COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
                    return 0
                    ;;
            esac
            COMPREPLY=( $(compgen -W "--bundle --config --debug" -- "$cur") )
            return 0
            ;;
        spec)
            case "$prev" in
                --bundle|-b)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    return 0
                    ;;
            esac
            COMPREPLY=( $(compgen -W "--bundle" -- "$cur") )
            return 0
            ;;
        kill)
            COMPREPLY=( $(compgen -W "TERM KILL INT HUP USR1 USR2" -- "$cur") )
            return 0
            ;;
        help)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            return 0
            ;;
        *)
            # For other commands that take container ID
            if [[ "${COMP_WORDS[1]}" =~ ^(start|stop|delete|state|pause|resume|exec|ps|events|update)$ ]]; then
                # Complete with running container IDs if proxmox-lxcri list is available
                if command -v proxmox-lxcri >/dev/null 2>&1; then
                    local containers=$(proxmox-lxcri list 2>/dev/null | awk 'NR>1 {print $1}')
                    COMPREPLY=( $(compgen -W "$containers" -- "$cur") )
                fi
                return 0
            fi
            ;;
    esac
    
    # First word completion
    if [[ ${COMP_CWORD} == 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands $opts" -- "$cur") )
        return 0
    fi
    
    # File completion for config files
    case "$prev" in
        --config)
            COMPREPLY=( $(compgen -f -X '!*.json' -- "$cur") )
            return 0
            ;;
        --log|--pid-file|--console-socket)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --root)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --log-format)
            COMPREPLY=( $(compgen -W "text json" -- "$cur") )
            return 0
            ;;
    esac
    
    # Default completion
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

complete -F _proxmox_lxcri proxmox-lxcri
