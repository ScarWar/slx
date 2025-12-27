#!/bin/bash
# slx kill commands
# Cancel jobs: single or all

# Kill a specific job
kill_job() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a job ID${NC}"
        echo "Usage: slx kill <job_id>"
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

