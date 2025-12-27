#!/bin/bash
# slx (SLurm eXtended) Common Functions
# Shared functionality for all slx commands

# Tool info
SLX_VERSION="1.0.0"
SLX_NAME="slx"

# XDG directories (with fallbacks)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# slx-specific paths
SLX_CONFIG_DIR="${XDG_CONFIG_HOME}/${SLX_NAME}"
SLX_CONFIG_FILE="${SLX_CONFIG_DIR}/config.env"
SLX_DATA_DIR="${XDG_DATA_HOME}/${SLX_NAME}"

# Check if terminal supports colors
supports_colors() {
    # Check if stdout is a terminal
    [ -t 1 ] || return 1
    # Check if TERM is set and not "dumb"
    [ -n "$TERM" ] && [ "$TERM" != "dumb" ] || return 1
    # Check if NO_COLOR is set (respect NO_COLOR env var)
    [ -z "$NO_COLOR" ] || return 1
    return 0
}

# Colors for output (using $'...' for portability)
if supports_colors; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    NC=$'\033[0m' # No Color
else
    # No colors if terminal doesn't support them
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    BOLD=""
    NC=""
fi

# Default configuration values
DEFAULT_WORKDIR="${HOME}/workdir"
DEFAULT_PARTITION=""
DEFAULT_ACCOUNT=""
DEFAULT_QOS="normal"
DEFAULT_TIME="1440"
DEFAULT_NODES="1"
DEFAULT_NTASKS="1"
DEFAULT_CPUS="4"
DEFAULT_MEM="50000"
DEFAULT_GPUS=""
DEFAULT_EXCLUDE=""
DEFAULT_NODELIST=""

# Runtime configuration (loaded from config.env)
SLX_WORKDIR=""
SLX_PARTITION=""
SLX_ACCOUNT=""
SLX_QOS=""
SLX_TIME=""
SLX_NODES=""
SLX_NTASKS=""
SLX_CPUS=""
SLX_MEM=""
SLX_GPUS=""
SLX_EXCLUDE=""
SLX_NODELIST=""
SLX_LOG_DIR=""

# Load configuration from config.env if it exists
load_config() {
    if [ -f "$SLX_CONFIG_FILE" ]; then
        # Source the config file safely
        set -a
        source "$SLX_CONFIG_FILE"
        set +a
    fi
    
    # Apply loaded values or defaults
    SLX_WORKDIR="${SLX_WORKDIR:-$DEFAULT_WORKDIR}"
    SLX_PARTITION="${SLX_PARTITION:-$DEFAULT_PARTITION}"
    SLX_ACCOUNT="${SLX_ACCOUNT:-$DEFAULT_ACCOUNT}"
    SLX_QOS="${SLX_QOS:-$DEFAULT_QOS}"
    SLX_TIME="${SLX_TIME:-$DEFAULT_TIME}"
    SLX_NODES="${SLX_NODES:-$DEFAULT_NODES}"
    SLX_NTASKS="${SLX_NTASKS:-$DEFAULT_NTASKS}"
    SLX_CPUS="${SLX_CPUS:-$DEFAULT_CPUS}"
    SLX_MEM="${SLX_MEM:-$DEFAULT_MEM}"
    SLX_GPUS="${SLX_GPUS:-$DEFAULT_GPUS}"
    SLX_EXCLUDE="${SLX_EXCLUDE:-$DEFAULT_EXCLUDE}"
    SLX_NODELIST="${SLX_NODELIST:-$DEFAULT_NODELIST}"
    SLX_LOG_DIR="${SLX_LOG_DIR:-${SLX_WORKDIR}/slurm/logs}"
}

# Save configuration to config.env
save_config() {
    mkdir -p "$SLX_CONFIG_DIR"
    cat > "$SLX_CONFIG_FILE" << EOF
# slx configuration file
# Generated on $(date)

# WORKDIR: Base directory for projects (use a large mount if available)
SLX_WORKDIR="${SLX_WORKDIR}"

# Default SLURM job settings
SLX_PARTITION="${SLX_PARTITION}"
SLX_ACCOUNT="${SLX_ACCOUNT}"
SLX_QOS="${SLX_QOS}"
SLX_TIME="${SLX_TIME}"
SLX_NODES="${SLX_NODES}"
SLX_NTASKS="${SLX_NTASKS}"
SLX_CPUS="${SLX_CPUS}"
SLX_MEM="${SLX_MEM}"
SLX_GPUS="${SLX_GPUS}"
SLX_EXCLUDE="${SLX_EXCLUDE}"
SLX_NODELIST="${SLX_NODELIST}"

# Log directory
SLX_LOG_DIR="${SLX_LOG_DIR}"
EOF
    echo -e "${GREEN}Configuration saved to: ${SLX_CONFIG_FILE}${NC}"
}

