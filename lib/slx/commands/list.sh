#!/bin/bash
# slx list commands
# List jobs: all, running, pending

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

