#!/bin/bash
# End-to-end test suite for slx
# Tests the full workflow with mocked SLURM commands
# Run with: bash tests/test_e2e.sh

# Don't exit on first error - we handle errors in run_test
# set -e

# ============================================
# Test Framework
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Temporary test directory
TEST_TMP=""
MOCK_BIN=""

setup_test_env() {
    TEST_TMP=$(mktemp -d)
    export HOME="$TEST_TMP/home"
    export XDG_CONFIG_HOME="$TEST_TMP/config"
    export XDG_DATA_HOME="$TEST_TMP/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
    
    # Mock bin directory for SLURM command mocking
    MOCK_BIN="$TEST_TMP/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    
    # Create mock SLURM commands
    create_mock_slurm_commands
    
    # Copy slx to data directory (simulating install)
    mkdir -p "$XDG_DATA_HOME/slx"
    cp -r "$PROJECT_DIR/lib" "$XDG_DATA_HOME/slx/"
    cp -r "$PROJECT_DIR/templates" "$XDG_DATA_HOME/slx/"
    cp -r "$PROJECT_DIR/completions" "$XDG_DATA_HOME/slx/" 2>/dev/null || true
    
    # Create slx wrapper
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/slx" << 'WRAPPER'
#!/bin/bash
SLX_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/slx"
source "$SLX_DATA_DIR/lib/slx/common.sh"
load_config

# Source all command files
for cmd_file in "$SLX_DATA_DIR/lib/slx/commands"/*.sh; do
    [ -f "$cmd_file" ] && source "$cmd_file"
done

# Main command dispatch
case "$1" in
    init) shift; cmd_init "$@" ;;
    profile) shift; cmd_profile "$@" ;;
    project) shift; cmd_project "$@" ;;
    *) echo "Unknown command: $1" ;;
esac
WRAPPER
    chmod +x "$HOME/.local/bin/slx"
    
    # Add to path
    export PATH="$HOME/.local/bin:$PATH"
}

teardown_test_env() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

# Create mock SLURM commands
create_mock_slurm_commands() {
    # Mock sinfo - returns partition and node info
    cat > "$MOCK_BIN/sinfo" << 'EOF'
#!/bin/bash
# Check for specific output formats
if echo "$*" | grep -q '%P'; then
    # Partition query
    echo "cpu"
    echo "gpu"
    echo "rtx3090"
    echo "debug"
elif echo "$*" | grep -q '%N|%T|%c|%m|%G|%P'; then
    # Detailed node query
    echo "node01|idle|32|128000|(null)|cpu"
    echo "node02|allocated|32|128000|(null)|cpu"
    echo "node03|idle|64|256000|gpu:v100:4|gpu"
    echo "gpu-node-01|idle|128|512000|gpu:a100:8|rtx3090"
    echo "gpu-node-02|mixed|128|512000|gpu:a100:8|rtx3090"
elif echo "$*" | grep -q '%N|%T|%P'; then
    # Node with state and partition
    echo "node01|idle|cpu"
    echo "node02|allocated|cpu"
    echo "node03|idle|gpu"
    echo "gpu-node-01|idle|rtx3090"
    echo "gpu-node-02|mixed|rtx3090"
elif echo "$*" | grep -q '%N'; then
    # Simple node list
    echo "node01"
    echo "node02"
    echo "node03"
    echo "gpu-node-01"
    echo "gpu-node-02"
else
    # Default
    echo "node01|idle|cpu"
    echo "node02|allocated|cpu"
    echo "node03|idle|gpu"
fi
EOF
    chmod +x "$MOCK_BIN/sinfo"
    
    # Mock sacctmgr - returns account and QoS info
    cat > "$MOCK_BIN/sacctmgr" << 'EOF'
#!/bin/bash
case "$*" in
    *"format=account"*)
        echo "research"
        echo "teaching"
        echo "default"
        ;;
    *"format=qos"*)
        echo "normal,high,low"
        ;;
    *)
        echo ""
        ;;
esac
EOF
    chmod +x "$MOCK_BIN/sacctmgr"
    
    # Mock sbatch - returns job ID
    cat > "$MOCK_BIN/sbatch" << 'EOF'
#!/bin/bash
echo "Submitted batch job 12345678"
exit 0
EOF
    chmod +x "$MOCK_BIN/sbatch"
    
    # Mock squeue - returns job status
    cat > "$MOCK_BIN/squeue" << 'EOF'
#!/bin/bash
echo "JOBID     PARTITION  NAME       USER     ST  TIME      NODES NODELIST"
echo "12345678  gpu        test-job   testuser R   0:05      1     gpu-node-01"
EOF
    chmod +x "$MOCK_BIN/squeue"
    
    # Mock scancel
    cat > "$MOCK_BIN/scancel" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BIN/scancel"
}

# Assertion helpers
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

assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"
    
    if [ -d "$dir" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Directory not found: '$dir'"
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

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Exit code should match}"
    
    if [ "$expected" -eq "$actual" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Expected exit code: $expected"
        echo "  Actual exit code: $actual"
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
# E2E Tests: Configuration
# ============================================

test_e2e_config_creation() {
    # Source common.sh directly for testing
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    # Set config values
    SLX_WORKDIR="$HOME/workdir"
    SLX_PARTITION="gpu"
    SLX_ACCOUNT="research"
    SLX_QOS="normal"
    SLX_TIME="1440"
    SLX_NODES="1"
    SLX_NTASKS="1"
    SLX_CPUS="4"
    SLX_MEM="50000"
    SLX_GPUS="1"
    SLX_NODELIST=""
    SLX_EXCLUDE=""
    SLX_LOG_DIR="$SLX_WORKDIR/slurm/logs"
    
    # Save config
    save_config
    
    # Verify config file exists
    assert_file_exists "$SLX_CONFIG_FILE" "Config file should be created"
    
    # Verify config contains expected values
    assert_file_contains "$SLX_CONFIG_FILE" 'SLX_PARTITION="gpu"'
    assert_file_contains "$SLX_CONFIG_FILE" 'SLX_ACCOUNT="research"'
    assert_file_contains "$SLX_CONFIG_FILE" 'SLX_GPUS="1"'
}

test_e2e_config_load() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    # Create config manually
    mkdir -p "$SLX_CONFIG_DIR"
    cat > "$SLX_CONFIG_FILE" << 'EOF'
SLX_WORKDIR="/custom/workdir"
SLX_PARTITION="rtx3090"
SLX_ACCOUNT="teaching"
SLX_QOS="high"
SLX_TIME="2880"
SLX_NODES="2"
SLX_NTASKS="4"
SLX_CPUS="16"
SLX_MEM="128000"
SLX_GPUS="4"
SLX_NODELIST="gpu-node-01,gpu-node-02"
SLX_EXCLUDE="node01"
EOF
    
    # Load config
    load_config
    
    # Verify values loaded correctly
    assert_equals "/custom/workdir" "$SLX_WORKDIR"
    assert_equals "rtx3090" "$SLX_PARTITION"
    assert_equals "teaching" "$SLX_ACCOUNT"
    assert_equals "high" "$SLX_QOS"
    assert_equals "2880" "$SLX_TIME"
    assert_equals "2" "$SLX_NODES"
    assert_equals "4" "$SLX_NTASKS"
    assert_equals "16" "$SLX_CPUS"
    assert_equals "128000" "$SLX_MEM"
    assert_equals "4" "$SLX_GPUS"
    assert_equals "gpu-node-01,gpu-node-02" "$SLX_NODELIST"
    assert_equals "node01" "$SLX_EXCLUDE"
}

# ============================================
# E2E Tests: Profiles
# ============================================

test_e2e_profile_creation() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Set profile variables
    SLX_PROFILE_NAME="test-gpu-profile"
    SLX_PROFILE_DESC="Test GPU profile for large models"
    SLX_PROFILE_PARTITION="rtx3090"
    SLX_PROFILE_ACCOUNT="research"
    SLX_PROFILE_QOS="high"
    SLX_PROFILE_TIME="2880"
    SLX_PROFILE_NODES="2"
    SLX_PROFILE_NTASKS="8"
    SLX_PROFILE_CPUS="16"
    SLX_PROFILE_MEM="256000"
    SLX_PROFILE_GPUS="8"
    SLX_PROFILE_NODELIST="gpu-node-01,gpu-node-02"
    SLX_PROFILE_EXCLUDE=""
    
    # Save profile
    save_profile "test-gpu-profile"
    
    # Verify profile file exists
    local profile_file="$SLX_PROFILES_DIR/test-gpu-profile.env"
    assert_file_exists "$profile_file" "Profile file should be created"
    
    # Verify profile contents
    assert_file_contains "$profile_file" 'SLX_PROFILE_NAME="test-gpu-profile"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_PARTITION="rtx3090"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_GPUS="8"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_NODELIST="gpu-node-01,gpu-node-02"'
}

test_e2e_profile_load() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Create profile manually
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/cpu-debug.env" << 'EOF'
SLX_PROFILE_NAME="cpu-debug"
SLX_PROFILE_DESC="Quick CPU debug jobs"
SLX_PROFILE_PARTITION="debug"
SLX_PROFILE_ACCOUNT="default"
SLX_PROFILE_QOS="low"
SLX_PROFILE_TIME="30"
SLX_PROFILE_NODES="1"
SLX_PROFILE_NTASKS="1"
SLX_PROFILE_CPUS="2"
SLX_PROFILE_MEM="4000"
SLX_PROFILE_GPUS=""
SLX_PROFILE_NODELIST=""
SLX_PROFILE_EXCLUDE=""
EOF
    
    # Load profile
    load_profile "cpu-debug"
    
    # Verify values loaded correctly
    assert_equals "cpu-debug" "$SLX_PROFILE_NAME"
    assert_equals "Quick CPU debug jobs" "$SLX_PROFILE_DESC"
    assert_equals "debug" "$SLX_PROFILE_PARTITION"
    assert_equals "30" "$SLX_PROFILE_TIME"
    assert_equals "2" "$SLX_PROFILE_CPUS"
}

test_e2e_profile_list() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Create multiple profiles
    mkdir -p "$SLX_PROFILES_DIR"
    
    for profile in cpu-small gpu-large debug-quick; do
        cat > "$SLX_PROFILES_DIR/${profile}.env" << EOF
SLX_PROFILE_NAME="$profile"
SLX_PROFILE_DESC="Test profile $profile"
EOF
    done
    
    # List profiles
    local profiles=($(list_profiles))
    
    assert_equals "3" "${#profiles[@]}" "Should have 3 profiles"
    
    # Check each profile is in the list
    local found_cpu=false
    local found_gpu=false
    local found_debug=false
    
    for p in "${profiles[@]}"; do
        case "$p" in
            cpu-small) found_cpu=true ;;
            gpu-large) found_gpu=true ;;
            debug-quick) found_debug=true ;;
        esac
    done
    
    [ "$found_cpu" = true ] || { echo "Missing cpu-small profile"; return 1; }
    [ "$found_gpu" = true ] || { echo "Missing gpu-large profile"; return 1; }
    [ "$found_debug" = true ] || { echo "Missing debug-quick profile"; return 1; }
}

test_e2e_profile_delete() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Create profile
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/to-delete.env" << 'EOF'
SLX_PROFILE_NAME="to-delete"
EOF
    
    # Verify exists
    assert_file_exists "$SLX_PROFILES_DIR/to-delete.env"
    
    # Delete profile
    delete_profile "to-delete"
    
    # Verify deleted
    if [ -f "$SLX_PROFILES_DIR/to-delete.env" ]; then
        echo "Profile file should be deleted"
        return 1
    fi
}

# ============================================
# E2E Tests: Template Processing
# ============================================

test_e2e_template_processing() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local template_dir=$(find_template_dir)
    assert_dir_exists "$template_dir" "Template directory should exist"
    
    # Test sbatch template
    local result=$(process_template "$template_dir/job.sbatch.tmpl" \
        "JOB_NAME=test-job" \
        "PARTITION=gpu" \
        "ACCOUNT=research" \
        "QOS=normal" \
        "TIME=60" \
        "NODES=1" \
        "NTASKS=1" \
        "CPUS=4" \
        "MEM=8000" \
        "GPUS=1" \
        "NODELIST=gpu-node-01" \
        "EXCLUDE=" \
        "RUN_NAME=run")
    
    assert_contains "$result" "#SBATCH --job-name=test-job"
    assert_contains "$result" "#SBATCH --partition=gpu"
    assert_contains "$result" "#SBATCH --account=research"
    assert_contains "$result" "#SBATCH --time=60"
    assert_contains "$result" "#SBATCH --gpus=1"
    assert_contains "$result" "#SBATCH --nodelist=gpu-node-01"
    assert_contains "$result" "bash run.sh"
}

test_e2e_template_conditional_blocks() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local template_dir=$(find_template_dir)
    
    # Test without GPUS (should not include gpus line)
    # Note: Don't pass empty variables to process_template - just don't pass them at all
    local result=$(process_template "$template_dir/job.sbatch.tmpl" \
        "JOB_NAME=cpu-job" \
        "PARTITION=cpu" \
        "ACCOUNT=research" \
        "QOS=normal" \
        "TIME=60" \
        "NODES=1" \
        "NTASKS=1" \
        "CPUS=4" \
        "MEM=8000" \
        "RUN_NAME=run")
    
    # Should contain the required fields
    assert_contains "$result" "#SBATCH --job-name=cpu-job"
    assert_contains "$result" "#SBATCH --partition=cpu"
    
    # Should not contain gpus line with empty value
    if echo "$result" | grep -q "#SBATCH --gpus=$"; then
        echo "Should not contain gpus line with empty value"
        return 1
    fi
}

# ============================================
# E2E Tests: SLURM Query Functions
# ============================================

test_e2e_slurm_query_partitions() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local partitions=$(slurm_query_partitions)
    
    assert_contains "$partitions" "cpu" "Should contain cpu partition"
    assert_contains "$partitions" "gpu" "Should contain gpu partition"
    assert_contains "$partitions" "rtx3090" "Should contain rtx3090 partition"
    
    # Should strip asterisk from default partition
    if echo "$partitions" | grep -q '\*'; then
        echo "Should strip asterisk from partition names"
        return 1
    fi
}

test_e2e_slurm_query_accounts() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local accounts=$(slurm_query_accounts)
    
    assert_contains "$accounts" "research" "Should contain research account"
    assert_contains "$accounts" "teaching" "Should contain teaching account"
}

test_e2e_slurm_query_qos() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local qos=$(slurm_query_qos)
    
    assert_contains "$qos" "normal" "Should contain normal QoS"
    assert_contains "$qos" "high" "Should contain high QoS"
    assert_contains "$qos" "low" "Should contain low QoS"
}

test_e2e_slurm_query_nodes() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local nodes=$(slurm_query_nodes)
    
    assert_contains "$nodes" "node01" "Should contain node01"
    assert_contains "$nodes" "gpu-node-01" "Should contain gpu-node-01"
    assert_contains "$nodes" "idle" "Should contain idle state"
}

test_e2e_slurm_query_node_details() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local details=$(slurm_query_node_details)
    
    assert_contains "$details" "node01|idle|32|128000" "Should contain node01 details"
    assert_contains "$details" "gpu:a100:8" "Should contain GPU info"
}

# ============================================
# E2E Tests: Project Creation
# ============================================

test_e2e_project_directory_structure() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Setup workdir
    SLX_WORKDIR="$HOME/workdir"
    mkdir -p "$SLX_WORKDIR/projects"
    
    local project_name="test-project"
    local project_dir="$SLX_WORKDIR/projects/$project_name"
    
    # Create project structure manually (simulating project_new)
    mkdir -p "$project_dir/logs"
    
    # Generate sbatch file
    local template_dir=$(find_template_dir)
    process_template "$template_dir/job.sbatch.tmpl" \
        "JOB_NAME=$project_name" \
        "PARTITION=gpu" \
        "ACCOUNT=research" \
        "QOS=normal" \
        "TIME=1440" \
        "NODES=1" \
        "NTASKS=1" \
        "CPUS=4" \
        "MEM=50000" \
        "GPUS=1" \
        "NODELIST=" \
        "EXCLUDE=" \
        "RUN_NAME=run" > "$project_dir/run.sbatch"
    
    # Create run script
    cat > "$project_dir/run.sh" << 'EOF'
#!/bin/bash
echo "Hello from test-project!"
EOF
    chmod +x "$project_dir/run.sh"
    
    # Verify structure
    assert_dir_exists "$project_dir" "Project directory should exist"
    assert_dir_exists "$project_dir/logs" "Logs directory should exist"
    assert_file_exists "$project_dir/run.sbatch" "Sbatch file should exist"
    assert_file_exists "$project_dir/run.sh" "Run script should exist"
    
    # Verify sbatch contents
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --job-name=test-project"
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --partition=gpu"
    assert_file_contains "$project_dir/run.sbatch" "bash run.sh"
}

test_e2e_project_with_profile() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    load_config
    
    # Create a profile
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/gpu-large.env" << 'EOF'
SLX_PROFILE_NAME="gpu-large"
SLX_PROFILE_DESC="Large GPU jobs"
SLX_PROFILE_PARTITION="rtx3090"
SLX_PROFILE_ACCOUNT="research"
SLX_PROFILE_QOS="high"
SLX_PROFILE_TIME="2880"
SLX_PROFILE_NODES="2"
SLX_PROFILE_NTASKS="8"
SLX_PROFILE_CPUS="16"
SLX_PROFILE_MEM="256000"
SLX_PROFILE_GPUS="8"
SLX_PROFILE_NODELIST="gpu-node-01,gpu-node-02"
SLX_PROFILE_EXCLUDE=""
EOF
    
    # Load profile
    load_profile "gpu-large"
    
    # Simulate applying profile to project variables
    local P_PARTITION=""
    local P_ACCOUNT=""
    local P_QOS=""
    local P_TIME="1440"
    local P_NODES="1"
    local P_NTASKS="1"
    local P_CPUS="4"
    local P_MEM="50000"
    local P_GPUS=""
    local P_NODELIST=""
    local P_EXCLUDE=""
    
    apply_profile_to_project
    
    # Verify profile values were applied
    assert_equals "rtx3090" "$P_PARTITION"
    assert_equals "research" "$P_ACCOUNT"
    assert_equals "high" "$P_QOS"
    assert_equals "2880" "$P_TIME"
    assert_equals "2" "$P_NODES"
    assert_equals "8" "$P_NTASKS"
    assert_equals "16" "$P_CPUS"
    assert_equals "256000" "$P_MEM"
    assert_equals "8" "$P_GPUS"
    assert_equals "gpu-node-01,gpu-node-02" "$P_NODELIST"
}

# ============================================
# E2E Tests: Node Display Formatting
# ============================================

test_e2e_node_display_format() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    # Test format_node_display
    local display=$(format_node_display "gpu-node-01" "idle" "128" "512000" "gpu:a100:8" "rtx3090")
    
    assert_contains "$display" "gpu-node-01" "Should contain node name"
    assert_contains "$display" "[idle]" "Should contain state"
    assert_contains "$display" "cpu=128" "Should contain CPU count"
    assert_contains "$display" "mem=500G" "Should contain memory in GB"
    assert_contains "$display" "gpu=a100x8" "Should contain GPU info"
}

test_e2e_node_display_without_gpu() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    # Test CPU node without GPU
    local display=$(format_node_display "node01" "allocated" "32" "128000" "(null)" "cpu")
    
    assert_contains "$display" "node01" "Should contain node name"
    assert_contains "$display" "[allocated]" "Should contain state"
    assert_contains "$display" "cpu=32" "Should contain CPU count"
    
    # Should not contain GPU info
    if echo "$display" | grep -q "gpu="; then
        echo "Should not contain gpu info for CPU node"
        return 1
    fi
}

# ============================================
# E2E Tests: Menu Index Mapping
# ============================================

test_e2e_menu_index_to_option() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    local options=("cpu" "gpu" "rtx3090" "debug" "(manual entry)")
    
    # Simulate whiptail returning different indices
    for i in 0 1 2 3; do
        local choice_index="$i"
        local expected="${options[$i]}"
        
        if [[ "$choice_index" =~ ^[0-9]+$ ]] && [ "$choice_index" -ge 0 ] && [ "$choice_index" -lt ${#options[@]} ]; then
            local selected="${options[$choice_index]}"
            assert_equals "$expected" "$selected" "Index $i should map to $expected"
        else
            echo "Index $i validation failed"
            return 1
        fi
    done
}

# ============================================
# E2E Tests: Full Workflow Simulation
# ============================================

test_e2e_full_workflow() {
    source "$XDG_DATA_HOME/slx/lib/slx/common.sh"
    
    # Step 1: Initialize config
    SLX_WORKDIR="$HOME/workdir"
    SLX_PARTITION="gpu"
    SLX_ACCOUNT="research"
    SLX_QOS="normal"
    SLX_TIME="1440"
    SLX_NODES="1"
    SLX_NTASKS="1"
    SLX_CPUS="8"
    SLX_MEM="32000"
    SLX_GPUS="1"
    SLX_NODELIST=""
    SLX_EXCLUDE=""
    SLX_LOG_DIR="$SLX_WORKDIR/slurm/logs"
    
    save_config
    assert_file_exists "$SLX_CONFIG_FILE" "Step 1: Config should be saved"
    
    # Step 2: Create a profile
    SLX_PROFILE_NAME="ml-training"
    SLX_PROFILE_DESC="ML training jobs"
    SLX_PROFILE_PARTITION="rtx3090"
    SLX_PROFILE_ACCOUNT="research"
    SLX_PROFILE_QOS="high"
    SLX_PROFILE_TIME="4320"
    SLX_PROFILE_NODES="1"
    SLX_PROFILE_NTASKS="1"
    SLX_PROFILE_CPUS="16"
    SLX_PROFILE_MEM="128000"
    SLX_PROFILE_GPUS="4"
    SLX_PROFILE_NODELIST="gpu-node-01"
    SLX_PROFILE_EXCLUDE=""
    
    save_profile "ml-training"
    assert_file_exists "$SLX_PROFILES_DIR/ml-training.env" "Step 2: Profile should be saved"
    
    # Step 3: Create a project using the profile
    mkdir -p "$SLX_WORKDIR/projects/my-ml-project/logs"
    
    # Load and apply profile
    load_profile "ml-training"
    
    local P_PARTITION=""
    local P_ACCOUNT=""
    local P_QOS=""
    local P_TIME="1440"
    local P_NODES="1"
    local P_NTASKS="1"
    local P_CPUS="4"
    local P_MEM="50000"
    local P_GPUS=""
    local P_NODELIST=""
    local P_EXCLUDE=""
    
    apply_profile_to_project
    
    # Generate sbatch
    local template_dir=$(find_template_dir)
    local project_dir="$SLX_WORKDIR/projects/my-ml-project"
    
    process_template "$template_dir/job.sbatch.tmpl" \
        "JOB_NAME=my-ml-project" \
        "PARTITION=$P_PARTITION" \
        "ACCOUNT=$P_ACCOUNT" \
        "QOS=$P_QOS" \
        "TIME=$P_TIME" \
        "NODES=$P_NODES" \
        "NTASKS=$P_NTASKS" \
        "CPUS=$P_CPUS" \
        "MEM=$P_MEM" \
        "GPUS=$P_GPUS" \
        "NODELIST=$P_NODELIST" \
        "EXCLUDE=$P_EXCLUDE" \
        "RUN_NAME=run" > "$project_dir/run.sbatch"
    
    cat > "$project_dir/run.sh" << 'EOF'
#!/bin/bash
echo "Training ML model..."
python train.py
EOF
    chmod +x "$project_dir/run.sh"
    
    # Verify final state
    assert_file_exists "$project_dir/run.sbatch" "Step 3: Sbatch should be created"
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --partition=rtx3090" "Should use profile partition"
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --gpus=4" "Should use profile GPUs"
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --nodelist=gpu-node-01" "Should use profile nodelist"
    assert_file_contains "$project_dir/run.sbatch" "#SBATCH --time=4320" "Should use profile time"
}

# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx End-to-End Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}Configuration Tests:${NC}"
run_test "config creation" test_e2e_config_creation
run_test "config load" test_e2e_config_load

echo ""
echo -e "${YELLOW}Profile Tests:${NC}"
run_test "profile creation" test_e2e_profile_creation
run_test "profile load" test_e2e_profile_load
run_test "profile list" test_e2e_profile_list
run_test "profile delete" test_e2e_profile_delete

echo ""
echo -e "${YELLOW}Template Processing Tests:${NC}"
run_test "template processing" test_e2e_template_processing
run_test "template conditional blocks" test_e2e_template_conditional_blocks

echo ""
echo -e "${YELLOW}SLURM Query Tests:${NC}"
run_test "query partitions" test_e2e_slurm_query_partitions
run_test "query accounts" test_e2e_slurm_query_accounts
run_test "query QoS" test_e2e_slurm_query_qos
run_test "query nodes" test_e2e_slurm_query_nodes
run_test "query node details" test_e2e_slurm_query_node_details

echo ""
echo -e "${YELLOW}Project Tests:${NC}"
run_test "project directory structure" test_e2e_project_directory_structure
run_test "project with profile" test_e2e_project_with_profile

echo ""
echo -e "${YELLOW}Node Display Tests:${NC}"
run_test "node display format" test_e2e_node_display_format
run_test "node display without GPU" test_e2e_node_display_without_gpu

echo ""
echo -e "${YELLOW}Menu Tests:${NC}"
run_test "menu index to option mapping" test_e2e_menu_index_to_option

echo ""
echo -e "${YELLOW}Full Workflow Tests:${NC}"
run_test "full workflow simulation" test_e2e_full_workflow

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

