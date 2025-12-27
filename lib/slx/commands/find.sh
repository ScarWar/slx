#!/bin/bash
# slx find command
# Find jobs by pattern

# Find jobs by name pattern
find_jobs() {
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a search pattern${NC}"
        echo "Usage: slx find <pattern>"
        exit 1
    fi
    
    echo -e "${BLUE}Jobs matching pattern '$1':${NC}"
    squeue -u $USER -o "%.18i %.9P %.20j %.8u %.2t %.10M %.6D %R" | grep -i "$1"
}

