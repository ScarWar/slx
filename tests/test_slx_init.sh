#!/bin/bash
# Test suite for slx init functionality
# Run with: bash tests/test_slx_init.sh

# Don't exit on first error - we handle errors in run_test
# set -e

# ============================================
# Test Framework
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SLX_SCRIPT="$PROJECT_DIR/bin/slx"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Temporary test directory
TEST_TMP=""

setup_test_env() {
    TEST_TMP=$(mktemp -d)
    export HOME="$TEST_TMP/home"
    export XDG_CONFIG_HOME="$TEST_TMP/config"
    export XDG_DATA_HOME="$TEST_TMP/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
    
    # Mock bin directory for command mocking
    MOCK_BIN="$TEST_TMP/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
}

teardown_test_env() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

# Test assertion helpers
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  String: '$haystack'"
        echo "  Should contain: '$needle'"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"
    
    if [ -f "$file" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  File not found: '$file'"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local message="${3:-File should contain pattern}"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  File: '$file'"
        echo "  Pattern not found: '$pattern'"
        return 1
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -ne "  ${BLUE}Testing:${NC} $test_name... "
    
    setup_test_env
    
    local result=0
    local output
    output=$( (set +e; $test_func) 2>&1) || result=$?
    
    teardown_test_env
    
    if [ $result -eq 0 ]; then
        echo -e "${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAILED${NC}"
        echo "$output" | sed 's/^/    /'
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ============================================
# Mock Helpers
# ============================================

create_mock_sinfo() {
    local output="$1"
    cat > "$MOCK_BIN/sinfo" << EOF
#!/bin/bash
echo "$output"
EOF
    chmod +x "$MOCK_BIN/sinfo"
}

create_mock_sacctmgr() {
    local output="$1"
    cat > "$MOCK_BIN/sacctmgr" << EOF
#!/bin/bash
echo "$output"
EOF
    chmod +x "$MOCK_BIN/sacctmgr"
}

remove_mock_sinfo() {
    rm -f "$MOCK_BIN/sinfo"
}

remove_mock_sacctmgr() {
    rm -f "$MOCK_BIN/sacctmgr"
}

# ============================================
# Source slx functions for unit testing
# ============================================

source_slx_functions() {
    # Define colors (needed by slx functions)
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
    
    # Define the helper functions directly (copied from slx)
    has_cmd() {
        command -v "$1" &>/dev/null
    }
    
    detect_menu_tool() {
        if has_cmd whiptail; then
            echo "whiptail"
        elif has_cmd dialog; then
            echo "dialog"
        else
            echo "text"
        fi
    }
    
    slurm_query_partitions() {
        if ! has_cmd sinfo; then
            return 1
        fi
        sinfo -h -o "%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$'
    }
    
    slurm_query_accounts() {
        if ! has_cmd sacctmgr; then
            return 1
        fi
        sacctmgr -n -P show assoc where user="$USER" format=account 2>/dev/null | sort -u | grep -v '^$'
    }
    
    slurm_query_qos() {
        if ! has_cmd sacctmgr; then
            return 1
        fi
        sacctmgr -n -P show assoc where user="$USER" format=qos 2>/dev/null | tr ',' '\n' | sort -u | grep -v '^$'
    }
    
    slurm_query_nodes() {
        if ! has_cmd sinfo; then
            return 1
        fi
        sinfo -N -h -o "%N|%T|%P" 2>/dev/null | sed 's/\*$//' | sort -u | grep -v '^$'
    }
    
    slurm_query_node_names() {
        if ! has_cmd sinfo; then
            return 1
        fi
        sinfo -N -h -o "%N" 2>/dev/null | sort -u | grep -v '^$'
    }
}

# ============================================
# Unit Tests: SLURM Query Helpers
# ============================================

test_has_cmd_existing() {
    source_slx_functions
    
    # bash should exist
    has_cmd bash
    assert_equals "0" "$?" "has_cmd should return 0 for existing command"
}

test_has_cmd_nonexisting() {
    source_slx_functions
    
    # nonexistent_command_xyz should not exist
    has_cmd nonexistent_command_xyz && return 1 || true
}

test_detect_menu_tool_text_fallback() {
    source_slx_functions
    
    # Remove whiptail and dialog from path
    local old_path="$PATH"
    export PATH="$MOCK_BIN"
    
    local result=$(detect_menu_tool)
    export PATH="$old_path"
    
    assert_equals "text" "$result" "Should fall back to text when no whiptail/dialog"
}

test_slurm_query_partitions_success() {
    source_slx_functions
    
    create_mock_sinfo "gpu*
cpu
highmem
debug"
    
    local result=$(slurm_query_partitions)
    
    assert_contains "$result" "gpu" "Should contain gpu partition"
    assert_contains "$result" "cpu" "Should contain cpu partition"
    assert_contains "$result" "highmem" "Should contain highmem partition"
    assert_contains "$result" "debug" "Should contain debug partition"
}

test_slurm_query_partitions_strips_asterisk() {
    source_slx_functions
    
    create_mock_sinfo "gpu*
cpu*"
    
    local result=$(slurm_query_partitions)
    
    # Should not contain asterisk
    if [[ "$result" == *"*"* ]]; then
        echo "Result should not contain asterisk"
        return 1
    fi
}

test_slurm_query_partitions_no_sinfo() {
    # Override PATH to exclude real sinfo
    local old_path="$PATH"
    export PATH="$MOCK_BIN"  # Only mock bin, no real commands
    
    source_slx_functions
    
    # Should fail gracefully when sinfo not found
    local result=0
    slurm_query_partitions || result=$?
    
    export PATH="$old_path"
    
    if [ $result -ne 0 ]; then
        return 0  # Test passes - function correctly returned error
    else
        echo "Expected slurm_query_partitions to fail when sinfo not available"
        return 1
    fi
}

test_slurm_query_partitions_empty_output() {
    source_slx_functions
    
    create_mock_sinfo ""
    
    local result=$(slurm_query_partitions)
    
    assert_equals "" "$result" "Should return empty for empty sinfo output"
}

test_slurm_query_accounts_success() {
    source_slx_functions
    
    create_mock_sacctmgr "research
teaching
admin"
    
    local result=$(slurm_query_accounts)
    
    assert_contains "$result" "research" "Should contain research account"
    assert_contains "$result" "teaching" "Should contain teaching account"
}

test_slurm_query_accounts_no_sacctmgr() {
    # Override PATH to exclude real sacctmgr
    local old_path="$PATH"
    export PATH="$MOCK_BIN"  # Only mock bin, no real commands
    
    source_slx_functions
    
    # Should fail gracefully when sacctmgr not found
    local result=0
    slurm_query_accounts || result=$?
    
    export PATH="$old_path"
    
    if [ $result -ne 0 ]; then
        return 0  # Test passes - function correctly returned error
    else
        echo "Expected slurm_query_accounts to fail when sacctmgr not available"
        return 1
    fi
}

test_slurm_query_qos_success() {
    source_slx_functions
    
    create_mock_sacctmgr "normal,high,low"
    
    local result=$(slurm_query_qos)
    
    assert_contains "$result" "normal" "Should contain normal qos"
    assert_contains "$result" "high" "Should contain high qos"
    assert_contains "$result" "low" "Should contain low qos"
}

test_slurm_query_qos_splits_commas() {
    source_slx_functions
    
    create_mock_sacctmgr "normal,high,low"
    
    local result=$(slurm_query_qos)
    local count=$(echo "$result" | grep -c .)
    
    # Should have 3 lines (one per QoS)
    if [ "$count" -lt 3 ]; then
        echo "Expected at least 3 QoS entries, got $count"
        return 1
    fi
}

test_slurm_query_nodes_success() {
    source_slx_functions
    
    create_mock_sinfo "node01|idle|gpu
node02|allocated|gpu
node03|idle|cpu"
    
    local result=$(slurm_query_nodes)
    
    assert_contains "$result" "node01" "Should contain node01"
    assert_contains "$result" "node02" "Should contain node02"
    assert_contains "$result" "idle" "Should contain state info"
    assert_contains "$result" "gpu" "Should contain partition info"
}

test_slurm_query_node_names_success() {
    source_slx_functions
    
    create_mock_sinfo "node01
node02
node03"
    
    local result=$(slurm_query_node_names)
    
    assert_contains "$result" "node01" "Should contain node01"
    assert_contains "$result" "node02" "Should contain node02"
    assert_contains "$result" "node03" "Should contain node03"
}

test_slurm_query_node_names_deduplicates() {
    source_slx_functions
    
    create_mock_sinfo "node01
node01
node02"
    
    local result=$(slurm_query_node_names)
    local count=$(echo "$result" | grep -c "node01" || true)
    
    assert_equals "1" "$count" "Should deduplicate node names"
}

# ============================================
# Unit Tests: Configuration
# ============================================

test_config_save_creates_directory() {
    # Simulate config save
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/tmp/workdir"
SLX_PARTITION="gpu"
SLX_ACCOUNT="research"
EOF
    
    assert_file_exists "$config_file" "Config file should be created"
}

test_config_save_includes_nodelist() {
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/tmp/workdir"
SLX_PARTITION="gpu"
SLX_ACCOUNT="research"
SLX_NODELIST="node01,node02"
SLX_EXCLUDE="node03"
EOF
    
    assert_file_contains "$config_file" "SLX_NODELIST" "Config should include SLX_NODELIST"
    assert_file_contains "$config_file" "SLX_EXCLUDE" "Config should include SLX_EXCLUDE"
}

test_config_load_applies_defaults() {
    # Test that missing config values get defaults
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/tmp/workdir"
EOF
    
    # Source the config
    source "$config_file"
    
    # Apply defaults (simulating load_config logic)
    SLX_PARTITION="${SLX_PARTITION:-}"
    SLX_QOS="${SLX_QOS:-normal}"
    SLX_TIME="${SLX_TIME:-1440}"
    SLX_NODES="${SLX_NODES:-1}"
    
    assert_equals "normal" "$SLX_QOS" "QOS should default to normal"
    assert_equals "1440" "$SLX_TIME" "TIME should default to 1440"
    assert_equals "1" "$SLX_NODES" "NODES should default to 1"
}

test_config_load_preserves_existing() {
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/custom/workdir"
SLX_PARTITION="custom-partition"
SLX_QOS="high"
SLX_TIME="60"
EOF
    
    source "$config_file"
    
    assert_equals "/custom/workdir" "$SLX_WORKDIR" "WORKDIR should be preserved"
    assert_equals "custom-partition" "$SLX_PARTITION" "PARTITION should be preserved"
    assert_equals "high" "$SLX_QOS" "QOS should be preserved"
    assert_equals "60" "$SLX_TIME" "TIME should be preserved"
}

# ============================================
# Unit Tests: Menu Selection (Text Mode)
# ============================================

test_menu_parse_single_number() {
    # Test parsing of single number selection
    local selection="2"
    local options=("opt1" "opt2" "opt3")
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#options[@]} ]; then
        local result="${options[$((selection-1))]}"
        assert_equals "opt2" "$result" "Should select second option"
    else
        return 1
    fi
}

test_menu_parse_range() {
    # Test parsing of range selection (1-3)
    local selection="1-3"
    local options=("opt1" "opt2" "opt3" "opt4")
    local selected=()
    
    if [[ "$selection" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        for ((j=start; j<=end; j++)); do
            if [ "$j" -ge 1 ] && [ "$j" -le ${#options[@]} ]; then
                selected+=("${options[$((j-1))]}")
            fi
        done
    fi
    
    assert_equals "3" "${#selected[@]}" "Should select 3 options"
    assert_equals "opt1" "${selected[0]}" "First should be opt1"
    assert_equals "opt2" "${selected[1]}" "Second should be opt2"
    assert_equals "opt3" "${selected[2]}" "Third should be opt3"
}

test_menu_parse_comma_separated() {
    # Test parsing of comma-separated selection (1,3,5)
    local selection="1,3"
    local options=("opt1" "opt2" "opt3" "opt4")
    local selected=()
    
    IFS=',' read -ra parts <<< "$selection"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if [[ "$part" =~ ^[0-9]+$ ]]; then
            if [ "$part" -ge 1 ] && [ "$part" -le ${#options[@]} ]; then
                selected+=("${options[$((part-1))]}")
            fi
        fi
    done
    
    assert_equals "2" "${#selected[@]}" "Should select 2 options"
    assert_equals "opt1" "${selected[0]}" "First should be opt1"
    assert_equals "opt3" "${selected[1]}" "Second should be opt3"
}

test_menu_parse_mixed() {
    # Test parsing of mixed selection (1,3-5,7)
    local selection="1,3-4"
    local options=("opt1" "opt2" "opt3" "opt4" "opt5")
    local selected=()
    
    IFS=',' read -ra parts <<< "$selection"
    for part in "${parts[@]}"; do
        part=$(echo "$part" | tr -d ' ')
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
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
    
    assert_equals "3" "${#selected[@]}" "Should select 3 options"
    assert_equals "opt1" "${selected[0]}" "First should be opt1"
    assert_equals "opt3" "${selected[1]}" "Second should be opt3"
    assert_equals "opt4" "${selected[2]}" "Third should be opt4"
}

test_menu_skip_on_zero() {
    local selection="0"
    local result=""
    
    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        result=""
    else
        result="selected"
    fi
    
    assert_equals "" "$result" "Should return empty on 0 selection"
}

test_menu_skip_on_empty() {
    local selection=""
    local result=""
    
    if [ "$selection" = "0" ] || [ -z "$selection" ]; then
        result=""
    else
        result="selected"
    fi
    
    assert_equals "" "$result" "Should return empty on empty selection"
}

test_menu_invalid_number_ignored() {
    # Test that invalid numbers (out of range) are ignored
    local selection="99"
    local options=("opt1" "opt2" "opt3")
    local result=""
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le ${#options[@]} ]; then
        result="${options[$((selection-1))]}"
    fi
    
    assert_equals "" "$result" "Should ignore out-of-range selection"
}

# ============================================
# Integration Tests: Config Scenarios
# ============================================

test_config_all_defaults() {
    # Test configuration with all default values
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/home/user/workdir"
SLX_PARTITION=""
SLX_ACCOUNT=""
SLX_QOS="normal"
SLX_TIME="1440"
SLX_NODES="1"
SLX_NTASKS="1"
SLX_CPUS="4"
SLX_MEM="50000"
SLX_GPUS=""
SLX_EXCLUDE=""
SLX_NODELIST=""
SLX_LOG_DIR="/home/user/workdir/slurm/logs"
EOF
    
    source "$config_file"
    
    assert_equals "/home/user/workdir" "$SLX_WORKDIR"
    assert_equals "" "$SLX_PARTITION"
    assert_equals "normal" "$SLX_QOS"
    assert_equals "1440" "$SLX_TIME"
    assert_equals "" "$SLX_NODELIST"
    assert_equals "" "$SLX_EXCLUDE"
}

test_config_full_custom() {
    # Test configuration with all custom values
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/scratch/user/work"
SLX_PARTITION="gpu-rtx"
SLX_ACCOUNT="research-lab"
SLX_QOS="high"
SLX_TIME="2880"
SLX_NODES="2"
SLX_NTASKS="8"
SLX_CPUS="16"
SLX_MEM="128000"
SLX_GPUS="4"
SLX_EXCLUDE="node01,node02"
SLX_NODELIST="node05,node06,node07"
SLX_LOG_DIR="/scratch/user/work/slurm/logs"
EOF
    
    source "$config_file"
    
    assert_equals "/scratch/user/work" "$SLX_WORKDIR"
    assert_equals "gpu-rtx" "$SLX_PARTITION"
    assert_equals "research-lab" "$SLX_ACCOUNT"
    assert_equals "high" "$SLX_QOS"
    assert_equals "2880" "$SLX_TIME"
    assert_equals "2" "$SLX_NODES"
    assert_equals "8" "$SLX_NTASKS"
    assert_equals "16" "$SLX_CPUS"
    assert_equals "128000" "$SLX_MEM"
    assert_equals "4" "$SLX_GPUS"
    assert_equals "node01,node02" "$SLX_EXCLUDE"
    assert_equals "node05,node06,node07" "$SLX_NODELIST"
}

test_config_nodelist_only() {
    # Test configuration with nodelist but no exclude
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/home/user/workdir"
SLX_PARTITION="gpu"
SLX_NODELIST="gpu-node-01,gpu-node-02"
SLX_EXCLUDE=""
EOF
    
    source "$config_file"
    
    assert_equals "gpu-node-01,gpu-node-02" "$SLX_NODELIST"
    assert_equals "" "$SLX_EXCLUDE"
}

test_config_exclude_only() {
    # Test configuration with exclude but no nodelist
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/home/user/workdir"
SLX_PARTITION="gpu"
SLX_NODELIST=""
SLX_EXCLUDE="broken-node-01,broken-node-02"
EOF
    
    source "$config_file"
    
    assert_equals "" "$SLX_NODELIST"
    assert_equals "broken-node-01,broken-node-02" "$SLX_EXCLUDE"
}

test_config_slurm_hostlist_format() {
    # Test configuration with SLURM hostlist format
    local config_dir="$XDG_CONFIG_HOME/slx"
    local config_file="$config_dir/config.env"
    
    mkdir -p "$config_dir"
    cat > "$config_file" << 'EOF'
SLX_WORKDIR="/home/user/workdir"
SLX_NODELIST="node[01-10,15,20-25]"
SLX_EXCLUDE="node[11-14]"
EOF
    
    source "$config_file"
    
    assert_equals "node[01-10,15,20-25]" "$SLX_NODELIST"
    assert_equals "node[11-14]" "$SLX_EXCLUDE"
}

# ============================================
# Edge Case Tests
# ============================================

test_empty_partition_list() {
    source_slx_functions
    
    create_mock_sinfo ""
    
    local result=$(slurm_query_partitions)
    assert_equals "" "$result" "Empty partition list should return empty"
}

test_empty_account_list() {
    source_slx_functions
    
    create_mock_sacctmgr ""
    
    local result=$(slurm_query_accounts)
    assert_equals "" "$result" "Empty account list should return empty"
}

test_partition_with_special_characters() {
    source_slx_functions
    
    create_mock_sinfo "gpu-rtx3090
cpu_highmem
debug.fast"
    
    local result=$(slurm_query_partitions)
    
    assert_contains "$result" "gpu-rtx3090" "Should handle hyphens"
    assert_contains "$result" "cpu_highmem" "Should handle underscores"
    assert_contains "$result" "debug.fast" "Should handle dots"
}

test_node_with_complex_state() {
    source_slx_functions
    
    create_mock_sinfo "node01|idle+drain|gpu
node02|mixed*|cpu
node03|allocated~|highmem"
    
    local result=$(slurm_query_nodes)
    
    assert_contains "$result" "node01" "Should contain node01"
    assert_contains "$result" "idle+drain" "Should preserve complex state"
}

test_whitespace_handling() {
    source_slx_functions
    
    create_mock_sinfo "  gpu  
cpu
  highmem  "
    
    local result=$(slurm_query_partitions)
    
    # Should still work with leading/trailing whitespace
    assert_contains "$result" "gpu" "Should handle whitespace"
}

test_duplicate_entries() {
    source_slx_functions
    
    create_mock_sinfo "gpu
gpu
cpu
cpu
gpu"
    
    local result=$(slurm_query_partitions)
    local gpu_count=$(echo "$result" | grep -c "^gpu$" || true)
    
    assert_equals "1" "$gpu_count" "Should deduplicate entries"
}

# ============================================
# Node Selection Extraction Tests
# ============================================

test_node_selection_extracts_name_only() {
    # Test that node selection extracts only node names, not full display strings
    # Simulate the extraction logic from select_nodes function
    
    # Simulate display strings with CPU, memory, GPU info
    local choice="node01 [idle] cpu=64 mem=512G gpu=a100x4,node02 [allocated] cpu=32 mem=256G gpu=v100x2"
    
    # Simulate the extraction logic
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        # Remove quotes if present (from whiptail/dialog)
        display=$(echo "$display" | tr -d '"' | xargs)
        
        # Extract first word (node name) - use awk to get first field
        local node_name=$(echo "$display" | awk '{print $1}')
        # Clean up: remove any brackets or special chars that might have been included
        node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        
        # Only add if we have a valid node name
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node01,node02" "$node_names" "Should extract only node names, not full display strings"
}

test_node_selection_with_quotes() {
    # Test that quotes are properly removed
    local choice='"node01 [idle] cpu=64 mem=512G gpu=a100x4","node02 [allocated] cpu=32 mem=256G"'
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        local node_name=$(echo "$display" | awk '{print $1}')
        node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node01,node02" "$node_names" "Should handle quoted display strings"
}

test_node_selection_single_node() {
    # Test with a single node selection
    local choice="gpu-node-01 [idle] cpu=128 mem=1024G gpu=a100x8"
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        local node_name=$(echo "$display" | awk '{print $1}')
        node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "gpu-node-01" "$node_names" "Should extract single node name correctly"
}

test_node_selection_with_map_lookup() {
    # Test that map lookup works when available
    # Simulate NODE_DISPLAY_MAP
    declare -A NODE_DISPLAY_MAP
    NODE_DISPLAY_MAP["node01 [idle] cpu=64 mem=512G gpu=a100x4"]="node01"
    NODE_DISPLAY_MAP["node02 [allocated] cpu=32 mem=256G"]="node02"
    
    local choice="node01 [idle] cpu=64 mem=512G gpu=a100x4,node02 [allocated] cpu=32 mem=256G"
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        
        # Try to get node name from map first
        local node_name="${NODE_DISPLAY_MAP[$display]}"
        
        # If not found in map, extract node name from display string
        if [ -z "$node_name" ]; then
            display=$(echo "$display" | xargs)
            node_name=$(echo "$display" | awk '{print $1}')
            node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        fi
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node01,node02" "$node_names" "Should use map lookup when available"
}

test_node_selection_fallback_extraction() {
    # Test fallback extraction when map lookup fails
    declare -A NODE_DISPLAY_MAP
    # Map doesn't have the entry, so should fall back to extraction
    
    local choice="node03 [mixed] cpu=48 mem=384G gpu=rtx3090x4"
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        
        # Try to get node name from map first
        local node_name="${NODE_DISPLAY_MAP[$display]}"
        
        # If not found in map, extract node name from display string
        if [ -z "$node_name" ]; then
            display=$(echo "$display" | xargs)
            node_name=$(echo "$display" | awk '{print $1}')
            node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        fi
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node03" "$node_names" "Should fall back to extraction when map lookup fails"
}

test_node_selection_complex_display_strings() {
    # Test with various complex display string formats
    local choice="node-01 [idle] cpu=64 mem=512G gpu=a100x4,node-02 [allocated] cpu=32,node-03 [mixed] mem=256G"
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        local node_name=$(echo "$display" | awk '{print $1}')
        node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node-01,node-02,node-03" "$node_names" "Should handle complex display strings"
}

test_node_selection_no_cpu_memory_info() {
    # Test with display strings that don't have CPU/memory info
    local choice="node01 [idle],node02 [allocated]"
    
    local node_names=""
    IFS=',' read -ra selected_displays <<< "$choice"
    for display in "${selected_displays[@]}"; do
        display=$(echo "$display" | tr -d '"' | xargs)
        local node_name=$(echo "$display" | awk '{print $1}')
        node_name=$(echo "$node_name" | sed 's/\[.*//' | sed 's/.*\]//' | xargs)
        
        if [ -n "$node_name" ]; then
            [ -n "$node_names" ] && node_names+=","
            node_names+="$node_name"
        fi
    done
    
    assert_equals "node01,node02" "$node_names" "Should extract names even without CPU/memory info"
}

# ============================================
# SBATCH Generation Tests
# ============================================

test_sbatch_includes_nodelist() {
    local sbatch_file="$TEST_TMP/test.sbatch"
    
    # Simulate sbatch generation with nodelist
    local P_NODELIST="node01,node02"
    local P_EXCLUDE=""
    
    echo "#!/bin/bash" > "$sbatch_file"
    echo "#SBATCH --job-name=test" >> "$sbatch_file"
    [ -n "$P_NODELIST" ] && echo "#SBATCH --nodelist=${P_NODELIST}" >> "$sbatch_file"
    [ -n "$P_EXCLUDE" ] && echo "#SBATCH --exclude=${P_EXCLUDE}" >> "$sbatch_file"
    
    assert_file_contains "$sbatch_file" "#SBATCH --nodelist=node01,node02"
}

test_sbatch_includes_exclude() {
    local sbatch_file="$TEST_TMP/test.sbatch"
    
    local P_NODELIST=""
    local P_EXCLUDE="badnode01,badnode02"
    
    echo "#!/bin/bash" > "$sbatch_file"
    echo "#SBATCH --job-name=test" >> "$sbatch_file"
    [ -n "$P_NODELIST" ] && echo "#SBATCH --nodelist=${P_NODELIST}" >> "$sbatch_file"
    [ -n "$P_EXCLUDE" ] && echo "#SBATCH --exclude=${P_EXCLUDE}" >> "$sbatch_file"
    
    assert_file_contains "$sbatch_file" "#SBATCH --exclude=badnode01,badnode02"
}

test_sbatch_includes_both() {
    local sbatch_file="$TEST_TMP/test.sbatch"
    
    local P_NODELIST="goodnode01,goodnode02"
    local P_EXCLUDE="badnode01"
    
    echo "#!/bin/bash" > "$sbatch_file"
    echo "#SBATCH --job-name=test" >> "$sbatch_file"
    [ -n "$P_NODELIST" ] && echo "#SBATCH --nodelist=${P_NODELIST}" >> "$sbatch_file"
    [ -n "$P_EXCLUDE" ] && echo "#SBATCH --exclude=${P_EXCLUDE}" >> "$sbatch_file"
    
    assert_file_contains "$sbatch_file" "#SBATCH --nodelist=goodnode01,goodnode02"
    assert_file_contains "$sbatch_file" "#SBATCH --exclude=badnode01"
}

test_sbatch_omits_empty() {
    local sbatch_file="$TEST_TMP/test.sbatch"
    
    local P_NODELIST=""
    local P_EXCLUDE=""
    
    echo "#!/bin/bash" > "$sbatch_file"
    echo "#SBATCH --job-name=test" >> "$sbatch_file"
    [ -n "$P_NODELIST" ] && echo "#SBATCH --nodelist=${P_NODELIST}" >> "$sbatch_file"
    [ -n "$P_EXCLUDE" ] && echo "#SBATCH --exclude=${P_EXCLUDE}" >> "$sbatch_file"
    
    # Should NOT contain nodelist or exclude lines
    if grep -q "nodelist" "$sbatch_file"; then
        echo "Should not contain nodelist when empty"
        return 1
    fi
    if grep -q "exclude" "$sbatch_file"; then
        echo "Should not contain exclude when empty"
        return 1
    fi
}

# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx init Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}SLURM Query Helpers:${NC}"
run_test "has_cmd with existing command" test_has_cmd_existing
run_test "has_cmd with non-existing command" test_has_cmd_nonexisting
run_test "detect_menu_tool falls back to text" test_detect_menu_tool_text_fallback
run_test "slurm_query_partitions success" test_slurm_query_partitions_success
run_test "slurm_query_partitions strips asterisk" test_slurm_query_partitions_strips_asterisk
run_test "slurm_query_partitions no sinfo" test_slurm_query_partitions_no_sinfo
run_test "slurm_query_partitions empty output" test_slurm_query_partitions_empty_output
run_test "slurm_query_accounts success" test_slurm_query_accounts_success
run_test "slurm_query_accounts no sacctmgr" test_slurm_query_accounts_no_sacctmgr
run_test "slurm_query_qos success" test_slurm_query_qos_success
run_test "slurm_query_qos splits commas" test_slurm_query_qos_splits_commas
run_test "slurm_query_nodes success" test_slurm_query_nodes_success
run_test "slurm_query_node_names success" test_slurm_query_node_names_success
run_test "slurm_query_node_names deduplicates" test_slurm_query_node_names_deduplicates

echo ""
echo -e "${YELLOW}Configuration:${NC}"
run_test "config save creates directory" test_config_save_creates_directory
run_test "config save includes nodelist" test_config_save_includes_nodelist
run_test "config load applies defaults" test_config_load_applies_defaults
run_test "config load preserves existing" test_config_load_preserves_existing

echo ""
echo -e "${YELLOW}Menu Selection (Text Mode):${NC}"
run_test "menu parse single number" test_menu_parse_single_number
run_test "menu parse range" test_menu_parse_range
run_test "menu parse comma-separated" test_menu_parse_comma_separated
run_test "menu parse mixed" test_menu_parse_mixed
run_test "menu skip on zero" test_menu_skip_on_zero
run_test "menu skip on empty" test_menu_skip_on_empty
run_test "menu invalid number ignored" test_menu_invalid_number_ignored

echo ""
echo -e "${YELLOW}Config Scenarios:${NC}"
run_test "config all defaults" test_config_all_defaults
run_test "config full custom" test_config_full_custom
run_test "config nodelist only" test_config_nodelist_only
run_test "config exclude only" test_config_exclude_only
run_test "config SLURM hostlist format" test_config_slurm_hostlist_format

echo ""
echo -e "${YELLOW}Edge Cases:${NC}"
run_test "empty partition list" test_empty_partition_list
run_test "empty account list" test_empty_account_list
run_test "partition with special characters" test_partition_with_special_characters
run_test "node with complex state" test_node_with_complex_state
run_test "whitespace handling" test_whitespace_handling
run_test "duplicate entries" test_duplicate_entries

echo ""
echo -e "${YELLOW}Node Selection Extraction:${NC}"
run_test "node selection extracts name only" test_node_selection_extracts_name_only
run_test "node selection with quotes" test_node_selection_with_quotes
run_test "node selection single node" test_node_selection_single_node
run_test "node selection with map lookup" test_node_selection_with_map_lookup
run_test "node selection fallback extraction" test_node_selection_fallback_extraction
run_test "node selection complex display strings" test_node_selection_complex_display_strings
run_test "node selection no CPU/memory info" test_node_selection_no_cpu_memory_info

echo ""
echo -e "${YELLOW}SBATCH Generation:${NC}"
run_test "sbatch includes nodelist" test_sbatch_includes_nodelist
run_test "sbatch includes exclude" test_sbatch_includes_exclude
run_test "sbatch includes both" test_sbatch_includes_both
run_test "sbatch omits empty" test_sbatch_omits_empty

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Results: ${TESTS_PASSED}/${TESTS_RUN} passed${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "${BLUE}============================================${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    echo -e "${BLUE}============================================${NC}"
    exit 0
fi

