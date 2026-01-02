#!/bin/bash
# slx profile commands
# Compute profile management: new, list, show, delete

# Profile management commands
cmd_profile() {
    local subcmd="$1"
    shift || true
    
    case "$subcmd" in
        new)
            profile_new "$@"
            ;;
        list|ls)
            profile_list "$@"
            ;;
        show)
            profile_show "$@"
            ;;
        delete|rm)
            profile_delete "$@"
            ;;
        ""|help)
            echo -e "${BOLD}Profile commands:${NC}"
            echo "  slx profile new              Create a new compute profile"
            echo "  slx profile list             List all profiles"
            echo "  slx profile show <name>      Show profile details"
            echo "  slx profile delete <name>    Delete a profile"
            echo ""
            echo -e "${BOLD}About profiles:${NC}"
            echo "  Profiles store SLURM job defaults (partition, account, time, memory,"
            echo "  GPUs, node preferences, etc.) that can be selected when creating"
            echo "  new projects. Useful for different workload types:"
            echo ""
            echo "  Examples:"
            echo "    - 'cpu-small': CPU jobs with 4 cores, 16GB RAM"
            echo "    - 'gpu-large': Multi-GPU jobs with A100 nodes"
            echo "    - 'debug': Short time limit for quick tests"
            ;;
        *)
            echo -e "${RED}Unknown profile command: $subcmd${NC}"
            echo "Run 'slx profile help' for usage"
            exit 1
            ;;
    esac
}

# Create a new profile interactively
profile_new() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Create New Compute Profile${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    echo -e "${CYAN}Profiles store SLURM defaults for different workload types.${NC}"
    echo -e "${CYAN}Examples: 'cpu-small', 'gpu-large', 'debug'${NC}"
    echo ""
    
    # Profile name (required)
    local PROFILE_NAME=""
    while [ -z "$PROFILE_NAME" ]; do
        get_input "Profile name (required)" "" "PROFILE_NAME"
        if [ -z "$PROFILE_NAME" ]; then
            echo -e "${RED}Profile name is required${NC}"
            continue
        fi
        
        # Sanitize
        PROFILE_NAME=$(sanitize_profile_name "$PROFILE_NAME")
        
        if [ -z "$PROFILE_NAME" ]; then
            echo -e "${RED}Invalid profile name (use alphanumeric, dash, underscore)${NC}"
            continue
        fi
        
        # Check if exists
        if profile_exists "$PROFILE_NAME"; then
            echo -e "${YELLOW}Profile '${PROFILE_NAME}' already exists${NC}"
            echo -ne "${YELLOW}Overwrite? [y/N]${NC}: "
            read -r overwrite
            if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
                PROFILE_NAME=""
                continue
            fi
        fi
    done
    
    # Description (optional)
    local PROFILE_DESC=""
    get_input "Description (optional)" "" "PROFILE_DESC"
    
    echo ""
    echo -e "${CYAN}Configure SLURM defaults for this profile:${NC}"
    echo ""
    
    # Use current global config as baseline defaults
    local P_PARTITION="$SLX_PARTITION"
    local P_ACCOUNT="$SLX_ACCOUNT"
    local P_QOS="$SLX_QOS"
    local P_TIME="$SLX_TIME"
    local P_NODES="$SLX_NODES"
    local P_NTASKS="$SLX_NTASKS"
    local P_CPUS="$SLX_CPUS"
    local P_MEM="$SLX_MEM"
    local P_GPUS="$SLX_GPUS"
    local P_NODELIST="$SLX_NODELIST"
    local P_EXCLUDE="$SLX_EXCLUDE"
    
    # Cluster-aware selections
    select_partition "P_PARTITION" "$P_PARTITION"
    select_account "P_ACCOUNT" "$P_ACCOUNT"
    select_qos "P_QOS" "$P_QOS"
    
    echo ""
    echo -e "${CYAN}Resource limits:${NC}"
    get_input "Time (minutes)" "$P_TIME" "P_TIME"
    get_input "Nodes" "$P_NODES" "P_NODES"
    get_input "Tasks" "$P_NTASKS" "P_NTASKS"
    get_input "CPUs per task" "$P_CPUS" "P_CPUS"
    get_input "Memory (MB)" "$P_MEM" "P_MEM"
    get_input "GPUs (leave empty for none)" "$P_GPUS" "P_GPUS"
    
    echo ""
    echo -e "${CYAN}Node preferences:${NC}"
    select_nodes "P_NODELIST" "$P_NODELIST" \
        "Preferred Nodes (NodeList)" \
        "Select nodes to prefer for jobs using this profile:"
    select_nodes "P_EXCLUDE" "$P_EXCLUDE" \
        "Exclude Nodes" \
        "Select nodes to exclude for jobs using this profile:"
    
    echo ""
    echo -e "${BLUE}Profile Summary:${NC}"
    echo -e "  Name:        ${GREEN}${PROFILE_NAME}${NC}"
    [ -n "$PROFILE_DESC" ] && echo -e "  Description: ${PROFILE_DESC}"
    echo -e "  Partition:   ${P_PARTITION:-<not set>}"
    echo -e "  Account:     ${P_ACCOUNT:-<not set>}"
    echo -e "  QoS:         ${P_QOS:-<not set>}"
    echo -e "  Time:        ${P_TIME} min"
    echo -e "  Nodes:       ${P_NODES}"
    echo -e "  CPUs:        ${P_CPUS}"
    echo -e "  Memory:      ${P_MEM} MB"
    echo -e "  GPUs:        ${P_GPUS:-<none>}"
    echo -e "  NodeList:    ${P_NODELIST:-<none>}"
    echo -e "  Exclude:     ${P_EXCLUDE:-<none>}"
    echo ""
    
    echo -ne "${YELLOW}Save this profile? [Y/n]${NC}: "
    read -r save
    if [ "$save" = "n" ] || [ "$save" = "N" ]; then
        echo -e "${YELLOW}Profile not saved${NC}"
        return 1
    fi
    
    # Set profile variables and save
    SLX_PROFILE_NAME="$PROFILE_NAME"
    SLX_PROFILE_DESC="$PROFILE_DESC"
    SLX_PROFILE_PARTITION="$P_PARTITION"
    SLX_PROFILE_ACCOUNT="$P_ACCOUNT"
    SLX_PROFILE_QOS="$P_QOS"
    SLX_PROFILE_TIME="$P_TIME"
    SLX_PROFILE_NODES="$P_NODES"
    SLX_PROFILE_NTASKS="$P_NTASKS"
    SLX_PROFILE_CPUS="$P_CPUS"
    SLX_PROFILE_MEM="$P_MEM"
    SLX_PROFILE_GPUS="$P_GPUS"
    SLX_PROFILE_NODELIST="$P_NODELIST"
    SLX_PROFILE_EXCLUDE="$P_EXCLUDE"
    
    save_profile "$PROFILE_NAME"
    
    echo ""
    echo -e "${GREEN}Profile '${PROFILE_NAME}' created successfully!${NC}"
    echo -e "Use it when creating projects: ${CYAN}slx project new --profile ${PROFILE_NAME}${NC}"
}

