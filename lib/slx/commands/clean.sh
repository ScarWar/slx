#!/bin/bash
# slx clean command
# Clean old log files

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
    
    # Search in project logs and SLX log dir
    local SEARCH_DIRS=("${SLX_WORKDIR}/projects" "$SLX_LOG_DIR")
    local OLD_FILES=""
    
    for dir in "${SEARCH_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            OLD_FILES+=$(find "$dir" -type f \( -name "*.log" -o -name "*.out" -o -name "*.err" \) \
                        -mtime +$days 2>/dev/null)
            OLD_FILES+=$'\n'
        fi
    done
    
    OLD_FILES=$(echo "$OLD_FILES" | grep -v '^$' | head -20)
    
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

