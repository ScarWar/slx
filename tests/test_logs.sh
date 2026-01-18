#!/bin/bash
# Test suite for slx logs command
# Tests log path resolution from SLURM job metadata and fallback behavior
# Run with: bash tests/test_logs.sh

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
    
    # Mock bin directory for scontrol mocking
    MOCK_BIN="$TEST_TMP/mock_bin"
    mkdir -p "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    
    # Source common.sh and logs.sh for testing
    source "$PROJECT_DIR/lib/slx/common.sh"
    source "$PROJECT_DIR/lib/slx/commands/logs.sh"
    
    # Initialize config
    load_config
    SLX_WORKDIR="$TEST_TMP/workdir"
    SLX_LOG_DIR="$SLX_WORKDIR/slurm/logs"
    mkdir -p "$SLX_LOG_DIR"
    mkdir -p "$SLX_WORKDIR/projects"
}

teardown_test_env() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

# Create mock scontrol that returns job info
create_mock_scontrol() {
    local stdout_path="$1"
    local stderr_path="$2"
    local work_dir="$3"
    local job_name="$4"
    local job_id="${5:-12345678}"
    
    cat > "$MOCK_BIN/scontrol" << EOF
#!/bin/bash
if [[ "\$*" == *"show job"* ]]; then
    job_arg="\$(echo "\$*" | grep -oP '\d+\$' || echo "$job_id")"
    echo "JobId=\$job_arg JobName=$job_name UserId=testuser(1000) GroupId=testgroup(1000) WorkDir=$work_dir StdErr=$stderr_path StdIn=/dev/null StdOut=$stdout_path"
else
    echo "Usage: scontrol show job <job_id>"
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN/scontrol"
}

create_mock_scontrol_invalid_job() {
    cat > "$MOCK_BIN/scontrol" << 'EOF'
#!/bin/bash
echo "slurm_load_jobs error: Invalid job id specified"
exit 1
EOF
    chmod +x "$MOCK_BIN/scontrol"
}

