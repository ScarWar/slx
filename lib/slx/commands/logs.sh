#!/bin/bash
# slx logs commands
# View and tail job logs

# View job logs
view_logs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: slx logs <job_id>"
        exit 1
    fi
    
    JOB_ID=$1
    LOG_FILES=()
    
    # Check in various log locations
    # Project logs
    for proj_dir in "${SLX_WORKDIR}/projects"/*; do
        if [ -d "$proj_dir/logs" ]; then
            for f in "$proj_dir/logs"/*_${JOB_ID}.out "$proj_dir/logs"/*_${JOB_ID}.err; do
                [ -f "$f" ] && LOG_FILES+=("$f")
            done
        fi
    done
    
    # Check SLX log dir
    if [ -d "$SLX_LOG_DIR" ]; then
        for f in "$SLX_LOG_DIR"/*${JOB_ID}*.out "$SLX_LOG_DIR"/*${JOB_ID}*.err \
                 "$SLX_LOG_DIR"/*${JOB_ID}*.log; do
            [ -f "$f" ] && LOG_FILES+=("$f")
        done
    fi
    
    # Check current directory
    for f in slurm-${JOB_ID}.out *_${JOB_ID}.out *_${JOB_ID}.err; do
        [ -f "$f" ] && LOG_FILES+=("$f")
    done
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        echo "Searched in project logs, ${SLX_LOG_DIR}, and current directory"
        exit 1
    fi
    
    for log_file in "${LOG_FILES[@]}"; do
        echo -e "\n${BLUE}=== $(basename $log_file) ===${NC}"
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
    
    JOB_ID=$1
    LOG_FILES=()
    
    # Check in various log locations
    for proj_dir in "${SLX_WORKDIR}/projects"/*; do
        if [ -d "$proj_dir/logs" ]; then
            for f in "$proj_dir/logs"/*_${JOB_ID}.out "$proj_dir/logs"/*_${JOB_ID}.err; do
                [ -f "$f" ] && LOG_FILES+=("$f")
            done
        fi
    done
    
    if [ -d "$SLX_LOG_DIR" ]; then
        for f in "$SLX_LOG_DIR"/*${JOB_ID}*.out "$SLX_LOG_DIR"/*${JOB_ID}*.err; do
            [ -f "$f" ] && LOG_FILES+=("$f")
        done
    fi
    
    for f in slurm-${JOB_ID}.out *_${JOB_ID}.out *_${JOB_ID}.err; do
        [ -f "$f" ] && LOG_FILES+=("$f")
    done
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Tailing logs for job $JOB_ID (Ctrl+C to exit)${NC}"
    tail -f "${LOG_FILES[@]}"
}

