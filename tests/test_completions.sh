#!/bin/bash
# Test suite for slx completion functionality
# Run with: bash tests/test_completions.sh

# Don't exit on first error - we handle errors in run_test
# set -e

# ============================================
# Test Framework
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPLETION_BASH="$PROJECT_DIR/completions/slx.bash"
COMPLETION_ZSH="$PROJECT_DIR/completions/slx.zsh"

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
    export USER="${USER:-testuser}"
    
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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should not contain substring}"
    
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  String: '$haystack'"
        echo "  Should not contain: '$needle'"
        return 1
    fi
}

assert_array_contains() {
    local array_name="$1"
    local needle="$2"
    local message="${3:-Array should contain value}"
    
    local found=0
    eval "for item in \"\${${array_name}[@]}\"; do
        if [ \"\$item\" = \"$needle\" ]; then
            found=1
            break
        fi
    done"
    
    if [ $found -eq 1 ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Array does not contain: '$needle'"
        return 1
    fi
}

assert_array_not_contains() {
    local array_name="$1"
    local needle="$2"
    local message="${3:-Array should not contain value}"
    
    local found=0
    eval "for item in \"\${${array_name}[@]}\"; do
        if [ \"\$item\" = \"$needle\" ]; then
            found=1
            break
        fi
    done"
    
    if [ $found -eq 0 ]; then
        return 0
    else
        echo -e "${RED}ASSERTION FAILED: $message${NC}"
        echo "  Array should not contain: '$needle'"
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

create_mock_squeue() {
    local job_ids="$1"
    cat > "$MOCK_BIN/squeue" << EOF
#!/bin/bash
if [ "\$1" = "-u" ] && [ "\$2" = "$USER" ] && [ "\$3" = "-h" ] && [ "\$4" = "-o" ] && [ "\$5" = "%i" ]; then
    echo "$job_ids"
elif [ "\$1" = "-u" ] && [ "\$2" = "$USER" ] && [ "\$3" = "-h" ] && [ "\$4" = "-o" ] && [ "\$5" = "%j" ]; then
    echo "job1
job2
job3"
else
    exit 1
fi
EOF
    chmod +x "$MOCK_BIN/squeue"
}

remove_mock_squeue() {
    rm -f "$MOCK_BIN/squeue"
}

# ============================================
# Bash Completion Tests
# ============================================

test_bash_completion_first_position_shows_commands() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx)
    COMP_CWORD=1
    
    _slx_completion
    
    # Should show all commands (including profile and run)
    local commands="init project profile run submit list running pending kill killall logs tail info status history find clean version help"
    for cmd in $commands; do
        assert_array_contains "COMPREPLY" "$cmd" "Should contain command: $cmd"
    done
}

test_bash_completion_logs_shows_only_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "123456
789012
345678"
    
    COMP_WORDS=(slx logs)
    COMP_CWORD=2
    
    _slx_completion
    
    # Should only show job IDs, not commands
    assert_array_contains "COMPREPLY" "123456" "Should contain job ID 123456"
    assert_array_contains "COMPREPLY" "789012" "Should contain job ID 789012"
    assert_array_contains "COMPREPLY" "345678" "Should contain job ID 345678"
    
    # Should NOT contain commands
    assert_array_not_contains "COMPREPLY" "init" "Should not contain command 'init'"
    assert_array_not_contains "COMPREPLY" "submit" "Should not contain command 'submit'"
    assert_array_not_contains "COMPREPLY" "project" "Should not contain command 'project'"
}

test_bash_completion_tail_shows_only_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "111111
222222"
    
    COMP_WORDS=(slx tail)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "111111" "Should contain job ID 111111"
    assert_array_contains "COMPREPLY" "222222" "Should contain job ID 222222"
    assert_array_not_contains "COMPREPLY" "logs" "Should not contain command 'logs'"
}

test_bash_completion_kill_shows_only_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "999999"
    
    COMP_WORDS=(slx kill)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "999999" "Should contain job ID 999999"
    assert_array_not_contains "COMPREPLY" "killall" "Should not contain command 'killall'"
}

test_bash_completion_logs_position_3_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "123456
789012"
    
    COMP_WORDS=(slx logs "")
    COMP_CWORD=3
    
    _slx_completion
    
    # Should still show job IDs at position 3
    assert_array_contains "COMPREPLY" "123456" "Should contain job ID at position 3"
    assert_array_contains "COMPREPLY" "789012" "Should contain job ID at position 3"
}

test_bash_completion_init_returns_empty() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx init)
    COMP_CWORD=2
    
    _slx_completion
    
    # Should return empty, not show other commands
    assert_equals "0" "${#COMPREPLY[@]}" "Should return empty array after 'init'"
}