# List all profiles
profile_list() {
    local profiles=($(list_profiles))
    
    if [ ${#profiles[@]} -eq 0 ]; then
        echo -e "${YELLOW}No profiles found${NC}"
        echo "Create one with: slx profile new"
        return 0
    fi
    
    echo -e "${BLUE}Available compute profiles:${NC}"
    echo ""
    
    for p in "${profiles[@]}"; do
        local desc=""
        if load_profile "$p" 2>/dev/null; then
            [ -n "$SLX_PROFILE_DESC" ] && desc=" - ${SLX_PROFILE_DESC}"
        fi
        echo -e "  ${GREEN}${p}${NC}${desc}"
    done
    echo ""
    echo -e "Show details: ${CYAN}slx profile show <name>${NC}"
}

# Show profile details
profile_show() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Please provide a profile name${NC}"
        echo "Usage: slx profile show <name>"
        echo ""
        echo "Available profiles:"
        profile_list
        return 1
    fi
    
    if ! profile_exists "$name"; then
        echo -e "${RED}Error: Profile '${name}' not found${NC}"
        echo ""
        echo "Available profiles:"
        profile_list
        return 1
    fi
    
    print_profile_summary "$name"
    echo ""
    echo -e "  File: ${CYAN}${SLX_PROFILES_DIR}/${name}.env${NC}"
}

# Delete a profile
profile_delete() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Please provide a profile name${NC}"
        echo "Usage: slx profile delete <name>"
        echo ""
        echo "Available profiles:"
        profile_list
        return 1
    fi
    
    if ! profile_exists "$name"; then
        echo -e "${RED}Error: Profile '${name}' not found${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}About to delete profile: ${name}${NC}"
    echo -ne "${YELLOW}Are you sure? [y/N]${NC}: "
    read -r confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        delete_profile "$name"
    else
        echo -e "${YELLOW}Cancelled${NC}"
    fi
}