remove_mock_scontrol() {
    rm -f "$MOCK_BIN/scontrol"
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

assert_array_length() {
    local array_name="$1"
    local expected_length="$2"
    local message="${3:-Array should have expected length}"
    
    local actual_length
    eval "actual_length=\${#${array_name}[@]}"
    
    if [ "$actual_length" -eq "$expected_length" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Expected length: $expected_length"
        echo "  Actual length: $actual_length"
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
# Tests: resolve_job_log_paths
# ============================================

test_resolve_with_absolute_paths() {
    local work_dir="$TEST_TMP/project"
    mkdir -p "$work_dir/logs"
    
    echo "stdout content" > "$work_dir/logs/test-job_12345678.out"
    echo "stderr content" > "$work_dir/logs/test-job_12345678.err"
    
    create_mock_scontrol \
        "$work_dir/logs/test-job_12345678.out" \
        "$work_dir/logs/test-job_12345678.err" \
        "$work_dir" \
        "test-job"
    
    resolve_job_log_paths "12345678"
    local result=$?
    
    assert_equals "0" "$result" "Should return success"
    assert_array_length "RESOLVED_LOG_FILES" "2" "Should find 2 log files"
}

test_resolve_with_pattern_expansion_x() {
    local work_dir="$TEST_TMP/project"
    mkdir -p "$work_dir/logs"
    
    echo "stdout content" > "$work_dir/logs/myjob_12345678.out"
    echo "stderr content" > "$work_dir/logs/myjob_12345678.err"
    
    create_mock_scontrol \
        "logs/%x_%j.out" \
        "logs/%x_%j.err" \
        "$work_dir" \
        "myjob"
    
    resolve_job_log_paths "12345678"
    local result=$?
    
    assert_equals "0" "$result" "Should return success"
    assert_array_length "RESOLVED_LOG_FILES" "2" "Should find 2 log files"
}

test_resolve_deduplicates_same_file() {
    local work_dir="$TEST_TMP/project"
    mkdir -p "$work_dir/logs"
    
    echo "combined output" > "$work_dir/logs/combined_12345678.log"
    
    create_mock_scontrol \
        "$work_dir/logs/combined_12345678.log" \
        "$work_dir/logs/combined_12345678.log" \
        "$work_dir" \
        "myjob"
    
    resolve_job_log_paths "12345678"
    local result=$?
    
    assert_equals "0" "$result" "Should return success"
    assert_array_length "RESOLVED_LOG_FILES" "1" "Should deduplicate to 1 file"
}

test_resolve_fails_when_no_scontrol() {
    remove_mock_scontrol
    local old_path="$PATH"
    export PATH="$MOCK_BIN"
    
    resolve_job_log_paths "12345678"
    local result=$?
    
    export PATH="$old_path"
    
    assert_equals "1" "$result" "Should return failure when scontrol not available"
}

test_resolve_fails_for_invalid_job() {
    create_mock_scontrol_invalid_job
    
    resolve_job_log_paths "99999999"
    local result=$?
    
    assert_equals "1" "$result" "Should return failure for invalid job"
}

# ============================================
# Tests: search_log_files_by_pattern (fallback)
# ============================================

test_fallback_finds_project_logs() {
    local proj_dir="$SLX_WORKDIR/projects/test-project"
    mkdir -p "$proj_dir/logs"
    
    echo "stdout" > "$proj_dir/logs/test_12345678.out"
    echo "stderr" > "$proj_dir/logs/test_12345678.err"
    
    search_log_files_by_pattern "12345678"
    
    assert_array_length "SEARCHED_LOG_FILES" "2" "Should find 2 log files"
}

test_fallback_finds_slx_log_dir() {
    mkdir -p "$SLX_LOG_DIR"
    
    echo "stdout" > "$SLX_LOG_DIR/job_12345678.out"
    echo "stderr" > "$SLX_LOG_DIR/job_12345678.err"
    
    search_log_files_by_pattern "12345678"
    
    assert_array_length "SEARCHED_LOG_FILES" "2" "Should find 2 log files"
}

# ============================================
# Tests: view_logs integration
# ============================================

test_view_logs_uses_scontrol_when_available() {
    local work_dir="$TEST_TMP/project"
    mkdir -p "$work_dir/logs"
    
    echo "This is stdout from scontrol path" > "$work_dir/logs/resolved_12345678.out"
    
    create_mock_scontrol \
        "$work_dir/logs/resolved_12345678.out" \
        "$work_dir/logs/resolved_12345678.out" \
        "$work_dir" \
        "resolved"
    
    local output
    output=$( ( view_logs "12345678" ) 2>&1)
    
    assert_contains "$output" "This is stdout from scontrol path" "Should show resolved log content"
}

test_view_logs_falls_back_to_pattern() {
    remove_mock_scontrol
    local old_path="$PATH"
    export PATH="$MOCK_BIN:/bin:/usr/bin"
    
    local proj_dir="$SLX_WORKDIR/projects/fallback-project"
    mkdir -p "$proj_dir/logs"
    echo "Fallback log content" > "$proj_dir/logs/job_87654321.out"
    
    local output
    output=$( ( view_logs "87654321" ) 2>&1)
    
    export PATH="$old_path"
    
    assert_contains "$output" "Fallback log content" "Should show fallback log content"
}

test_view_logs_shows_error_when_no_logs() {
    remove_mock_scontrol
    local old_path="$PATH"
    export PATH="$MOCK_BIN:/bin:/usr/bin"
    
    # Run view_logs in a subshell to capture exit code without killing test
    local result=0
    ( view_logs "99999999" >/dev/null 2>&1 ) || result=$?
    
    export PATH="$old_path"
    
    assert_equals "1" "$result" "Should exit with error when no logs found"
}


# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx Logs Command Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}Log Path Resolution Tests:${NC}"
run_test "resolve with absolute paths" test_resolve_with_absolute_paths
run_test "resolve with %x pattern expansion" test_resolve_with_pattern_expansion_x
run_test "resolve deduplicates same file" test_resolve_deduplicates_same_file
run_test "resolve fails when no scontrol" test_resolve_fails_when_no_scontrol
run_test "resolve fails for invalid job" test_resolve_fails_for_invalid_job

echo ""
echo -e "${YELLOW}Fallback Pattern Search Tests:${NC}"
run_test "fallback finds project logs" test_fallback_finds_project_logs
run_test "fallback finds SLX log dir" test_fallback_finds_slx_log_dir

echo ""
echo -e "${YELLOW}view_logs Integration Tests:${NC}"
run_test "view_logs uses scontrol when available" test_view_logs_uses_scontrol_when_available
run_test "view_logs falls back to pattern" test_view_logs_falls_back_to_pattern
run_test "view_logs shows error when no logs" test_view_logs_shows_error_when_no_logs

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