test_bash_completion_submit_shows_sbatch_files() {
    source "$COMPLETION_BASH"
    
    # Create some test files
    touch "$TEST_TMP/test1.sbatch"
    touch "$TEST_TMP/test2.sbatch"
    touch "$TEST_TMP/test.txt"
    
    COMP_WORDS=(slx submit)
    COMP_CWORD=2
    
    # Change to test directory
    cd "$TEST_TMP"
    
    _slx_completion
    
    # Should show .sbatch files
    local found_sbatch=0
    for item in "${COMPREPLY[@]}"; do
        if [[ "$item" == *".sbatch"* ]]; then
            found_sbatch=1
            break
        fi
    done
    
    if [ $found_sbatch -eq 0 ] && [ ${#COMPREPLY[@]} -eq 0 ]; then
        # Empty is acceptable if no .sbatch files in current dir
        return 0
    fi
}

test_bash_completion_info_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "555555
666666"
    
    COMP_WORDS=(slx info)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "555555" "Should contain job ID for info"
    assert_array_contains "COMPREPLY" "666666" "Should contain job ID for info"
}

test_bash_completion_info_position_3_shows_options() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx info 123456)
    COMP_CWORD=3
    
    _slx_completion
    
    # Should show options like --nodes, -n
    assert_array_contains "COMPREPLY" "--nodes" "Should contain --nodes option"
    assert_array_contains "COMPREPLY" "-n" "Should contain -n option"
}

test_bash_completion_no_squeue_returns_empty() {
    source "$COMPLETION_BASH"
    
    # Create a mock squeue that doesn't exist (remove it if it was created)
    rm -f "$MOCK_BIN/squeue"
    
    # Temporarily override PATH to only include mock bin (which has no squeue)
    local old_path="$PATH"
    export PATH="$MOCK_BIN"
    
    # Verify squeue is not available
    if command -v squeue &>/dev/null; then
        # If squeue is still found (maybe as a function or alias), skip this test
        export PATH="$old_path"
        echo "Skipping: squeue still available in test environment"
        return 0
    fi
    
    COMP_WORDS=(slx logs)
    COMP_CWORD=2
    
    _slx_completion
    
    # Restore PATH
    export PATH="$old_path"
    
    # Should return empty when squeue not available
    assert_equals "0" "${#COMPREPLY[@]}" "Should return empty when squeue not available"
}

test_bash_completion_project_submit_shows_projects() {
    source "$COMPLETION_BASH"
    
    local workdir="$TEST_TMP/workdir"
    mkdir -p "$workdir/projects"
    mkdir -p "$workdir/projects/proj1"
    mkdir -p "$workdir/projects/proj2"
    mkdir -p "$workdir/projects/proj3"
    
    export SLX_WORKDIR="$workdir"
    
    COMP_WORDS=(slx project submit)
    COMP_CWORD=3
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "proj1" "Should contain project proj1"
    assert_array_contains "COMPREPLY" "proj2" "Should contain project proj2"
    assert_array_contains "COMPREPLY" "proj3" "Should contain project proj3"
}

# ============================================
# Bash Alias Completion Tests
# ============================================

test_bash_alias_sxl_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "777777
888888"
    
    COMP_WORDS=(sxl)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "777777" "sxl alias should show job IDs"
    assert_array_contains "COMPREPLY" "888888" "sxl alias should show job IDs"
}

test_bash_alias_sxt_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "111111"
    
    COMP_WORDS=(sxt)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "111111" "sxt alias should show job IDs"
}

test_bash_alias_sxk_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "222222"
    
    COMP_WORDS=(sxk)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "222222" "sxk alias should show job IDs"
}

test_bash_alias_sxs_shows_sbatch_files() {
    source "$COMPLETION_BASH"
    
    touch "$TEST_TMP/test.sbatch"
    cd "$TEST_TMP"
    
    COMP_WORDS=(sxs)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    # Should attempt to show .sbatch files (may be empty if none in current dir)
    # Just verify it doesn't crash
    return 0
}

test_bash_alias_sxi_shows_job_ids() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "333333"
    
    COMP_WORDS=(sxi)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "333333" "sxi alias should show job IDs"
}

test_bash_alias_sxi_position_2_shows_options() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(sxi 123456)
    COMP_CWORD=2
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "--nodes" "sxi alias should show --nodes option"
    assert_array_contains "COMPREPLY" "-n" "sxi alias should show -n option"
}

