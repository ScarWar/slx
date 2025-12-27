#!/bin/bash
# slx init command
# Initialize slx configuration

# Initialize configuration
cmd_init() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}slx - SLurm eXtended Setup${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check if config already exists
    if [ -f "$SLX_CONFIG_FILE" ]; then
        echo -e "${YELLOW}Configuration already exists at: ${SLX_CONFIG_FILE}${NC}"
        echo -ne "${YELLOW}Update existing configuration? [y/N]${NC}: "
        read -r update
        if [ "$update" != "y" ] && [ "$update" != "Y" ]; then
            echo -e "${YELLOW}Keeping existing configuration${NC}"
            return 0
        fi
        # Load existing config as defaults
        load_config
    fi
    
    echo -e "${CYAN}Let's configure slx for your cluster.${NC}"
    echo ""
    
    # WORKDIR - try to detect large mounts
    local suggested_workdir="$SLX_WORKDIR"
    if [ -z "$suggested_workdir" ] || [ "$suggested_workdir" = "$DEFAULT_WORKDIR" ]; then
        # Try common large mount locations
        for dir in "/scratch/$USER" "/data/$USER" "/work/$USER" "$HOME/workdir"; do
            if [ -d "$(dirname "$dir")" ]; then
                suggested_workdir="$dir"
                break
            fi
        done
    fi
    
    get_input "WORKDIR (base directory for projects)" "$suggested_workdir" "SLX_WORKDIR"
    SLX_WORKDIR=$(eval echo "$SLX_WORKDIR")  # Expand variables
    
    # Create workdir if it doesn't exist
    if [ ! -d "$SLX_WORKDIR" ]; then
        echo -ne "${YELLOW}Directory does not exist. Create it? [Y/n]${NC}: "
        read -r create_dir
        if [ "$create_dir" != "n" ] && [ "$create_dir" != "N" ]; then
            mkdir -p "$SLX_WORKDIR"
            mkdir -p "$SLX_WORKDIR/projects"
            echo -e "${GREEN}Created: ${SLX_WORKDIR}${NC}"
        fi
    else
        mkdir -p "$SLX_WORKDIR/projects"
    fi
    
    echo ""
    
    # Show cluster resource summary
    show_cluster_resources
    
    echo -e "${CYAN}SLURM job defaults - select from available options:${NC}"
    echo ""
    
    # Cluster-aware selections for partition/account/QoS
    select_partition "SLX_PARTITION" "$SLX_PARTITION"
    select_account "SLX_ACCOUNT" "$SLX_ACCOUNT"
    select_qos "SLX_QOS" "$SLX_QOS"
    
    echo ""
    echo -e "${CYAN}Resource limits:${NC}"
    get_input "Default time limit (minutes)" "$SLX_TIME" "SLX_TIME"
    get_input "Default nodes" "$SLX_NODES" "SLX_NODES"
    get_input "Default tasks" "$SLX_NTASKS" "SLX_NTASKS"
    get_input "Default CPUs per task" "$SLX_CPUS" "SLX_CPUS"
    get_input "Default memory (MB)" "$SLX_MEM" "SLX_MEM"
    get_input "Default GPUs (leave empty for none)" "$SLX_GPUS" "SLX_GPUS"
    
    echo ""
    echo -e "${CYAN}Node preferences:${NC}"
    
    # Multi-select for preferred nodes (nodelist)
    select_nodes "SLX_NODELIST" "$SLX_NODELIST" \
        "Preferred Nodes (NodeList)" \
        "Select nodes to prefer for jobs (optional):"
    
    # Multi-select for excluded nodes
    select_nodes "SLX_EXCLUDE" "$SLX_EXCLUDE" \
        "Exclude Nodes" \
        "Select nodes to exclude from jobs (optional):"
    
    # Set log directory
    SLX_LOG_DIR="${SLX_WORKDIR}/slurm/logs"
    mkdir -p "$SLX_LOG_DIR"
    
    echo ""
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo -e "  WORKDIR:   ${GREEN}${SLX_WORKDIR}${NC}"
    echo -e "  Partition: ${GREEN}${SLX_PARTITION:-<not set>}${NC}"
    echo -e "  Account:   ${GREEN}${SLX_ACCOUNT:-<not set>}${NC}"
    echo -e "  QoS:       ${GREEN}${SLX_QOS:-<not set>}${NC}"
    echo -e "  Time:      ${GREEN}${SLX_TIME} min${NC}"
    echo -e "  Nodes:     ${GREEN}${SLX_NODES}${NC}"
    echo -e "  CPUs:      ${GREEN}${SLX_CPUS}${NC}"
    echo -e "  Memory:    ${GREEN}${SLX_MEM} MB${NC}"
    echo -e "  GPUs:      ${GREEN}${SLX_GPUS:-<none>}${NC}"
    echo -e "  NodeList:  ${GREEN}${SLX_NODELIST:-<none>}${NC}"
    echo -e "  Exclude:   ${GREEN}${SLX_EXCLUDE:-<none>}${NC}"
    echo ""
    
    echo -ne "${YELLOW}Save this configuration? [Y/n]${NC}: "
    read -r save
    if [ "$save" != "n" ] && [ "$save" != "N" ]; then
        save_config
        echo ""
        echo -e "${GREEN}slx is now configured!${NC}"
        echo -e "Create a new project with: ${CYAN}slx project new${NC}"
    else
        echo -e "${YELLOW}Configuration not saved${NC}"
    fi
}

