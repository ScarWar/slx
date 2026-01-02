#!/bin/bash
# Test suite for slx profile functionality
# Run with: bash tests/test_profiles.sh

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

setup_test_env() {
    TEST_TMP=$(mktemp -d)
    export HOME="$TEST_TMP/home"
    export XDG_CONFIG_HOME="$TEST_TMP/config"
    export XDG_DATA_HOME="$TEST_TMP/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
    
    # Source common.sh for profile functions
    source "$PROJECT_DIR/lib/slx/common.sh"
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

assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist}"
    
    if [ ! -f "$file" ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  File should not exist: '$file'"
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
# Profile Helper Tests
# ============================================

test_sanitize_profile_name_basic() {
    local result=$(sanitize_profile_name "My Profile")
    assert_equals "my_profile" "$result" "Should convert to lowercase and replace spaces"
}

test_sanitize_profile_name_special_chars() {
    local result=$(sanitize_profile_name "gpu@large!test#123")
    assert_equals "gpulargetest123" "$result" "Should remove special characters"
}

test_sanitize_profile_name_preserves_valid() {
    local result=$(sanitize_profile_name "gpu-large_v2")
    assert_equals "gpu-large_v2" "$result" "Should preserve dashes and underscores"
}

test_list_profiles_empty() {
    local profiles=($(list_profiles))
    assert_equals "0" "${#profiles[@]}" "Should return empty array when no profiles"
}

test_list_profiles_finds_profiles() {
    mkdir -p "$SLX_PROFILES_DIR"
    touch "$SLX_PROFILES_DIR/gpu-large.env"
    touch "$SLX_PROFILES_DIR/cpu-small.env"
    touch "$SLX_PROFILES_DIR/debug.env"
    
    local profiles=($(list_profiles))
    assert_equals "3" "${#profiles[@]}" "Should find 3 profiles"
}

test_profile_exists_true() {
    mkdir -p "$SLX_PROFILES_DIR"
    touch "$SLX_PROFILES_DIR/test-profile.env"
    
    if profile_exists "test-profile"; then
        return 0
    else
        echo "Profile should exist"
        return 1
    fi
}

test_profile_exists_false() {
    if profile_exists "nonexistent"; then
        echo "Profile should not exist"
        return 1
    else
        return 0
    fi
}

test_save_profile_creates_file() {
    SLX_PROFILE_NAME="test-profile"
    SLX_PROFILE_DESC="Test description"
    SLX_PROFILE_PARTITION="gpu"
    SLX_PROFILE_ACCOUNT="research"
    SLX_PROFILE_QOS="normal"
    SLX_PROFILE_TIME="1440"
    SLX_PROFILE_NODES="1"
    SLX_PROFILE_NTASKS="1"
    SLX_PROFILE_CPUS="8"
    SLX_PROFILE_MEM="64000"
    SLX_PROFILE_GPUS="2"
    SLX_PROFILE_NODELIST="node01,node02"
    SLX_PROFILE_EXCLUDE="node03"
    
    save_profile "test-profile" > /dev/null
    
    assert_file_exists "$SLX_PROFILES_DIR/test-profile.env" "Profile file should be created"
}

test_save_profile_contains_values() {
    SLX_PROFILE_NAME="test-profile"
    SLX_PROFILE_DESC="My test profile"
    SLX_PROFILE_PARTITION="gpu-rtx"
    SLX_PROFILE_GPUS="4"
    
    save_profile "test-profile" > /dev/null
    
    local profile_file="$SLX_PROFILES_DIR/test-profile.env"
    assert_file_contains "$profile_file" 'SLX_PROFILE_NAME="test-profile"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_DESC="My test profile"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_PARTITION="gpu-rtx"'
    assert_file_contains "$profile_file" 'SLX_PROFILE_GPUS="4"'
}

test_load_profile_sets_variables() {
    mkdir -p "$SLX_PROFILES_DIR"
    cat > "$SLX_PROFILES_DIR/test-profile.env" << 'EOF'
SLX_PROFILE_NAME="test-profile"
SLX_PROFILE_DESC="Test profile"
SLX_PROFILE_PARTITION="gpu"
SLX_PROFILE_CPUS="16"
SLX_PROFILE_MEM="128000"
SLX_PROFILE_GPUS="4"
EOF
    
    load_profile "test-profile"
    
    assert_equals "test-profile" "$SLX_PROFILE_NAME" "Name should be loaded"
    assert_equals "gpu" "$SLX_PROFILE_PARTITION" "Partition should be loaded"
    assert_equals "16" "$SLX_PROFILE_CPUS" "CPUs should be loaded"
    assert_equals "128000" "$SLX_PROFILE_MEM" "Memory should be loaded"
    assert_equals "4" "$SLX_PROFILE_GPUS" "GPUs should be loaded"
}

test_load_profile_fails_for_nonexistent() {
    if load_profile "nonexistent" 2>/dev/null; then
        echo "Should fail for nonexistent profile"
        return 1
    else
        return 0
    fi
}

test_delete_profile_removes_file() {
    mkdir -p "$SLX_PROFILES_DIR"
    touch "$SLX_PROFILES_DIR/to-delete.env"
    
    delete_profile "to-delete" > /dev/null
    
    assert_file_not_exists "$SLX_PROFILES_DIR/to-delete.env" "Profile file should be deleted"
}

test_apply_profile_to_project() {
    # Set up profile variables
    SLX_PROFILE_PARTITION="gpu-rtx"
    SLX_PROFILE_CPUS="32"
    SLX_PROFILE_MEM="256000"
    SLX_PROFILE_GPUS="8"
    SLX_PROFILE_NODELIST="node01,node02"
    
    # Set initial project variables
    P_PARTITION="cpu"
    P_CPUS="4"
    P_MEM="8000"
    P_GPUS=""
    P_NODELIST=""
    
    # Apply profile
    apply_profile_to_project
    
    # Verify project variables were updated
    assert_equals "gpu-rtx" "$P_PARTITION" "Partition should be updated from profile"
    assert_equals "32" "$P_CPUS" "CPUs should be updated from profile"
    assert_equals "256000" "$P_MEM" "Memory should be updated from profile"
    assert_equals "8" "$P_GPUS" "GPUs should be updated from profile"
    assert_equals "node01,node02" "$P_NODELIST" "NodeList should be updated from profile"
}

test_apply_profile_preserves_unset() {
    # Set only some profile variables
    SLX_PROFILE_PARTITION="gpu"
    SLX_PROFILE_CPUS=""  # Not set
    SLX_PROFILE_MEM=""   # Not set
    SLX_PROFILE_GPUS="2"
    
    # Set initial project variables
    P_PARTITION="cpu"
    P_CPUS="8"
    P_MEM="16000"
    P_GPUS="1"
    
    # Apply profile
    apply_profile_to_project
    
    # Verify only set values were updated
    assert_equals "gpu" "$P_PARTITION" "Partition should be updated"
    assert_equals "8" "$P_CPUS" "CPUs should be preserved (profile empty)"
    assert_equals "16000" "$P_MEM" "Memory should be preserved (profile empty)"
    assert_equals "2" "$P_GPUS" "GPUs should be updated"
}

# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx Profile Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}Profile Name Sanitization:${NC}"
run_test "basic name sanitization" test_sanitize_profile_name_basic
run_test "special character removal" test_sanitize_profile_name_special_chars
run_test "preserves valid characters" test_sanitize_profile_name_preserves_valid

echo ""
echo -e "${YELLOW}Profile Listing:${NC}"
run_test "empty profile list" test_list_profiles_empty
run_test "finds existing profiles" test_list_profiles_finds_profiles

echo ""
echo -e "${YELLOW}Profile Existence:${NC}"
run_test "profile exists (true)" test_profile_exists_true
run_test "profile exists (false)" test_profile_exists_false

echo ""
echo -e "${YELLOW}Profile Save:${NC}"
run_test "creates profile file" test_save_profile_creates_file
run_test "saves correct values" test_save_profile_contains_values

echo ""
echo -e "${YELLOW}Profile Load:${NC}"
run_test "loads profile variables" test_load_profile_sets_variables
run_test "fails for nonexistent" test_load_profile_fails_for_nonexistent

echo ""
echo -e "${YELLOW}Profile Delete:${NC}"
run_test "removes profile file" test_delete_profile_removes_file

echo ""
echo -e "${YELLOW}Profile Application:${NC}"
run_test "applies to project variables" test_apply_profile_to_project
run_test "preserves unset values" test_apply_profile_preserves_unset

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

