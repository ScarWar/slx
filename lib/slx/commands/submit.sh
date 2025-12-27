#!/bin/bash
# slx submit command
# Submit a job script

# Submit a job
submit_job() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job script to submit${NC}"
        echo "Usage: slx submit <script>"
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
        echo "View logs with: slx logs $JOB_ID"
        echo "Monitor with: slx tail $JOB_ID"
    else
        echo -e "${RED}Failed to submit job${NC}"
        exit 1
    fi
}

