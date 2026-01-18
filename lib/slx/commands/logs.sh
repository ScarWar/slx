#!/bin/bash
# slx logs commands
# View and tail job logs

# ============================================
# Helper: Resolve log paths from job metadata
# ============================================

# Resolve log file paths from SLURM job metadata (scontrol)
# Usage: resolve_job_log_paths <job_id>
# Sets: RESOLVED_LOG_FILES array with absolute paths to existing log files
# Returns: 0 if resolved files found, 1 otherwise
resolve_job_log_paths() {
    local job_id="$1"
    RESOLVED_LOG_FILES=()
    
    # Check if scontrol is available
    if ! has_cmd scontrol; then
        return 1
    fi
    
    # Get job info from scontrol (one-line format for easier parsing)
    local job_info
    job_info=$(scontrol show job -o "$job_id" 2>/dev/null) || return 1
    
    # Check if we got valid output
    if [ -z "$job_info" ] || [[ "$job_info" == *"Invalid job id"* ]]; then
        return 1
    fi
    
    # Extract fields from job info
    # Format: Key=Value Key2=Value2 ...
    local stdout_path stderr_path work_dir job_name
    
    # Extract StdOut path
    stdout_path=$(echo "$job_info" | grep -oP 'StdOut=\K[^ ]+' || true)
    
    # Extract StdErr path
    stderr_path=$(echo "$job_info" | grep -oP 'StdErr=\K[^ ]+' || true)
    
    # Extract WorkDir for resolving relative paths
    work_dir=$(echo "$job_info" | grep -oP 'WorkDir=\K[^ ]+' || true)
    
    # Extract JobName for %x expansion
    job_name=$(echo "$job_info" | grep -oP 'JobName=\K[^ ]+' || true)
    
    # If no stdout/stderr paths found, return failure
    if [ -z "$stdout_path" ] && [ -z "$stderr_path" ]; then
        return 1
    fi
    
    # Function to expand SLURM filename patterns
    # Handles: %j (job id), %x (job name), %% (literal %)
    expand_slurm_pattern() {
        local pattern="$1"
        local jid="$2"
        local jname="$3"
        
        # First, replace %% with a placeholder to preserve literal %
        local result="${pattern//%%/__PERCENT_PLACEHOLDER__}"
        
        # Replace %j with job id
        result="${result//%j/$jid}"
        
        # Replace %x with job name
        result="${result//%x/$jname}"
        
        # Restore literal % from placeholder
        result="${result//__PERCENT_PLACEHOLDER__/%}"
        
        echo "$result"
    }
    
    # Function to resolve path (make absolute if relative)
    resolve_path() {
        local path="$1"
        local base_dir="$2"
        
        # If path is already absolute, return as-is
        if [[ "$path" == /* ]]; then
            echo "$path"
        elif [ -n "$base_dir" ]; then
            # Resolve relative path against base dir
            echo "${base_dir}/${path}"
        else
            # No base dir, return as-is (might be relative to cwd)
            echo "$path"
        fi
    }
    
    # Process stdout path
    if [ -n "$stdout_path" ]; then
        stdout_path=$(expand_slurm_pattern "$stdout_path" "$job_id" "$job_name")
        stdout_path=$(resolve_path "$stdout_path" "$work_dir")
        if [ -f "$stdout_path" ]; then
            RESOLVED_LOG_FILES+=("$stdout_path")
        fi
    fi
    
    # Process stderr path
    if [ -n "$stderr_path" ]; then
        stderr_path=$(expand_slurm_pattern "$stderr_path" "$job_id" "$job_name")
        stderr_path=$(resolve_path "$stderr_path" "$work_dir")
        # Only add if it's different from stdout (avoid duplicates)
        if [ -f "$stderr_path" ] && [ "$stderr_path" != "$stdout_path" ]; then
            RESOLVED_LOG_FILES+=("$stderr_path")
        fi
    fi
    
    # Return success if we found any files
    if [ ${#RESOLVED_LOG_FILES[@]} -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# ============================================
# Fallback: Search for logs by pattern
# ============================================

# Search for log files using filename heuristics
# Usage: search_log_files_by_pattern <job_id>
# Sets: SEARCHED_LOG_FILES array with found log file paths
search_log_files_by_pattern() {
    local job_id="$1"
    SEARCHED_LOG_FILES=()
    
    # Check in various log locations
    # Project logs
    for proj_dir in "${SLX_WORKDIR}/projects"/*; do
        if [ -d "$proj_dir/logs" ]; then
            for f in "$proj_dir/logs"/*_${job_id}.out "$proj_dir/logs"/*_${job_id}.err; do
                [ -f "$f" ] && SEARCHED_LOG_FILES+=("$f")
            done
        fi
    done
    
    # Check SLX log dir
    if [ -d "$SLX_LOG_DIR" ]; then
        for f in "$SLX_LOG_DIR"/*${job_id}*.out "$SLX_LOG_DIR"/*${job_id}*.err \
                 "$SLX_LOG_DIR"/*${job_id}*.log; do
            [ -f "$f" ] && SEARCHED_LOG_FILES+=("$f")
        done
    fi
    
    # Check current directory
    for f in slurm-${job_id}.out *_${job_id}.out *_${job_id}.err; do
        [ -f "$f" ] && SEARCHED_LOG_FILES+=("$f")
    done
}

# ============================================
# Main Commands
# ============================================

# View job logs
view_logs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: slx logs <job_id>"
        exit 1
    fi
    
    local JOB_ID="$1"
    local LOG_FILES=()
    
    # Try to resolve log paths from SLURM job metadata first
    if resolve_job_log_paths "$JOB_ID"; then
        LOG_FILES=("${RESOLVED_LOG_FILES[@]}")
    else
        # Fall back to pattern-based search
        search_log_files_by_pattern "$JOB_ID"
        LOG_FILES=("${SEARCHED_LOG_FILES[@]}")
    fi
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        echo "Searched in project logs, ${SLX_LOG_DIR}, and current directory"
        exit 1
    fi
    
    for log_file in "${LOG_FILES[@]}"; do
        echo -e "\n${BLUE}=== $(basename "$log_file") ===${NC}"
        cat "$log_file"
    done
}

# Tail job logs
tail_logs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: slx tail <job_id>"
        exit 1
    fi
    
    local JOB_ID="$1"
    local LOG_FILES=()
    
    # Try to resolve log paths from SLURM job metadata first
    if resolve_job_log_paths "$JOB_ID"; then
        LOG_FILES=("${RESOLVED_LOG_FILES[@]}")
    else
        # Fall back to pattern-based search
        search_log_files_by_pattern "$JOB_ID"
        LOG_FILES=("${SEARCHED_LOG_FILES[@]}")
    fi
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Tailing logs for job $JOB_ID (Ctrl+C to exit)${NC}"
    tail -f "${LOG_FILES[@]}"
}
