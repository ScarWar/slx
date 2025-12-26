# Bash completion for cluster.sh
# Source this file or add to your ~/.bashrc:
#   source /path/to/cluster-completion.bash

_cluster_completion() {
    local cur prev opts commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    commands="submit list running pending kill killall logs tail info status history find clean help"
    
    case "${COMP_CWORD}" in
        1)
            # First argument: command name
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return 0
            ;;
        2)
            # Second argument: depends on the command
            case "${prev}" in
                submit)
                    # Complete with .sbatch files
                    COMPREPLY=($(compgen -f -X '!*.sbatch' -- "${cur}"))
                    return 0
                    ;;
                logs|tail|kill)
                    # Complete with job IDs from squeue
                    if command -v squeue &> /dev/null; then
                        local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                        COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
                    fi
                    return 0
                    ;;
                info)
                    # Complete with job IDs or --nodes/-n option
                    if command -v squeue &> /dev/null; then
                        local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                        local options="--nodes -n"
                        COMPREPLY=($(compgen -W "${job_ids} ${options}" -- "${cur}"))
                    fi
                    return 0
                    ;;
                list)
                    # Complete with --user option
                    COMPREPLY=($(compgen -W "--user" -- "${cur}"))
                    return 0
                    ;;
                history)
                    # Complete with --days option
                    COMPREPLY=($(compgen -W "--days" -- "${cur}"))
                    return 0
                    ;;
                find)
                    # Complete with job names from squeue
                    if command -v squeue &> /dev/null; then
                        local job_names=$(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u)
                        COMPREPLY=($(compgen -W "${job_names}" -- "${cur}"))
                    fi
                    return 0
                    ;;
            esac
            ;;
        3)
            # Third argument: handle options that take values
            case "${COMP_WORDS[1]}" in
                list)
                    if [ "${prev}" == "--user" ]; then
                        # Complete with usernames (if available)
                        if command -v getent &> /dev/null; then
                            local users=$(getent passwd | cut -d: -f1 | sort)
                            COMPREPLY=($(compgen -W "${users}" -- "${cur}"))
                        fi
                    fi
                    return 0
                    ;;
                history)
                    if [ "${prev}" == "--days" ]; then
                        # Suggest common day values
                        COMPREPLY=($(compgen -W "1 3 7 14 30" -- "${cur}"))
                    fi
                    return 0
                    ;;
            esac
            ;;
    esac
    
    return 0
}

# Register completion for cluster.sh
complete -F _cluster_completion cluster.sh
complete -F _cluster_completion cluster

# If aliases are used, complete them too
if command -v cluster.sh &> /dev/null || [ -f "$HOME/workdir/bin/cluster.sh" ] || [ -f "${CLUSTER_WORKDIR:-$HOME/workdir}/bin/cluster.sh" ]; then
    # Try to find cluster.sh in common locations
    _complete_cluster_alias() {
        local cur prev
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        
        # Get the actual command being run
        local cmd="${COMP_WORDS[0]}"
        
        # Map aliases to their commands
        case "$cmd" in
            cs)
                # cs = cluster submit
                if [ "${COMP_CWORD}" -eq 1 ]; then
                    COMPREPLY=($(compgen -f -X '!*.sbatch' -- "${cur}"))
                fi
                ;;
            cl|ct|ck|ci)
                # cl = logs, ct = tail, ck = kill, ci = info
                if [ "${COMP_CWORD}" -eq 1 ] && command -v squeue &> /dev/null; then
                    local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                    COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
                fi
                ;;
            cf)
                # cf = find
                if [ "${COMP_CWORD}" -eq 1 ] && command -v squeue &> /dev/null; then
                    local job_names=$(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u)
                    COMPREPLY=($(compgen -W "${job_names}" -- "${cur}"))
                fi
                ;;
        esac
        return 0
    }
    
    complete -F _complete_cluster_alias cs cl ct ck ci cf 2>/dev/null || true
fi

