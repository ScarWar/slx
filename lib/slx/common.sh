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
SLX_PROFILES_DIR="${SLX_CONFIG_DIR}/profiles.d"
SLX_NODE_INVENTORY_FILE="${SLX_CONFIG_DIR}/nodes.tsv"

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

# ============================================
# Compute Profile Helpers
# ============================================

# Sanitize a profile name (alphanumeric, dash, underscore only)
sanitize_profile_name() {
    echo "$1" | tr ' ' '_' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]'
}

# List all available profile names (without .env extension)
list_profiles() {
    if [ ! -d "$SLX_PROFILES_DIR" ]; then
        return 0
    fi
    for f in "$SLX_PROFILES_DIR"/*.env; do
        [ -f "$f" ] || continue
        basename "$f" .env
    done
}

# Check if a profile exists
profile_exists() {
    local name="$1"
    [ -f "$SLX_PROFILES_DIR/${name}.env" ]
}

# Load a profile into SLX_PROFILE_* variables
# Usage: load_profile "profile_name"
# Sets: SLX_PROFILE_NAME, SLX_PROFILE_DESC, SLX_PROFILE_PARTITION, etc.
load_profile() {
    local name="$1"
    local profile_file="$SLX_PROFILES_DIR/${name}.env"
    
    if [ ! -f "$profile_file" ]; then
        echo -e "${RED}Error: Profile '${name}' not found${NC}" >&2
        return 1
    fi
    
    # Clear any existing profile variables
    unset SLX_PROFILE_NAME SLX_PROFILE_DESC
    unset SLX_PROFILE_PARTITION SLX_PROFILE_ACCOUNT SLX_PROFILE_QOS
    unset SLX_PROFILE_TIME SLX_PROFILE_NODES SLX_PROFILE_NTASKS
    unset SLX_PROFILE_CPUS SLX_PROFILE_MEM SLX_PROFILE_GPUS
    unset SLX_PROFILE_NODELIST SLX_PROFILE_EXCLUDE
    
    # Source the profile
    set -a
    source "$profile_file"
    set +a
    
    return 0
}

# Save a profile from current SLX_PROFILE_* variables
# Usage: save_profile "profile_name"
save_profile() {
    local name="$1"
    
    mkdir -p "$SLX_PROFILES_DIR"
    
    local profile_file="$SLX_PROFILES_DIR/${name}.env"
    
    cat > "$profile_file" << EOF
# slx compute profile: ${name}
# Generated on $(date)

# Profile metadata
SLX_PROFILE_NAME="${SLX_PROFILE_NAME:-$name}"
SLX_PROFILE_DESC="${SLX_PROFILE_DESC:-}"

# SLURM settings
SLX_PROFILE_PARTITION="${SLX_PROFILE_PARTITION:-}"
SLX_PROFILE_ACCOUNT="${SLX_PROFILE_ACCOUNT:-}"
SLX_PROFILE_QOS="${SLX_PROFILE_QOS:-}"
SLX_PROFILE_TIME="${SLX_PROFILE_TIME:-}"
SLX_PROFILE_NODES="${SLX_PROFILE_NODES:-}"
SLX_PROFILE_NTASKS="${SLX_PROFILE_NTASKS:-}"
SLX_PROFILE_CPUS="${SLX_PROFILE_CPUS:-}"
SLX_PROFILE_MEM="${SLX_PROFILE_MEM:-}"
SLX_PROFILE_GPUS="${SLX_PROFILE_GPUS:-}"

# Node preferences
SLX_PROFILE_NODELIST="${SLX_PROFILE_NODELIST:-}"
SLX_PROFILE_EXCLUDE="${SLX_PROFILE_EXCLUDE:-}"
EOF
    
    echo -e "${GREEN}Profile saved to: ${profile_file}${NC}"
}

# Delete a profile
# Usage: delete_profile "profile_name"
delete_profile() {
    local name="$1"
    local profile_file="$SLX_PROFILES_DIR/${name}.env"
    
    if [ ! -f "$profile_file" ]; then
        echo -e "${RED}Error: Profile '${name}' not found${NC}" >&2
        return 1
    fi
    
    rm -f "$profile_file"
    echo -e "${GREEN}Profile '${name}' deleted${NC}"
}

# Print a profile summary
# Usage: print_profile_summary "profile_name"
print_profile_summary() {
    local name="$1"
    
    if ! load_profile "$name"; then
        return 1
    fi
    
    echo -e "${BLUE}Profile: ${GREEN}${SLX_PROFILE_NAME:-$name}${NC}"
    [ -n "$SLX_PROFILE_DESC" ] && echo -e "  Description: ${SLX_PROFILE_DESC}"
    echo ""
    echo -e "  ${CYAN}SLURM Settings:${NC}"
    [ -n "$SLX_PROFILE_PARTITION" ] && echo -e "    Partition:  ${SLX_PROFILE_PARTITION}"
    [ -n "$SLX_PROFILE_ACCOUNT" ] && echo -e "    Account:    ${SLX_PROFILE_ACCOUNT}"
    [ -n "$SLX_PROFILE_QOS" ] && echo -e "    QoS:        ${SLX_PROFILE_QOS}"
    [ -n "$SLX_PROFILE_TIME" ] && echo -e "    Time:       ${SLX_PROFILE_TIME} min"
    [ -n "$SLX_PROFILE_NODES" ] && echo -e "    Nodes:      ${SLX_PROFILE_NODES}"
    [ -n "$SLX_PROFILE_NTASKS" ] && echo -e "    Tasks:      ${SLX_PROFILE_NTASKS}"
    [ -n "$SLX_PROFILE_CPUS" ] && echo -e "    CPUs:       ${SLX_PROFILE_CPUS}"
    [ -n "$SLX_PROFILE_MEM" ] && echo -e "    Memory:     ${SLX_PROFILE_MEM} MB"
    [ -n "$SLX_PROFILE_GPUS" ] && echo -e "    GPUs:       ${SLX_PROFILE_GPUS}"
    echo ""
    echo -e "  ${CYAN}Node Preferences:${NC}"
    [ -n "$SLX_PROFILE_NODELIST" ] && echo -e "    NodeList:   ${SLX_PROFILE_NODELIST}"
    [ -n "$SLX_PROFILE_EXCLUDE" ] && echo -e "    Exclude:    ${SLX_PROFILE_EXCLUDE}"
    if [ -z "$SLX_PROFILE_NODELIST" ] && [ -z "$SLX_PROFILE_EXCLUDE" ]; then
        echo -e "    ${YELLOW}(none set)${NC}"
    fi
}

# Apply a loaded profile to P_* project variables
# Call load_profile first, then call this to set P_PARTITION, P_ACCOUNT, etc.
apply_profile_to_project() {
    [ -n "$SLX_PROFILE_PARTITION" ] && P_PARTITION="$SLX_PROFILE_PARTITION"
    [ -n "$SLX_PROFILE_ACCOUNT" ] && P_ACCOUNT="$SLX_PROFILE_ACCOUNT"
    [ -n "$SLX_PROFILE_QOS" ] && P_QOS="$SLX_PROFILE_QOS"
    [ -n "$SLX_PROFILE_TIME" ] && P_TIME="$SLX_PROFILE_TIME"
    [ -n "$SLX_PROFILE_NODES" ] && P_NODES="$SLX_PROFILE_NODES"
    [ -n "$SLX_PROFILE_NTASKS" ] && P_NTASKS="$SLX_PROFILE_NTASKS"
    [ -n "$SLX_PROFILE_CPUS" ] && P_CPUS="$SLX_PROFILE_CPUS"
    [ -n "$SLX_PROFILE_MEM" ] && P_MEM="$SLX_PROFILE_MEM"
    [ -n "$SLX_PROFILE_GPUS" ] && P_GPUS="$SLX_PROFILE_GPUS"
    [ -n "$SLX_PROFILE_NODELIST" ] && P_NODELIST="$SLX_PROFILE_NODELIST"
    [ -n "$SLX_PROFILE_EXCLUDE" ] && P_EXCLUDE="$SLX_PROFILE_EXCLUDE"
}

# Interactive profile selection
# Usage: select_profile result_var
# Returns empty string if no profiles or user skips
select_profile() {
    local result_var="$1"
    
    local profiles=($(list_profiles))
    
    if [ ${#profiles[@]} -eq 0 ]; then
        eval "$result_var=''"
        return 0
    fi
    
    # Build display options with descriptions
    local opts=()
    opts+=("(none - use defaults)")
    for p in "${profiles[@]}"; do
        local desc=""
        if load_profile "$p" 2>/dev/null; then
            [ -n "$SLX_PROFILE_DESC" ] && desc=" - ${SLX_PROFILE_DESC}"
        fi
        opts+=("${p}${desc}")
    done
    
    local choice=""
    menu_select_one "Select Compute Profile" "Choose a profile for job defaults (or skip to use global config):" choice "${opts[@]}"
    
    if [ "$choice" = "(none - use defaults)" ] || [ -z "$choice" ]; then
        eval "$result_var=''"
    else
        # Extract profile name (before " - " if description present)
        local selected_name="${choice%% - *}"
        eval "$result_var='$selected_name'"
    fi
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
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_partitions() {
    if ! has_cmd sinfo; then
        return 0  # Return success with empty output instead of error
    fi
    sinfo -h -o "%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$' || true
}

# Query available accounts for current user
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_accounts() {
    if ! has_cmd sacctmgr; then
        return 0  # Return success with empty output instead of error
    fi
    sacctmgr -n -P show assoc where user="$USER" format=account 2>/dev/null | sort -u | grep -v '^$' || true
}

# Query available QoS for current user
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_qos() {
    if ! has_cmd sacctmgr; then
        return 0  # Return success with empty output instead of error
    fi
    sacctmgr -n -P show assoc where user="$USER" format=qos 2>/dev/null | tr ',' '\n' | sort -u | grep -v '^$' || true
}

# Query available nodes with state and partition info
# Returns: nodename|state|partition
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_nodes() {
    if ! has_cmd sinfo; then
        return 0  # Return success with empty output instead of error
    fi
    sinfo -N -h -o "%N|%T|%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$' || true
}

# Query just node names (simple list)
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_node_names() {
    if ! has_cmd sinfo; then
        return 0  # Return success with empty output instead of error
    fi
    sinfo -N -h -o "%N" 2>/dev/null | sort -u | grep -v '^$' || true
}

# Query detailed node information (CPU, memory, GPU/GRES, state)
# Returns: nodename|state|cpus|mem|gres|partition
# Best-effort: returns empty output (not error) if command unavailable or no results
slurm_query_node_details() {
    if ! has_cmd sinfo; then
        return 0  # Return success with empty output instead of error
    fi
    # Format: NodeName|State|CPUs|Memory(MB)|GRES|Partition
    # Memory is in MB, GRES shows GPU info like "gpu:a100:4"
    sinfo -N -h -o "%N|%T|%c|%m|%G|%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$' || true
}

# Load node inventory from user-maintained TSV file
# Format: nodeName<TAB>gpu<TAB>cpu<TAB>mem<TAB>notes
# Usage: load_node_inventory
# Populates associative array NODE_INVENTORY[nodename]="gpu|cpu|mem|notes"
declare -A NODE_INVENTORY
load_node_inventory() {
    NODE_INVENTORY=()
    
    if [ ! -f "$SLX_NODE_INVENTORY_FILE" ]; then
        return 0
    fi
    
    while IFS=$'\t' read -r name gpu cpu mem notes; do
        # Skip header line and empty lines
        [[ "$name" =~ ^#.*$ || -z "$name" || "$name" == "nodeName" ]] && continue
        NODE_INVENTORY["$name"]="${gpu}|${cpu}|${mem}|${notes}"
    done < "$SLX_NODE_INVENTORY_FILE"
}

# Lookup node info from inventory
# Usage: lookup_node_inventory "nodename"
# Returns: "gpu|cpu|mem|notes" or empty string if not found
lookup_node_inventory() {
    local name="$1"
    echo "${NODE_INVENTORY[$name]:-}"
}

# Format node display string with details
# Usage: format_node_display "nodename" "state" "cpus" "mem" "gres" "partition"
# Returns compact display like: "node01 [idle] cpu=64 mem=512G gpu=a100x4"
format_node_display() {
    local name="$1"
    local state="$2"
    local cpus="$3"
    local mem="$4"
    local gres="$5"
    local partition="$6"
    
    local display="$name"
    
    # Add state if available
    [ -n "$state" ] && display+=" [${state}]"
    
    # Check inventory first for overrides
    local inv_info=$(lookup_node_inventory "$name")
    if [ -n "$inv_info" ]; then
        IFS='|' read -r inv_gpu inv_cpu inv_mem inv_notes <<< "$inv_info"
        [ -n "$inv_cpu" ] && cpus="$inv_cpu"
        [ -n "$inv_mem" ] && mem="$inv_mem"
        [ -n "$inv_gpu" ] && gres="$inv_gpu"
    fi
    
    # Add resource info
    [ -n "$cpus" ] && [ "$cpus" != "(null)" ] && display+=" cpu=${cpus}"
    
    # Format memory (convert MB to G if large)
    if [ -n "$mem" ] && [ "$mem" != "(null)" ]; then
        if [[ "$mem" =~ ^[0-9]+$ ]] && [ "$mem" -ge 1024 ]; then
            local mem_gb=$((mem / 1024))
            display+=" mem=${mem_gb}G"
        else
            display+=" mem=${mem}"
        fi
    fi
    
    # Format GRES (GPU info)
    if [ -n "$gres" ] && [ "$gres" != "(null)" ]; then
        # Parse GRES like "gpu:a100:4" -> "a100x4"
        if [[ "$gres" =~ gpu:([^:]+):([0-9]+) ]]; then
            local gpu_type="${BASH_REMATCH[1]}"
            local gpu_count="${BASH_REMATCH[2]}"
            display+=" gpu=${gpu_type}x${gpu_count}"
        elif [[ "$gres" =~ gpu:([0-9]+) ]]; then
            display+=" gpu=${BASH_REMATCH[1]}"
        elif [ "$gres" != "(null)" ]; then
            display+=" gres=${gres}"
        fi
    fi
    
    echo "$display"
}

# Build node options array with detailed display
# Usage: build_node_options_detailed
# Sets: NODE_DISPLAY_OPTS array and NODE_DISPLAY_MAP associative array
declare -a NODE_DISPLAY_OPTS
declare -A NODE_DISPLAY_MAP
build_node_options_detailed() {
    NODE_DISPLAY_OPTS=()
    NODE_DISPLAY_MAP=()
    
    # Load inventory if available
    load_node_inventory
    
    # Try detailed query first
    local node_details=$(slurm_query_node_details)
    
    if [ -z "$node_details" ]; then
        # Fallback to simple query
        local nodes=$(slurm_query_nodes)
        while IFS='|' read -r name state partition; do
            [ -z "$name" ] && continue
            local display=$(format_node_display "$name" "$state" "" "" "" "$partition")
            NODE_DISPLAY_OPTS+=("$display")
            NODE_DISPLAY_MAP["$display"]="$name"
        done <<< "$nodes"
    else
        # Use detailed info
        while IFS='|' read -r name state cpus mem gres partition; do
            [ -z "$name" ] && continue
            local display=$(format_node_display "$name" "$state" "$cpus" "$mem" "$gres" "$partition")
            NODE_DISPLAY_OPTS+=("$display")
            NODE_DISPLAY_MAP["$display"]="$name"
        done <<< "$node_details"
    fi
    
    # Remove duplicates while preserving order
    local seen=()
    local unique_opts=()
    for opt in "${NODE_DISPLAY_OPTS[@]}"; do
        local name="${NODE_DISPLAY_MAP[$opt]}"
        if [[ ! " ${seen[*]} " =~ " ${name} " ]]; then
            seen+=("$name")
            unique_opts+=("$opt")
        fi
    done
    NODE_DISPLAY_OPTS=("${unique_opts[@]}")
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
            local i=0
            # Build menu items: use index as tag, option text as display
            # This ensures reliable mapping between selection and option
            for opt in "${options[@]}"; do
                menu_items+=("$i" "$opt")
                ((i++)) || true  # Prevent errexit when i=0 (evaluates to false)
            done
            
            local choice_index=""
            local exit_code=0
            
            # whiptail/dialog:
            # - Displays UI on terminal (via ncurses)
            # - Returns selection on stderr
            # Use temp file to capture stderr (selection) while keeping terminal for display
            # All operations are made errexit-safe with || true patterns
            local tmp_file
            tmp_file=$(mktemp 2>/dev/null) || tmp_file="/tmp/slx_menu_$$"
            $menu_tool --title "$title" --menu "$prompt" 20 60 12 "${menu_items[@]}" </dev/tty >/dev/tty 2>"$tmp_file" || exit_code=$?
            choice_index=$(cat "$tmp_file" 2>/dev/null) || true
            rm -f "$tmp_file" 2>/dev/null || true
            
            # Trim whitespace (xargs can fail on unusual input, so make it safe)
            choice_index=$(echo "$choice_index" | xargs 2>/dev/null) || choice_index=""
            
            if [ $exit_code -eq 0 ] && [ -n "$choice_index" ]; then
                # Convert index back to option text
                if [[ "$choice_index" =~ ^[0-9]+$ ]] && [ "$choice_index" -ge 0 ] && [ "$choice_index" -lt ${#options[@]} ]; then
                    local selected_option="${options[$choice_index]}"
                    eval "$result_var='$selected_option'"
                else
                    # Invalid index, treat as cancelled
                    eval "$result_var=''"
                fi
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
            
            local choices=""
            local exit_code=0
            
            # whiptail/dialog: capture stderr (selection) while keeping terminal for display
            # All operations are made errexit-safe with || true patterns
            local tmp_file
            tmp_file=$(mktemp 2>/dev/null) || tmp_file="/tmp/slx_menu_multi_$$"
            $menu_tool --title "$title" --checklist "$prompt" 22 70 15 "${menu_items[@]}" </dev/tty >/dev/tty 2>"$tmp_file" || exit_code=$?
            choices=$(cat "$tmp_file" 2>/dev/null) || true
            rm -f "$tmp_file" 2>/dev/null || true
            
            if [ $exit_code -eq 0 ] && [ -n "$choices" ]; then
                # Parse quoted strings properly (whiptail/dialog returns space-separated quoted strings)
                # Example: "item1" "item2 with spaces" "item3"
                # We need to extract each quoted string and join with commas, preserving spaces within strings
                local cleaned=""
                # Extract quoted strings using grep -o to get all matches, then join with commas
                # Use `|| true` to handle empty output from grep
                local items=$(echo "$choices" | grep -o '"[^"]*"' | sed 's/"//g' || true)
                while IFS= read -r item; do
                    [ -z "$item" ] && continue
                    if [ -n "$cleaned" ]; then
                        cleaned+=","
                    fi
                    cleaned+="$item"
                done <<< "$items"
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
    # Read partitions into array, handling empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$partitions"
    
    # Ensure we have at least one option
    if [ ${#opts[@]} -eq 0 ]; then
        get_input "Partition (no partitions found)" "$default" "$result_var"
        return
    fi
    
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
    # Read accounts into array, handling empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$accounts"
    
    # Ensure we have at least one option
    if [ ${#opts[@]} -eq 0 ]; then
        get_input "Account (no accounts found)" "$default" "$result_var"
        return
    fi
    
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
    # Read QoS into array, handling empty lines
    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] && opts+=("$line")
    done <<< "$qos_list"
    
    # Ensure we have at least one option
    if [ ${#opts[@]} -eq 0 ]; then
        get_input "QoS (no QoS found)" "$default" "$result_var"
        return
    fi
    
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
# Enhanced to show CPU/memory/GPU info when available
select_nodes() {
    local result_var="$1"
    local default="$2"
    local title="$3"
    local prompt="$4"
    
    # Show guidance based on whether this is nodelist or exclude
    echo ""
    if [[ "$title" == *"NodeList"* ]] || [[ "$title" == *"Prefer"* ]]; then
        echo -e "${CYAN}NodeList Guidance:${NC}"
        echo -e "  Use NodeList to prefer specific nodes for your jobs."
        echo -e "  Jobs will run on these nodes when available, but SLURM"
        echo -e "  may still use other nodes if these are busy."
    elif [[ "$title" == *"Exclude"* ]]; then
        echo -e "${CYAN}Exclude Guidance:${NC}"
        echo -e "  Use Exclude to avoid problematic or unsuitable nodes."
        echo -e "  Jobs will never be scheduled on excluded nodes."
    fi
    echo ""
    
    # Build detailed node options
    build_node_options_detailed
    
    if [ ${#NODE_DISPLAY_OPTS[@]} -eq 0 ]; then
        echo -e "${YELLOW}Could not query cluster nodes.${NC}"
        get_input "$title (could not query cluster)" "$default" "$result_var"
        return
    fi
    
    local node_count=${#NODE_DISPLAY_OPTS[@]}
    
    # Large cluster handling
    if [ $node_count -gt 50 ]; then
        echo -e "${YELLOW}Large cluster detected (${node_count} nodes).${NC}"
        echo -e "Options:"
        echo -e "  ${CYAN}1)${NC} Interactive menu (with node details)"
        echo -e "  ${CYAN}2)${NC} Manual entry (SLURM hostlist format)"
        echo -e "  ${CYAN}0)${NC} Skip this selection"
        echo -ne "Choice [1/2/0]: "
        read -r method
        
        if [ "$method" = "0" ] || [ -z "$method" ]; then
            eval "$result_var='$default'"
            return
        fi
        
        if [ "$method" = "2" ]; then
            echo ""
            echo -e "${CYAN}Enter nodes using SLURM hostlist format:${NC}"
            echo -e "  Examples: ${YELLOW}node01,node02,node03${NC}"
            echo -e "           ${YELLOW}node[01-10]${NC}"
            echo -e "           ${YELLOW}gpu-node[01-05,08,10-12]${NC}"
            get_input "$title" "$default" "$result_var"
            return
        fi
    fi
    
    # Add manual entry option
    NODE_DISPLAY_OPTS+=("(manual entry)")
    
    local choice=""
    menu_select_many "$title" "$prompt" choice "${NODE_DISPLAY_OPTS[@]}"
    
    if [ "$choice" = "(manual entry)" ]; then
        echo ""
        echo -e "${CYAN}Enter nodes (comma-separated or SLURM hostlist):${NC}"
        get_input "$title" "$default" "$result_var"
    elif [ -z "$choice" ]; then
        eval "$result_var='$default'"
    else
        # Convert display names back to node names
        local node_names=""
        IFS=',' read -ra selected_displays <<< "$choice"
        for display in "${selected_displays[@]}"; do
            # Remove quotes if present (from whiptail/dialog)
            display=$(echo "$display" | tr -d '"' | xargs)
            
            # Try to get node name from map first
            local node_name="${NODE_DISPLAY_MAP[$display]}"
            
            # If not found in map, extract node name from display string
            # Display format: "node01 [idle] cpu=64 mem=512G gpu=a100x4"
            # We want just "node01" - everything before first space or bracket
            if [ -z "$node_name" ]; then
                # Remove any leading/trailing whitespace first
                display=$(echo "$display" | xargs)
                # Extract first word (node name) - use awk to get first field
                node_name=$(echo "$display" | awk '{print $1}')
                # Clean up: remove any brackets or special chars that might have been included
                node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
            fi
            
            # Only add if we have a valid node name
            if [ -n "$node_name" ]; then
                [ -n "$node_names" ] && node_names+=","
                node_names+="$node_name"
            fi
        done
        eval "$result_var='$node_names'"
    fi
}