# Get user input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        echo -ne "${CYAN}$prompt${NC} ${YELLOW}[$default]${NC}: "
    else
        echo -ne "${CYAN}$prompt${NC}: "
    fi
    
    read -r input
    
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

# ============================================
# Template Processing
# ============================================

# Find template directory (checks multiple locations)
find_template_dir() {
    # Check if running from repo
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_templates="${script_dir}/../../templates"
    if [ -d "$repo_templates" ]; then
        echo "$repo_templates"
        return 0
    fi
    
    # Check installed location
    local installed_templates="${SLX_DATA_DIR}/templates"
    if [ -d "$installed_templates" ]; then
        echo "$installed_templates"
        return 0
    fi
    
    # Fallback: check if templates are in same dir as script
    if [ -d "${script_dir}/templates" ]; then
        echo "${script_dir}/templates"
        return 0
    fi
    
    return 1
}

# Simple template processor (handles {{VAR}} and {{#VAR}}...{{/VAR}})
# Usage: process_template template_file var1=value1 var2=value2 ...
process_template() {
    local template_file="$1"
    shift
    
    if [ ! -f "$template_file" ]; then
        echo -e "${RED}Error: Template file not found: ${template_file}${NC}" >&2
        return 1
    fi
    
    # Build associative array of variables from arguments
    declare -A vars
    for arg in "$@"; do
        if [[ "$arg" =~ ^([^=]+)=(.+)$ ]]; then
            vars["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
        fi
    done
    
    # Read template content
    local content=$(cat "$template_file")
    
    # Process conditional blocks {{#VAR}}...{{/VAR}}
    # Handle both single-line and multi-line blocks
    for var_name in "${!vars[@]}"; do
        # Pattern to match: {{#VAR}}...{{/VAR}}
        # Use a loop to handle all occurrences
        while true; do
            # Try to find the block pattern
            local pattern_start="{{#${var_name}}}"
            local pattern_end="{{/${var_name}}}"
            local start_pos="${content%%$pattern_start*}"
            
            # If pattern not found, break
            if [ "$start_pos" = "$content" ]; then
                break
            fi
            
            # Extract content after the start pattern
            local after_start="${content#*$pattern_start}"
            local end_pos="${after_start%%$pattern_end*}"
            
            # If end pattern not found, break (malformed template)
            if [ "$end_pos" = "$after_start" ]; then
                break
            fi
            
            # Extract the block content
            local block_content="$end_pos"
            local full_block="${pattern_start}${block_content}${pattern_end}"
            
            # Check if variable is set and non-empty
            if [ -n "${vars[$var_name]}" ]; then
                # Replace variables in block content
                local processed_block="$block_content"
                for vname in "${!vars[@]}"; do
                    processed_block="${processed_block//\{\{${vname}\}\}/${vars[$vname]}}"
                done
                # Replace the full block with processed content
                content="${content//$full_block/$processed_block}"
            else
                # Remove the entire block (including newlines if present)
                content="${content//$full_block/}"
            fi
        done
    done
    
    # Process simple variable substitutions {{VAR}} (not in conditionals)
    for var_name in "${!vars[@]}"; do
        content="${content//\{\{${var_name}\}\}/${vars[$var_name]}}"
    done
    
    echo "$content"
}

# ============================================
# SLURM Query Helpers (best-effort)
# ============================================

# Check if a command is available
has_cmd() {
    command -v "$1" &>/dev/null
}

# Detect which menu tool is available
detect_menu_tool() {
    if has_cmd whiptail; then
        echo "whiptail"
    elif has_cmd dialog; then
        echo "dialog"
    else
        echo "text"
    fi
}

# Query available partitions from SLURM
slurm_query_partitions() {
    if ! has_cmd sinfo; then
        return 1
    fi
    sinfo -h -o "%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$'
}

# Query available accounts for current user
slurm_query_accounts() {
    if ! has_cmd sacctmgr; then
        return 1
    fi
    sacctmgr -n -P show assoc where user="$USER" format=account 2>/dev/null | sort -u | grep -v '^$'
}

# Query available QoS for current user
slurm_query_qos() {
    if ! has_cmd sacctmgr; then
        return 1
    fi
    sacctmgr -n -P show assoc where user="$USER" format=qos 2>/dev/null | tr ',' '\n' | sort -u | grep -v '^$'
}

# Query available nodes with state and partition info
# Returns: nodename|state|partition
slurm_query_nodes() {
    if ! has_cmd sinfo; then
        return 1
    fi
    sinfo -N -h -o "%N|%T|%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$'
}

# Query just node names (simple list)
slurm_query_node_names() {
    if ! has_cmd sinfo; then
        return 1
    fi
    sinfo -N -h -o "%N" 2>/dev/null | sort -u | grep -v '^$'
}

# ============================================
# Interactive Menu Helpers
# ============================================

# Single-select menu using whiptail/dialog or fallback
# Usage: menu_select_one "title" "prompt" result_var option1 option2 ...
menu_select_one() {
    local title="$1"
    local prompt="$2"
    local result_var="$3"
    shift 3
    local options=("$@")
    
    if [ ${#options[@]} -eq 0 ]; then
        eval "$result_var=''"
        return 1
    fi
    
    local menu_tool=$(detect_menu_tool)
    
    case "$menu_tool" in
        whiptail|dialog)
            local menu_items=()
            local i=1
            for opt in "${options[@]}"; do
                menu_items+=("$opt" "$i")
                ((i++))
            done
            
            local choice
            choice=$($menu_tool --title "$title" --menu "$prompt" 20 60 12 "${menu_items[@]}" 3>&1 1>&2 2>&3)
            local exit_code=$?
            
            if [ $exit_code -eq 0 ] && [ -n "$choice" ]; then
                eval "$result_var='$choice'"
            else
                eval "$result_var=''"
            fi
            ;;
        text)
            echo ""
            echo -e "${CYAN}${title}${NC}"
            echo -e "${prompt}"
            echo ""
            local i=1
            for opt in "${options[@]}"; do
                echo -e "  ${YELLOW}$i)${NC} $opt"
                ((i++))
            done
            echo -e "  ${YELLOW}0)${NC} Skip / Enter manually"
            echo ""
            echo -ne "${CYAN}Select [1-${#options[@]}, 0 to skip]:${NC} "
            read -r selection
            
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#options[@]} ]; then
                eval "$result_var='${options[$((selection-1))]}'"
            else
                eval "$result_var=''"
            fi
            ;;
    esac
}

# Multi-select menu using whiptail/dialog or fallback
# Usage: menu_select_many "title" "prompt" result_var option1 option2 ...
# Result is comma-separated list
menu_select_many() {
    local title="$1"
    local prompt="$2"
    local result_var="$3"
    shift 3
    local options=("$@")
    
    if [ ${#options[@]} -eq 0 ]; then
        eval "$result_var=''"
        return 1
    fi
    
    local menu_tool=$(detect_menu_tool)
    
    case "$menu_tool" in
        whiptail|dialog)
            local menu_items=()
            for opt in "${options[@]}"; do
                # Format: tag item status (OFF by default)
                menu_items+=("$opt" "" "OFF")
            done
            
            local choices
            choices=$($menu_tool --title "$title" --checklist "$prompt" 22 70 15 "${menu_items[@]}" 3>&1 1>&2 2>&3)
            local exit_code=$?
            
            if [ $exit_code -eq 0 ] && [ -n "$choices" ]; then
                # Remove quotes and convert spaces to commas
                local cleaned=$(echo "$choices" | tr -d '"' | tr ' ' ',')
                eval "$result_var='$cleaned'"
            else
                eval "$result_var=''"
            fi
            ;;
        text)
            echo ""
            echo -e "${CYAN}${title}${NC}"
            echo -e "${prompt}"
            echo ""
            local i=1
            for opt in "${options[@]}"; do
                echo -e "  ${YELLOW}$i)${NC} $opt"
                ((i++))
            done
            echo ""
            echo -e "${CYAN}Enter selection (comma-separated numbers, ranges like 1-5, or 0 to skip):${NC}"
            echo -ne "Selection: "
            read -r selection
            
            if [ "$selection" = "0" ] || [ -z "$selection" ]; then
                eval "$result_var=''"
            else
                # Parse ranges and individual numbers
                local selected=()
                IFS=',' read -ra parts <<< "$selection"
                for part in "${parts[@]}"; do
                    part=$(echo "$part" | tr -d ' ')
                    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                        # Range
                        local start="${BASH_REMATCH[1]}"
                        local end="${BASH_REMATCH[2]}"
                        for ((j=start; j<=end; j++)); do
                            if [ "$j" -ge 1 ] && [ "$j" -le ${#options[@]} ]; then
                                selected+=("${options[$((j-1))]}")
                            fi
                        done
                    elif [[ "$part" =~ ^[0-9]+$ ]]; then
                        if [ "$part" -ge 1 ] && [ "$part" -le ${#options[@]} ]; then
                            selected+=("${options[$((part-1))]}")
                        fi
                    fi
                done
                
                # Join with commas
                local result=""
                for s in "${selected[@]}"; do
                    [ -n "$result" ] && result+=","
                    result+="$s"
                done
                eval "$result_var='$result'"
            fi
            ;;
    esac
}

# Show cluster resource summary
show_cluster_resources() {
    echo -e "${BLUE}Querying cluster resources...${NC}"
    
    local partitions=$(slurm_query_partitions)
    local accounts=$(slurm_query_accounts)
    local qos_list=$(slurm_query_qos)
    local node_count=$(slurm_query_node_names | wc -l)
    
    echo ""
    if [ -n "$partitions" ]; then
        echo -e "  ${GREEN}✓${NC} Partitions: $(echo "$partitions" | wc -l) available"
    else
        echo -e "  ${YELLOW}!${NC} Could not query partitions"
    fi
    
    if [ -n "$accounts" ]; then
        echo -e "  ${GREEN}✓${NC} Accounts: $(echo "$accounts" | wc -l) available for $USER"
    else
        echo -e "  ${YELLOW}!${NC} Could not query accounts"
    fi
    
    if [ -n "$qos_list" ]; then
        echo -e "  ${GREEN}✓${NC} QoS: $(echo "$qos_list" | wc -l) available"
    else
        echo -e "  ${YELLOW}!${NC} Could not query QoS"
    fi
    
    if [ "$node_count" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Nodes: $node_count available"
    else
        echo -e "  ${YELLOW}!${NC} Could not query nodes"
    fi
    echo ""
}

# Interactive partition selection
select_partition() {
    local result_var="$1"
    local default="$2"
    
    local partitions=$(slurm_query_partitions)
    
    if [ -z "$partitions" ]; then
        get_input "Partition (could not query cluster)" "$default" "$result_var"
        return
    fi
    
    local opts=()
    while IFS= read -r line; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$partitions"
    
    # Add manual entry option
    opts+=("(manual entry)")
    
    local choice=""
    menu_select_one "Select Partition" "Choose a partition for your jobs:" choice "${opts[@]}"
    
    if [ "$choice" = "(manual entry)" ] || [ -z "$choice" ]; then
        get_input "Partition" "$default" "$result_var"
    else
        eval "$result_var='$choice'"
    fi
}

# Interactive account selection
select_account() {
    local result_var="$1"
    local default="$2"
    
    local accounts=$(slurm_query_accounts)
    
    if [ -z "$accounts" ]; then
        get_input "Account (could not query cluster)" "$default" "$result_var"
        return
    fi
    
    local opts=()
    while IFS= read -r line; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$accounts"
    
    opts+=("(manual entry)")
    
    local choice=""
    menu_select_one "Select Account" "Choose your SLURM account:" choice "${opts[@]}"
    
    if [ "$choice" = "(manual entry)" ] || [ -z "$choice" ]; then
        get_input "Account" "$default" "$result_var"
    else
        eval "$result_var='$choice'"
    fi
}

# Interactive QoS selection
select_qos() {
    local result_var="$1"
    local default="$2"
    
    local qos_list=$(slurm_query_qos)
    
    if [ -z "$qos_list" ]; then
        get_input "QoS (could not query cluster)" "$default" "$result_var"
        return
    fi
    
    local opts=()
    while IFS= read -r line; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$qos_list"
    
    opts+=("(manual entry)")
    
    local choice=""
    menu_select_one "Select QoS" "Choose Quality of Service level:" choice "${opts[@]}"
    
    if [ "$choice" = "(manual entry)" ] || [ -z "$choice" ]; then
        get_input "QoS" "$default" "$result_var"
    else
        eval "$result_var='$choice'"
    fi
}

# Interactive node selection (multi-select for exclude/nodelist)
select_nodes() {
    local result_var="$1"
    local default="$2"
    local title="$3"
    local prompt="$4"
    
    local nodes=$(slurm_query_nodes)
    
    if [ -z "$nodes" ]; then
        get_input "$title (could not query cluster)" "$default" "$result_var"
        return
    fi
    
    # Parse nodes with state info for display
    local opts=()
    while IFS='|' read -r name state partition; do
        [ -n "$name" ] && opts+=("$name")
    done <<< "$nodes"
    
    # Remove duplicates
    local unique_opts=($(printf '%s\n' "${opts[@]}" | sort -u))
    
    if [ ${#unique_opts[@]} -gt 50 ]; then
        echo -e "${YELLOW}Large cluster detected (${#unique_opts[@]} nodes).${NC}"
        echo -e "Options: ${CYAN}1)${NC} Interactive menu  ${CYAN}2)${NC} Manual entry (SLURM hostlist)"
        echo -ne "Choice [1/2]: "
        read -r method
        
        if [ "$method" = "2" ]; then
            echo -e "${CYAN}Enter nodes (SLURM hostlist format, e.g. node[01-05,08]):${NC}"
            get_input "$title" "$default" "$result_var"
            return
        fi
    fi
    
    unique_opts+=("(manual entry)")
    
    local choice=""
    menu_select_many "$title" "$prompt" choice "${unique_opts[@]}"
    
    if [ "$choice" = "(manual entry)" ] || [ -z "$choice" ]; then
        get_input "$title (comma-separated or SLURM hostlist)" "$default" "$result_var"
    else
        eval "$result_var='$choice'"
    fi
}

