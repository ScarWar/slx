#!/bin/bash
# Cluster management script for SLURM jobs
# Usage: ./cluster.sh <command> [options]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default log directory
LOG_DIR="${SLURM_LOG_DIR:-slurm/logs}"

# Print usage information
usage() {
    cat << EOF
Usage: ./cluster.sh <command> [options]

Commands:
    submit <script>          Submit a SLURM job script (e.g., jupyter.sbatch)
    list [--user USER]       List all running/pending jobs (default: current user)
    running                  List only running jobs
    pending                  List only pending jobs
    kill <job_id>            Cancel a specific job by ID
    killall                  Cancel all jobs for current user
    logs <job_id>            View logs for a specific job (both .out and .err)
    tail <job_id>            Tail logs for a running job
    info <job_id> [--nodes|-n]  Show detailed information about a job (use --nodes/-n to show only nodes)
    status                   Show summary of all user jobs
    history [--days N]       Show job history (default: 1 day)
    find <pattern>           Find jobs by name pattern
    clean                    Clean old log files (interactive)

Examples:
    ./cluster.sh submit jupyter.sbatch
    ./cluster.sh list
    ./cluster.sh logs 123456
    ./cluster.sh tail 123456
    ./cluster.sh kill 123456
    ./cluster.sh info 123456
    ./cluster.sh info 123456 --nodes
    ./cluster.sh status
EOF
}

# Submit a job
submit_job() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job script to submit${NC}"
        echo "Usage: ./cluster.sh submit <script>"
        exit 1
    fi
    
    if [ ! -f "$1" ]; then
        echo -e "${RED}Error: Script file '$1' not found${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Submitting job script: $1${NC}"
    JOB_ID=$(sbatch "$1" | grep -oP '\d+')
    
    if [ $? -eq 0 ] && [ -n "$JOB_ID" ]; then
        echo -e "${GREEN}Job submitted successfully!${NC}"
        echo -e "Job ID: ${GREEN}$JOB_ID${NC}"
        echo "View logs with: ./cluster.sh logs $JOB_ID"
        echo "Monitor with: ./cluster.sh tail $JOB_ID"
    else
        echo -e "${RED}Failed to submit job${NC}"
        exit 1
    fi
}

# List jobs
list_jobs() {
    local USER_ARG=""
    if [ "$1" == "--user" ] && [ -n "$2" ]; then
        USER_ARG="-u $2"
    elif [ -z "$USER_ARG" ]; then
        USER_ARG="-u $USER"
    fi
    
    echo -e "${BLUE}Current jobs:${NC}"
    squeue $USER_ARG -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R"
}

# List running jobs only
list_running() {
    echo -e "${BLUE}Running jobs:${NC}"
    squeue -u $USER -t RUNNING -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R"
}

# List pending jobs only
list_pending() {
    echo -e "${BLUE}Pending jobs:${NC}"
    squeue -u $USER -t PENDING -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R"
}

# Kill a specific job
kill_job() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: ./cluster.sh kill <job_id>"
        exit 1
    fi
    
    echo -e "${YELLOW}Cancelling job $1...${NC}"
    if scancel "$1"; then
        echo -e "${GREEN}Job $1 cancelled successfully${NC}"
    else
        echo -e "${RED}Failed to cancel job $1${NC}"
        exit 1
    fi
}

# Kill all user jobs
killall_jobs() {
    echo -e "${YELLOW}This will cancel ALL your jobs. Are you sure? (yes/no)${NC}"
    read -r response
    if [ "$response" = "yes" ]; then
        JOB_COUNT=$(squeue -u $USER -h | wc -l)
        if [ "$JOB_COUNT" -eq 0 ]; then
            echo -e "${BLUE}No jobs to cancel${NC}"
        else
            echo -e "${YELLOW}Cancelling $JOB_COUNT job(s)...${NC}"
            scancel -u $USER
            echo -e "${GREEN}All jobs cancelled${NC}"
        fi
    else
        echo "Cancelled"
    fi
}

