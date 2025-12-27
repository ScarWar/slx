#!/bin/bash
# slx info command
# Show job information

# Show job information
show_info() {
    local JOB_ID=""
    local SHOW_NODES_ONLY=false
    
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
                    echo "Usage: slx info <job_id> [--nodes|-n]"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$JOB_ID" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: slx info <job_id> [--nodes|-n]"
        exit 1
    fi
    
    if [ "$SHOW_NODES_ONLY" = true ]; then
        local NODE_INFO=$(scontrol show job "$JOB_ID" 2>/dev/null | grep -E "^[[:space:]]*NodeList=")
        if [ -z "$NODE_INFO" ]; then
            echo -e "${YELLOW}No node information found for job $JOB_ID${NC}"
            echo "Job may not be running or may not have been allocated nodes yet."
            exit 1
        fi
        
        local NODES=$(echo "$NODE_INFO" | sed -n 's/^[[:space:]]*NodeList=\([^ ]*\).*/\1/p')
        
        if [ -z "$NODES" ]; then
            echo -e "${YELLOW}No nodes allocated for job $JOB_ID${NC}"
            exit 1
        fi
        
        echo -e "${BLUE}Nodes for job $JOB_ID:${NC}"
        echo "$NODES" | tr ',' '\n' | sed 's/^/  /'
    else
        echo -e "${BLUE}Job Information:${NC}"
        scontrol show job "$JOB_ID"
    fi
}