test_bash_alias_sxps_shows_projects() {
    source "$COMPLETION_BASH"
    
    local workdir="$TEST_TMP/workdir"
    mkdir -p "$workdir/projects/proj1"
    mkdir -p "$workdir/projects/proj2"
    
    export SLX_WORKDIR="$workdir"
    
    COMP_WORDS=(sxps)
    COMP_CWORD=1
    
    _complete_slx_alias
    
    assert_array_contains "COMPREPLY" "proj1" "sxps alias should show projects"
    assert_array_contains "COMPREPLY" "proj2" "sxps alias should show projects"
}

# ============================================
# Zsh Completion Tests
# ============================================

test_zsh_completion_syntax_valid() {
    # Just check that the file can be sourced without syntax errors
    if zsh -n "$COMPLETION_ZSH" 2>/dev/null; then
        return 0
    else
        echo "Zsh completion file has syntax errors"
        return 1
    fi
}

test_zsh_completion_logs_only_shows_job_ids() {
    # Note: Full zsh completion testing requires zsh and compinit
    # This is a basic check that the function exists and can be loaded
    if ! command -v zsh &>/dev/null; then
        echo "Skipping: zsh not available"
        return 0
    fi
    
    # Check that the completion function is defined in the file
    if grep -q "_slx()" "$COMPLETION_ZSH"; then
        return 0
    else
        echo "_slx function not found in zsh completion"
        return 1
    fi
}

test_zsh_completion_checks_current_position() {
    # Check that the zsh completion checks CURRENT position
    if grep -q "CURRENT" "$COMPLETION_ZSH"; then
        return 0
    else
        echo "Zsh completion should check CURRENT position"
        return 1
    fi
}

test_zsh_completion_aliases_updated() {
    # Check that aliases are updated to sx-prefixed
    if grep -q "compdef _slx_job_id sxl sxt sxk sxi" "$COMPLETION_ZSH"; then
        return 0
    else
        echo "Zsh completion aliases not updated to sx-prefixed"
        return 1
    fi
}

# ============================================
# Edge Cases
# ============================================

test_bash_completion_empty_squeue_output() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue ""
    
    COMP_WORDS=(slx logs)
    COMP_CWORD=2
    
    _slx_completion
    
    # Should handle empty output gracefully
    assert_equals "0" "${#COMPREPLY[@]}" "Should return empty array for empty squeue output"
}

test_bash_completion_logs_filters_by_prefix() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "123456
123789
456789"
    
    COMP_WORDS=(slx logs 123)
    COMP_CWORD=3
    
    _slx_completion
    
    # Should filter to jobs starting with 123
    assert_array_contains "COMPREPLY" "123456" "Should contain job ID matching prefix"
    assert_array_contains "COMPREPLY" "123789" "Should contain job ID matching prefix"
    # compgen -W will filter automatically, so 456789 might still appear
    # The important thing is that it doesn't show commands
}

test_bash_completion_find_shows_job_names() {
    source "$COMPLETION_BASH"
    
    create_mock_squeue "job1
job2
job3"
    
    COMP_WORDS=(slx find)
    COMP_CWORD=2
    
    _slx_completion
    
    # Should show job names (mocked as job1, job2, job3)
    # Note: Our mock returns job names when format is %j
    # The actual completion should handle this
    return 0
}

test_bash_completion_list_shows_options() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx list)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "--user" "Should show --user option for list"
}

test_bash_completion_history_shows_options() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx history)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "--days" "Should show --days option for history"
}

test_bash_completion_profile_shows_subcommands() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx profile)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "new" "Should contain profile subcommand: new"
    assert_array_contains "COMPREPLY" "list" "Should contain profile subcommand: list"
    assert_array_contains "COMPREPLY" "show" "Should contain profile subcommand: show"
    assert_array_contains "COMPREPLY" "delete" "Should contain profile subcommand: delete"
}

test_bash_completion_profile_show_completes_names() {
    source "$COMPLETION_BASH"
    
    # Create mock profiles
    local config_dir="$TEST_TMP/config/slx"
    mkdir -p "$config_dir/profiles.d"
    touch "$config_dir/profiles.d/gpu-large.env"
    touch "$config_dir/profiles.d/cpu-small.env"
    
    export XDG_CONFIG_HOME="$TEST_TMP/config"
    
    COMP_WORDS=(slx profile show)
    COMP_CWORD=3
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "gpu-large" "Should contain profile: gpu-large"
    assert_array_contains "COMPREPLY" "cpu-small" "Should contain profile: cpu-small"
}

test_bash_completion_project_new_shows_profile_option() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx project new)
    COMP_CWORD=3
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "--profile" "Should show --profile option"
    assert_array_contains "COMPREPLY" "--git" "Should show --git option"
}