# View job logs
view_logs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: ./cluster.sh logs <job_id>"
        exit 1
    fi
    
    JOB_ID=$1
    
    # Try to find log files
    # Check common log locations
    LOG_FILES=()
    
    # Check in slurm/logs/jupyter/ directory
    if [ -f "$LOG_DIR/jupyter/${JOB_ID}.log" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter/${JOB_ID}.log")
    fi
    if [ -f "$LOG_DIR/jupyter/${JOB_ID}.err" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter/${JOB_ID}.err")
    fi
    
    # Check in slurm/logs/ directory (flat structure)
    if [ -f "$LOG_DIR/jupyter_${JOB_ID}.out" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter_${JOB_ID}.out")
    fi
    if [ -f "$LOG_DIR/jupyter_${JOB_ID}.err" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter_${JOB_ID}.err")
    fi
    
    # Check SLURM default location
    if [ -f "slurm-${JOB_ID}.out" ]; then
        LOG_FILES+=("slurm-${JOB_ID}.out")
    fi
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        echo "Searched in:"
        echo "  - $LOG_DIR/jupyter/"
        echo "  - $LOG_DIR/"
        echo "  - Current directory"
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
        echo "Usage: ./cluster.sh tail <job_id>"
        exit 1
    fi
    
    JOB_ID=$1
    
    # Find log files
    LOG_FILES=()
    
    if [ -f "$LOG_DIR/jupyter/${JOB_ID}.log" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter/${JOB_ID}.log")
    fi
    if [ -f "$LOG_DIR/jupyter/${JOB_ID}.err" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter/${JOB_ID}.err")
    fi
    if [ -f "$LOG_DIR/jupyter_${JOB_ID}.out" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter_${JOB_ID}.out")
    fi
    if [ -f "$LOG_DIR/jupyter_${JOB_ID}.err" ]; then
        LOG_FILES+=("$LOG_DIR/jupyter_${JOB_ID}.err")
    fi
    
    if [ ${#LOG_FILES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found for job $JOB_ID${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Tailing logs for job $JOB_ID (Ctrl+C to exit)${NC}"
    tail -f "${LOG_FILES[@]}"
}

# Show job information
show_info() {
    local JOB_ID=""
    local SHOW_NODES_ONLY=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --nodes|-n)
                SHOW_NODES_ONLY=true
                shift
                ;;
            *)
                if [ -z "$JOB_ID" ]; then
                    JOB_ID="$1"
                else
                    echo -e "${RED}Error: Unexpected argument: $1${NC}"
                    echo "Usage: ./cluster.sh info <job_id> [--nodes|-n]"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$JOB_ID" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: ./cluster.sh info <job_id> [--nodes|-n]"
        exit 1
    fi
    
    if [ "$SHOW_NODES_ONLY" = true ]; then
        # Extract and display only node information
        # Match only "NodeList=" at the start of a word, not "ReqNodeList" or "ExcNodeList"
        local NODE_INFO=$(scontrol show job "$JOB_ID" 2>/dev/null | grep -E "^[[:space:]]*NodeList=")
        if [ -z "$NODE_INFO" ]; then
            echo -e "${YELLOW}No node information found for job $JOB_ID${NC}"
            echo "Job may not be running or may not have been allocated nodes yet."
            exit 1
        fi
        
        # Extract node list (format: NodeList=n-xxx or NodeList=n-xxx,n-yyy)
        # Match NodeList= at the start, capture everything after = until space or end
        local NODES=$(echo "$NODE_INFO" | sed -n 's/^[[:space:]]*NodeList=\([^ ]*\).*/\1/p')
        
        if [ -z "$NODES" ]; then
            echo -e "${YELLOW}No nodes allocated for job $JOB_ID${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Nodes for job $JOB_ID:${NC}"
        # Split comma-separated nodes and display one per line
        echo "$NODES" | tr ',' '\n' | sed 's/^/  /'
    else
        echo -e "${BLUE}Job Information:${NC}"
        scontrol show job "$JOB_ID"
    fi
}

# Show job status summary
show_status() {
    echo -e "${BLUE}=== Job Status Summary ===${NC}\n"
    
    RUNNING=$(squeue -u $USER -t RUNNING -h | wc -l)
    PENDING=$(squeue -u $USER -t PENDING -h | wc -l)
    TOTAL=$((RUNNING + PENDING))
    
    echo -e "Total jobs: ${GREEN}$TOTAL${NC}"
    echo -e "  Running: ${GREEN}$RUNNING${NC}"
    echo -e "  Pending: ${YELLOW}$PENDING${NC}"
    
    if [ "$TOTAL" -gt 0 ]; then
        echo ""
        list_jobs
    fi
}

# Show job history
show_history() {
    local DAYS=1
    if [ "$1" == "--days" ] && [ -n "$2" ]; then
        DAYS=$2
    fi
    
    echo -e "${BLUE}Job history (last $DAYS day(s)):${NC}"
    sacct -u $USER --starttime=$(date -d "$DAYS days ago" +%Y-%m-%d) \
          --format=JobID,JobName,Partition,State,ExitCode,Start,End,Elapsed,MaxRSS,ReqMem
}

# Find jobs by name pattern
find_jobs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a search pattern${NC}"
        echo "Usage: ./cluster.sh find <pattern>"
        exit 1
    fi
    
    echo -e "${BLUE}Jobs matching pattern '$1':${NC}"
    squeue -u $USER -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R" | grep -i "$1"
}

# Clean old log files
clean_logs() {
    echo -e "${YELLOW}This will help you clean old log files interactively.${NC}"
    echo "Enter the number of days to keep (logs older than this will be shown for deletion):"
    read -r days
    
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid number${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Finding log files older than $days days...${NC}"
    
    OLD_FILES=$(find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.out" -o -name "*.err" \) \
                -mtime +$days 2>/dev/null | head -20)
    
    if [ -z "$OLD_FILES" ]; then
        echo -e "${GREEN}No old log files found${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Found old log files:${NC}"
    echo "$OLD_FILES" | nl
    echo ""
    echo "Delete these files? (yes/no)"
    read -r response
    
    if [ "$response" = "yes" ]; then
        echo "$OLD_FILES" | xargs rm -f
        echo -e "${GREEN}Deleted old log files${NC}"
    else
        echo "Cancelled"
    fi
}

# Main command dispatcher
main() {
    case "$1" in
        submit)
            shift
            submit_job "$@"
            ;;
        list)
            shift
            list_jobs "$@"
            ;;
        running)
            list_running
            ;;
        pending)
            list_pending
            ;;
        kill)
            shift
            kill_job "$@"
            ;;
        killall)
            killall_jobs
            ;;
        logs)
            shift
            view_logs "$@"
            ;;
        tail)
            shift
            tail_logs "$@"
            ;;
        info)
            shift
            show_info "$@"
            ;;
        status)
            show_status
            ;;
        history)
            shift
            show_history "$@"
            ;;
        find)
            shift
            find_jobs "$@"
            ;;
        clean)
            clean_logs
            ;;
        help|--help|-h)
            usage
            ;;
        "")
            usage
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

