#!/bin/bash
# slx history command
# Show job history

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