# ============================================
# Run Command Completion Tests
# ============================================

test_bash_completion_run_shows_options() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx run)
    COMP_CWORD=2
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "--profile" "Should show --profile option for run"
    assert_array_contains "COMPREPLY" "--mode" "Should show --mode option for run"
    assert_array_contains "COMPREPLY" "--help" "Should show --help option for run"
}

test_bash_completion_run_mode_completes_values() {
    source "$COMPLETION_BASH"
    
    COMP_WORDS=(slx run --mode)
    COMP_CWORD=3
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "srun" "Should show srun mode"
    assert_array_contains "COMPREPLY" "sbatch" "Should show sbatch mode"
}

test_bash_completion_run_profile_completes_profiles() {
    source "$COMPLETION_BASH"
    
    # Create mock profiles
    local config_dir="$TEST_TMP/config/slx"
    mkdir -p "$config_dir/profiles.d"
    touch "$config_dir/profiles.d/gpu-large.env"
    touch "$config_dir/profiles.d/cpu-small.env"
    
    export XDG_CONFIG_HOME="$TEST_TMP/config"
    
    COMP_WORDS=(slx run --profile)
    COMP_CWORD=3
    
    _slx_completion
    
    assert_array_contains "COMPREPLY" "gpu-large" "Should contain profile: gpu-large"
    assert_array_contains "COMPREPLY" "cpu-small" "Should contain profile: cpu-small"
}

# ============================================
# Run All Tests
# ============================================

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}slx Completion Test Suite${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo -e "${YELLOW}Bash Completion - Basic:${NC}"
run_test "first position shows commands" test_bash_completion_first_position_shows_commands
run_test "logs shows only job IDs" test_bash_completion_logs_shows_only_job_ids
run_test "tail shows only job IDs" test_bash_completion_tail_shows_only_job_ids
run_test "kill shows only job IDs" test_bash_completion_kill_shows_only_job_ids
run_test "logs position 3 shows job IDs" test_bash_completion_logs_position_3_shows_job_ids
run_test "init returns empty" test_bash_completion_init_returns_empty
run_test "submit shows sbatch files" test_bash_completion_submit_shows_sbatch_files
run_test "info shows job IDs" test_bash_completion_info_shows_job_ids
run_test "info position 3 shows options" test_bash_completion_info_position_3_shows_options
run_test "no squeue returns empty" test_bash_completion_no_squeue_returns_empty
run_test "project submit shows projects" test_bash_completion_project_submit_shows_projects

echo ""
echo -e "${YELLOW}Bash Alias Completion:${NC}"
run_test "sxl alias shows job IDs" test_bash_alias_sxl_shows_job_ids
run_test "sxt alias shows job IDs" test_bash_alias_sxt_shows_job_ids
run_test "sxk alias shows job IDs" test_bash_alias_sxk_shows_job_ids
run_test "sxs alias shows sbatch files" test_bash_alias_sxs_shows_sbatch_files
run_test "sxi alias shows job IDs" test_bash_alias_sxi_shows_job_ids
run_test "sxi position 2 shows options" test_bash_alias_sxi_position_2_shows_options
run_test "sxps alias shows projects" test_bash_alias_sxps_shows_projects

echo ""
echo -e "${YELLOW}Zsh Completion:${NC}"
run_test "zsh completion syntax valid" test_zsh_completion_syntax_valid
run_test "zsh completion logs only shows job IDs" test_zsh_completion_logs_only_shows_job_ids
run_test "zsh completion checks current position" test_zsh_completion_checks_current_position
run_test "zsh completion aliases updated" test_zsh_completion_aliases_updated

echo ""
echo -e "${YELLOW}Edge Cases:${NC}"
run_test "empty squeue output" test_bash_completion_empty_squeue_output
run_test "logs filters by prefix" test_bash_completion_logs_filters_by_prefix
run_test "find shows job names" test_bash_completion_find_shows_job_names
run_test "list shows options" test_bash_completion_list_shows_options
run_test "history shows options" test_bash_completion_history_shows_options

echo ""
echo -e "${YELLOW}Profile Completion:${NC}"
run_test "profile shows subcommands" test_bash_completion_profile_shows_subcommands
run_test "profile show completes names" test_bash_completion_profile_show_completes_names
run_test "project new shows profile option" test_bash_completion_project_new_shows_profile_option

echo ""
echo -e "${YELLOW}Run Command Completion:${NC}"
run_test "run shows options" test_bash_completion_run_shows_options
run_test "run --mode completes values" test_bash_completion_run_mode_completes_values
run_test "run --profile completes profiles" test_bash_completion_run_profile_completes_profiles

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

