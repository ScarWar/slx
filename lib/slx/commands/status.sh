#!/bin/bash
# slx status command
# Show job status summary

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

