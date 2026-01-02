# Bash completion for slx (SLurm eXtended)
# Source this file or add to your ~/.bashrc:
#   source ~/.local/share/slx/completions/slx.bash

_slx_completion() {
    local cur prev opts commands project_commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Helper function to check if a string is a numeric job ID
    _is_job_id() {
        [[ "$1" =~ ^[0-9]+$ ]]
    }
    
    # Main commands
    commands="init project profile submit list running pending kill killall logs tail info status history find clean version help"
    
    # Project subcommands
    project_commands="new submit list help"
    
    # Profile subcommands
    profile_commands="new list show delete help"
    
    case "${COMP_CWORD}" in
        1)
            # First argument: command name
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return 0
            ;;
        2)
            # Second argument: depends on the command
            case "${prev}" in
                project)
                    COMPREPLY=($(compgen -W "${project_commands}" -- "${cur}"))
                    return 0
                    ;;
                profile)
                    COMPREPLY=($(compgen -W "${profile_commands}" -- "${cur}"))
                    return 0
                    ;;
                submit)
                    # Complete with .sbatch files
                    COMPREPLY=($(compgen -f -X '!*.sbatch' -- "${cur}"))
                    return 0
                    ;;
                logs|tail|kill)
                    # Complete with job IDs from squeue (only job IDs, no other commands)
                    if command -v squeue &> /dev/null; then
                        local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                        COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
                    else
                        # No squeue available, return empty to prevent showing other commands
                        COMPREPLY=()
                    fi
                    return 0
                    ;;
                info)
                    # Complete with job IDs only at position 2
                    if command -v squeue &> /dev/null; then
                        local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                        COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
                    else
                        COMPREPLY=()
                    fi
                    return 0
                    ;;
                list)
                    COMPREPLY=($(compgen -W "--user" -- "${cur}"))
                    return 0
                    ;;
                history)
                    COMPREPLY=($(compgen -W "--days" -- "${cur}"))
                    return 0
                    ;;
                find)
                    if command -v squeue &> /dev/null; then
                        local job_names=$(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u)
                        COMPREPLY=($(compgen -W "${job_names}" -- "${cur}"))
                    else
                        COMPREPLY=()
                    fi
                    return 0
                    ;;
                *)
                    # For other commands, return empty to prevent showing default completions
                    COMPREPLY=()
                    return 0
                    ;;
            esac
            ;;
        3)
            # Third argument
            case "${COMP_WORDS[1]}" in
                logs|tail|kill)
                    # Complete with job IDs from squeue (after logs/tail/kill command)
                    if command -v squeue &> /dev/null; then
                        local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                        COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
                    else
                        # No squeue available, return empty to prevent showing other commands
                        COMPREPLY=()
                    fi
                    return 0
                    ;;
                project)
                    case "${COMP_WORDS[2]}" in
                        submit)
                            # Complete with project names
                            local workdir="${SLX_WORKDIR:-$HOME/workdir}"
                            if [ -d "$workdir/projects" ]; then
                                local projects=$(ls -1 "$workdir/projects" 2>/dev/null)
                                COMPREPLY=($(compgen -W "${projects}" -- "${cur}"))
                            fi
                            return 0
                            ;;
                        new)
                            # Complete with --git, --no-git, --profile
                            COMPREPLY=($(compgen -W "--git --no-git --profile" -- "${cur}"))
                            return 0
                            ;;
                    esac
                    ;;
                profile)
                    case "${COMP_WORDS[2]}" in
                        show|delete)
                            # Complete with profile names
                            local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/slx"
                            if [ -d "$config_dir/profiles.d" ]; then
                                local profiles=$(ls -1 "$config_dir/profiles.d"/*.env 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.env$//')
                                COMPREPLY=($(compgen -W "${profiles}" -- "${cur}"))
                            fi
                            return 0
                            ;;
                    esac
                    ;;
                info)
                    # If position 2 was a job ID, show flag options
                    if _is_job_id "${COMP_WORDS[2]}"; then
                        local options="--nodes -n"
                        COMPREPLY=($(compgen -W "${options}" -- "${cur}"))
                    fi
                    return 0
                    ;;
                list)
                    if [ "${prev}" == "--user" ]; then
                        if command -v getent &> /dev/null; then
                            local users=$(getent passwd | cut -d: -f1 | head -50)
                            COMPREPLY=($(compgen -W "${users}" -- "${cur}"))
                        fi
                    fi
                    return 0
                    ;;
                history)
                    if [ "${prev}" == "--days" ]; then
                        COMPREPLY=($(compgen -W "1 3 7 14 30" -- "${cur}"))
                    fi
                    return 0
                    ;;
            esac
            ;;
        *)
            # Handle --profile completion at any position
            if [ "${prev}" == "--profile" ]; then
                local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/slx"
                if [ -d "$config_dir/profiles.d" ]; then
                    local profiles=$(ls -1 "$config_dir/profiles.d"/*.env 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.env$//')
                    COMPREPLY=($(compgen -W "${profiles}" -- "${cur}"))
                fi
                return 0
            fi
            ;;
    esac
    
    return 0
}

# Register completion for slx
complete -F _slx_completion slx

# Alias completions
_complete_slx_alias() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    local cmd="${COMP_WORDS[0]}"
    
    case "$cmd" in
        sxs)
            # sxs = slx submit
            if [ "${COMP_CWORD}" -eq 1 ]; then
                COMPREPLY=($(compgen -f -X '!*.sbatch' -- "${cur}"))
            fi
            ;;
        sxl|sxt|sxk)
            # sxl = logs, sxt = tail, sxk = kill
            if [ "${COMP_CWORD}" -eq 1 ] && command -v squeue &> /dev/null; then
                local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
            else
                COMPREPLY=()
            fi
            ;;
        sxi)
            # sxi = slx info
            if [ "${COMP_CWORD}" -eq 1 ] && command -v squeue &> /dev/null; then
                local job_ids=$(squeue -u $USER -h -o "%i" 2>/dev/null)
                COMPREPLY=($(compgen -W "${job_ids}" -- "${cur}"))
            elif [ "${COMP_CWORD}" -eq 2 ]; then
                # If position 1 was a job ID, show flag options
                if [[ "${COMP_WORDS[1]}" =~ ^[0-9]+$ ]]; then
                    local options="--nodes -n"
                    COMPREPLY=($(compgen -W "${options}" -- "${cur}"))
                else
                    COMPREPLY=()
                fi
            else
                COMPREPLY=()
            fi
            ;;
        sxf)
            # sxf = find
            if [ "${COMP_CWORD}" -eq 1 ] && command -v squeue &> /dev/null; then
                local job_names=$(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u)
                COMPREPLY=($(compgen -W "${job_names}" -- "${cur}"))
            else
                COMPREPLY=()
            fi
            ;;
        sxps)
            # sxps = slx project submit
            if [ "${COMP_CWORD}" -eq 1 ]; then
                local workdir="${SLX_WORKDIR:-$HOME/workdir}"
                if [ -d "$workdir/projects" ]; then
                    local projects=$(ls -1 "$workdir/projects" 2>/dev/null)
                    COMPREPLY=($(compgen -W "${projects}" -- "${cur}"))
                else
                    COMPREPLY=()
                fi
            else
                COMPREPLY=()
            fi
            ;;
        *)
            # For unknown aliases, return empty
            COMPREPLY=()
            ;;
    esac
    return 0
}

complete -F _complete_slx_alias sxs sxl sxt sxk sxi sxf sxps 2>/dev/null || true

