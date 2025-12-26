# Zsh completion for cluster.sh
# Add to your ~/.zshrc:
#   fpath=(/path/to/directory $fpath)
#   autoload -U compinit && compinit
# Or source directly:
#   source /path/to/cluster-completion.zsh

_cluster() {
    local -a commands
    commands=(
        'submit:Submit a SLURM job script'
        'list:List all running/pending jobs'
        'running:List only running jobs'
        'pending:List only pending jobs'
        'kill:Cancel a specific job by ID'
        'killall:Cancel all jobs for current user'
        'logs:View logs for a specific job'
        'tail:Tail logs for a running job'
        'info:Show detailed information about a job'
        'status:Show summary of all user jobs'
        'history:Show job history'
        'find:Find jobs by name pattern'
        'clean:Clean old log files'
        'help:Show help message'
    )
    
    _describe 'command' commands
    
    case $words[2] in
        submit)
            _files -g '*.sbatch'
            ;;
        logs|tail|kill)
            if command -v squeue &> /dev/null; then
                local job_ids=($(squeue -u $USER -h -o "%i" 2>/dev/null))
                _describe 'job-id' job_ids
            fi
            ;;
        info)
            if command -v squeue &> /dev/null; then
                local job_ids=($(squeue -u $USER -h -o "%i" 2>/dev/null))
                local options=('--nodes:Show only nodes' '-n:Show only nodes')
                _describe 'job-id' job_ids
                _describe 'option' options
            fi
            ;;
        list)
            _arguments '--user[Specify user]'
            ;;
        history)
            _arguments '--days[Number of days]'
            ;;
        find)
            if command -v squeue &> /dev/null; then
                local job_names=($(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u))
                _describe 'job-name' job_names
            fi
            ;;
    esac
}

compdef _cluster cluster.sh cluster

# Completion for aliases
_cluster_submit() {
    _files -g '*.sbatch'
}

_cluster_job_id() {
    if command -v squeue &> /dev/null; then
        local job_ids=($(squeue -u $USER -h -o "%i" 2>/dev/null))
        _describe 'job-id' job_ids
    fi
}

_cluster_find() {
    if command -v squeue &> /dev/null; then
        local job_names=($(squeue -u $USER -h -o "%j" 2>/dev/null | sort -u))
        _describe 'job-name' job_names
    fi
}

compdef _cluster_submit cs
compdef _cluster_job_id cl ct ck ci
compdef _cluster_find cf


