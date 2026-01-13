#!/bin/bash
# Test suite for slx run command
# Run with: bash tests/test_run.sh

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
    
    # Mock bin directory for srun/sbatch mocking
    MOCK_BIN="$TEST_TMP/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    
    # Create mock SLURM commands that capture args
    create_mock_slurm_commands
    
    # Source common.sh and run.sh for testing
    source "$PROJECT_DIR/lib/slx/common.sh"
    source "$PROJECT_DIR/lib/slx/commands/profile.sh"
    source "$PROJECT_DIR/lib/slx/commands/run.sh"
    
    # Initialize config
    load_config
    SLX_WORKDIR="$TEST_TMP/workdir"
    SLX_LOG_DIR="$SLX_WORKDIR/slurm/logs"
    mkdir -p "$SLX_LOG_DIR"
}

teardown_test_env() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

# Create mock srun/sbatch that capture arguments
create_mock_slurm_commands() {
    # Mock srun that records args to a file
    cat > "$MOCK_BIN/srun" << 'EOF'
#!/bin/bash
# Record all arguments to a file for testing
echo "$@" > "${MOCK_BIN}/srun_args.txt"
# If --pty is present, record it specially
if [[ " $* " == *" --pty "* ]]; then
    echo "interactive" > "${MOCK_BIN}/srun_mode.txt"
else
    echo "command" > "${MOCK_BIN}/srun_mode.txt"
fi
exit 0
EOF
    chmod +x "$MOCK_BIN/srun"
    
    # Mock sbatch that records args and returns a job ID
    cat > "$MOCK_BIN/sbatch" << 'EOF'
#!/bin/bash
# Record the script path
echo "$@" > "${MOCK_BIN}/sbatch_args.txt"
# If a script was passed, capture its contents
for arg in "$@"; do
    if [[ -f "$arg" ]]; then
        cp "$arg" "${MOCK_BIN}/sbatch_script.txt"
    fi
done
echo "Submitted batch job 12345678"
exit 0
EOF
    chmod +x "$MOCK_BIN/sbatch"
    
    # Export MOCK_BIN for use in scripts
    export MOCK_BIN
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
# Run Command Tests - srun mode
# ============================================

test_run_srun_with_command() {
    # Run a command via srun
    run_srun "echo" "hello"
    
    assert_file_exists "$MOCK_BIN/srun_args.txt" "srun should have been called"
    
    local args=$(cat "$MOCK_BIN/srun_args.txt")
    assert_contains "$args" "echo" "Should contain the command"
    assert_contains "$args" "hello" "Should contain command args"
}

test_run_srun_interactive_shell() {
    # Run without command - should start interactive shell
    run_srun
    
    assert_file_exists "$MOCK_BIN/srun_mode.txt" "srun should have been called"
    
    local mode=$(cat "$MOCK_BIN/srun_mode.txt")
    assert_equals "interactive" "$mode" "Should be in interactive mode"
    
    local args=$(cat "$MOCK_BIN/srun_args.txt")
    assert_contains "$args" "--pty" "Should have --pty flag"
    assert_contains "$args" "bash" "Should run bash"
}

test_run_srun_with_profile() {
    # Create a profile
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/test-profile.env" << 'EOF'
SLX_PROFILE_NAME="test-profile"
SLX_PROFILE_PARTITION="gpu"
SLX_PROFILE_ACCOUNT="research"
SLX_PROFILE_CPUS="8"
SLX_PROFILE_GPUS="2"
EOF
    
    # Load and apply profile
    load_profile "test-profile"
    apply_profile_to_project
    
    # Run command
    run_srun "nvidia-smi"
    
    local args=$(cat "$MOCK_BIN/srun_args.txt")
    assert_contains "$args" "--partition=gpu" "Should have partition from profile"
    assert_contains "$args" "--account=research" "Should have account from profile"
    assert_contains "$args" "--cpus-per-task=8" "Should have cpus from profile"
    assert_contains "$args" "--gpus=2" "Should have gpus from profile"
}

# ============================================
# Run Command Tests - sbatch mode
# ============================================

test_run_sbatch_with_command() {
    # Run a command via sbatch
    run_sbatch "python" "train.py" "--epochs=10"
    
    assert_file_exists "$MOCK_BIN/sbatch_script.txt" "sbatch script should be created"
    
    local script=$(cat "$MOCK_BIN/sbatch_script.txt")
    assert_contains "$script" "#!/bin/bash" "Should have shebang"
    assert_contains "$script" "#SBATCH --job-name=" "Should have job name"
    assert_contains "$script" "exec python" "Should exec the command"
    assert_contains "$script" "train.py" "Should have script name"
    assert_contains "$script" "--epochs=10" "Should have script args"
}

test_run_sbatch_no_command_fails() {
    # sbatch without command should fail
    local result=0
    run_sbatch 2>/dev/null || result=$?
    
    if [ $result -eq 0 ]; then
        echo "sbatch without command should fail"
        return 1
    fi
    return 0
}

test_run_sbatch_with_profile() {
    # Create a profile
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/gpu-large.env" << 'EOF'
SLX_PROFILE_NAME="gpu-large"
SLX_PROFILE_PARTITION="rtx3090"
SLX_PROFILE_ACCOUNT="ml-research"
SLX_PROFILE_TIME="2880"
SLX_PROFILE_CPUS="16"
SLX_PROFILE_MEM="128000"
SLX_PROFILE_GPUS="4"
SLX_PROFILE_NODELIST="gpu-node-01"
EOF
    
    # Load and apply profile
    load_profile "gpu-large"
    apply_profile_to_project
    
    # Run command
    run_sbatch "./train.sh"
    
    local script=$(cat "$MOCK_BIN/sbatch_script.txt")
    assert_contains "$script" "#SBATCH --partition=rtx3090" "Should have partition from profile"
    assert_contains "$script" "#SBATCH --account=ml-research" "Should have account from profile"
    assert_contains "$script" "#SBATCH --time=2880" "Should have time from profile"
    assert_contains "$script" "#SBATCH --cpus-per-task=16" "Should have cpus from profile"
    assert_contains "$script" "#SBATCH --mem=128000" "Should have mem from profile"
    assert_contains "$script" "#SBATCH --gpus=4" "Should have gpus from profile"
    assert_contains "$script" "#SBATCH --nodelist=gpu-node-01" "Should have nodelist from profile"
}

test_run_sbatch_log_paths() {
    # Run command
    run_sbatch "echo" "test"
    
    local script=$(cat "$MOCK_BIN/sbatch_script.txt")
    assert_contains "$script" "#SBATCH --output=" "Should have output directive"
    assert_contains "$script" "#SBATCH --error=" "Should have error directive"
    assert_contains "$script" ".out" "Output should be .out file"
    assert_contains "$script" ".err" "Error should be .err file"
}

test_run_sbatch_preserves_cwd() {
    # Run command
    run_sbatch "ls" "-la"
    
    local script=$(cat "$MOCK_BIN/sbatch_script.txt")
    assert_contains "$script" "cd " "Should have cd command"
}

# ============================================
# cmd_run Tests (integration)
# ============================================

test_cmd_run_invalid_mode_fails() {
    local result=0
    cmd_run --mode invalid echo test 2>/dev/null || result=$?
    
    if [ $result -eq 0 ]; then
        echo "Invalid mode should fail"
        return 1
    fi
    return 0
}

test_cmd_run_invalid_profile_fails() {
    local result=0
    cmd_run --profile nonexistent echo test 2>/dev/null || result=$?
    
    if [ $result -eq 0 ]; then
        echo "Invalid profile should fail"
        return 1
    fi
    return 0
}

test_cmd_run_help() {
    local output
    output=$(cmd_run --help 2>&1)
    
    assert_contains "$output" "slx run" "Help should mention slx run"
    assert_contains "$output" "--profile" "Help should mention --profile"
    assert_contains "$output" "--mode" "Help should mention --mode"
    assert_contains "$output" "srun" "Help should mention srun"
    assert_contains "$output" "sbatch" "Help should mention sbatch"
}

# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx Run Command Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}srun Mode Tests:${NC}"
run_test "srun with command" test_run_srun_with_command
run_test "srun interactive shell" test_run_srun_interactive_shell
run_test "srun with profile" test_run_srun_with_profile

echo ""
echo -e "${YELLOW}sbatch Mode Tests:${NC}"
run_test "sbatch with command" test_run_sbatch_with_command
run_test "sbatch no command fails" test_run_sbatch_no_command_fails
run_test "sbatch with profile" test_run_sbatch_with_profile
run_test "sbatch log paths" test_run_sbatch_log_paths
run_test "sbatch preserves cwd" test_run_sbatch_preserves_cwd

echo ""
echo -e "${YELLOW}cmd_run Integration Tests:${NC}"
run_test "invalid mode fails" test_cmd_run_invalid_mode_fails
run_test "invalid profile fails" test_cmd_run_invalid_profile_fails
run_test "help output" test_cmd_run_help

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
