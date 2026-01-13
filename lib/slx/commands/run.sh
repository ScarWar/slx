#!/bin/bash
# slx run command
# Run commands using a compute profile via srun or sbatch

# Run command using profile settings
cmd_run() {
    local USE_PROFILE=""
    local RUN_MODE="srun"
    local SHOW_HELP=""
    local args=()
    
    # Parse flags
    while [ $# -gt 0 ]; do
        case "$1" in
            --profile)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    USE_PROFILE="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --profile requires a profile name${NC}"
                    echo "Available profiles:"
                    profile_list 2>/dev/null || echo "  (none)"
                    return 1
                fi
                ;;
            --profile=*)
                USE_PROFILE="${1#*=}"
                shift
                ;;
            --mode)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    RUN_MODE="$2"
                    shift 2
                else
                    echo -e "${RED}Error: --mode requires a value (srun or sbatch)${NC}"
                    return 1
                fi
                ;;
            --mode=*)
                RUN_MODE="${1#*=}"
                shift
                ;;
            --help|-h)
                SHOW_HELP="yes"
                shift
                ;;
            --)
                shift
                # Everything after -- is the command
                args+=("$@")
                break
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Run 'slx run --help' for usage"
                return 1
                ;;
            *)
                # Start of command
                args+=("$1")
                shift
                # Collect rest as command
                args+=("$@")
                break
                ;;
        esac
    done
    
    # Show help
    if [ -n "$SHOW_HELP" ]; then
        run_help
        return 0
    fi
    
    # Validate mode
    case "$RUN_MODE" in
        srun|sbatch)
            ;;
        *)
            echo -e "${RED}Error: Invalid mode '$RUN_MODE'. Use 'srun' or 'sbatch'${NC}"
            return 1
            ;;
    esac
    
    # Validate profile if specified
    if [ -n "$USE_PROFILE" ]; then
        if ! profile_exists "$USE_PROFILE"; then
            echo -e "${RED}Error: Profile '${USE_PROFILE}' not found${NC}"
            echo ""
            echo "Available profiles:"
            profile_list 2>/dev/null || echo "  (none)"
            return 1
        fi
    fi
    
    # Start with global defaults
    local P_PARTITION="$SLX_PARTITION"
    local P_ACCOUNT="$SLX_ACCOUNT"
    local P_QOS="$SLX_QOS"
    local P_TIME="$SLX_TIME"
    local P_NODES="$SLX_NODES"
    local P_NTASKS="$SLX_NTASKS"
    local P_CPUS="$SLX_CPUS"
    local P_MEM="$SLX_MEM"
    local P_GPUS="$SLX_GPUS"
    local P_EXCLUDE="$SLX_EXCLUDE"
    local P_NODELIST="$SLX_NODELIST"
    
    # Apply profile if specified
    if [ -n "$USE_PROFILE" ]; then
        if load_profile "$USE_PROFILE"; then
            apply_profile_to_project
            echo -e "${BLUE}Using profile: ${GREEN}${USE_PROFILE}${NC}"
            [ -n "$SLX_PROFILE_DESC" ] && echo -e "  ${SLX_PROFILE_DESC}"
        fi
    fi
    
    # Execute based on mode
    case "$RUN_MODE" in
        srun)
            run_srun "${args[@]}"
            ;;
        sbatch)
            run_sbatch "${args[@]}"
            ;;
    esac
}

# Show run command help
run_help() {
    cat << EOF
${BOLD}slx run${NC} - Run commands using a compute profile

${BOLD}USAGE:${NC}
    slx run [options] [--] [command ...]

${BOLD}OPTIONS:${NC}
    --profile <name>    Use settings from a saved compute profile
    --mode <srun|sbatch> Execution mode (default: srun)
                        srun: Interactive/blocking, output to terminal
                        sbatch: Batch submit, output to log files
    --help, -h          Show this help message

${BOLD}BEHAVIOR:${NC}
    - If no command is provided with srun mode, starts an interactive shell
    - If no command is provided with sbatch mode, an error is shown
    - Profile settings override global defaults for partition, account, etc.

${BOLD}EXAMPLES:${NC}
    # Run a command interactively using a profile
    slx run --profile gpu-large python train.py

    # Submit a batch job using a profile
    slx run --profile gpu-large --mode sbatch ./long_job.sh

    # Get an interactive shell on a GPU node
    slx run --profile gpu-large

    # Run without a profile (uses global defaults)
    slx run nvidia-smi

    # Use -- to separate options from commands with dashes
    slx run --profile debug -- ls -la

EOF
}

# Execute command via srun
run_srun() {
    local cmd_args=("$@")
    
    # Build srun options
    local srun_opts=()
    
    [ -n "$P_PARTITION" ] && srun_opts+=("--partition=$P_PARTITION")
    [ -n "$P_ACCOUNT" ] && srun_opts+=("--account=$P_ACCOUNT")
    [ -n "$P_QOS" ] && srun_opts+=("--qos=$P_QOS")
    [ -n "$P_TIME" ] && srun_opts+=("--time=$P_TIME")
    [ -n "$P_NODES" ] && srun_opts+=("--nodes=$P_NODES")
    [ -n "$P_NTASKS" ] && srun_opts+=("--ntasks=$P_NTASKS")
    [ -n "$P_CPUS" ] && srun_opts+=("--cpus-per-task=$P_CPUS")
    [ -n "$P_MEM" ] && srun_opts+=("--mem=$P_MEM")
    [ -n "$P_GPUS" ] && srun_opts+=("--gpus=$P_GPUS")
    [ -n "$P_NODELIST" ] && srun_opts+=("--nodelist=$P_NODELIST")
    [ -n "$P_EXCLUDE" ] && srun_opts+=("--exclude=$P_EXCLUDE")
    
    if [ ${#cmd_args[@]} -eq 0 ]; then
        # No command provided - start interactive shell
        echo -e "${BLUE}Starting interactive shell...${NC}"
        srun_opts+=("--pty")
        exec srun "${srun_opts[@]}" bash
    else
        # Run the provided command
        echo -e "${BLUE}Running command via srun...${NC}"
        exec srun "${srun_opts[@]}" -- "${cmd_args[@]}"
    fi
}

# Execute command via sbatch
run_sbatch() {
    local cmd_args=("$@")
    
    # sbatch requires a command
    if [ ${#cmd_args[@]} -eq 0 ]; then
        echo -e "${RED}Error: sbatch mode requires a command${NC}"
        echo "For an interactive shell, use: slx run --mode srun --profile <name>"
        return 1
    fi
    
    # Ensure log directory exists
    mkdir -p "$SLX_LOG_DIR"
    
    # Generate a job name from the command
    local JOB_NAME="slx-run"
    if [ -n "${cmd_args[0]}" ]; then
        JOB_NAME="slx-$(basename "${cmd_args[0]}")"
    fi
    
    # Create temporary sbatch script
    local SCRIPT_FILE
    SCRIPT_FILE=$(mktemp "${SLX_LOG_DIR}/slx-run-XXXXXX.sbatch")
    
    # Build the script
    {
        echo "#!/bin/bash"
        echo "#SBATCH --job-name=${JOB_NAME}"
        [ -n "$P_PARTITION" ] && echo "#SBATCH --partition=${P_PARTITION}"
        [ -n "$P_ACCOUNT" ] && echo "#SBATCH --account=${P_ACCOUNT}"
        [ -n "$P_QOS" ] && echo "#SBATCH --qos=${P_QOS}"
        [ -n "$P_TIME" ] && echo "#SBATCH --time=${P_TIME}"
        [ -n "$P_NODES" ] && echo "#SBATCH --nodes=${P_NODES}"
        [ -n "$P_NTASKS" ] && echo "#SBATCH --ntasks=${P_NTASKS}"
        [ -n "$P_CPUS" ] && echo "#SBATCH --cpus-per-task=${P_CPUS}"
        [ -n "$P_MEM" ] && echo "#SBATCH --mem=${P_MEM}"
        [ -n "$P_GPUS" ] && echo "#SBATCH --gpus=${P_GPUS}"
        [ -n "$P_NODELIST" ] && echo "#SBATCH --nodelist=${P_NODELIST}"
        [ -n "$P_EXCLUDE" ] && echo "#SBATCH --exclude=\"${P_EXCLUDE}\""
        echo "#SBATCH --output=${SLX_LOG_DIR}/%x_%j.out"
        echo "#SBATCH --error=${SLX_LOG_DIR}/%x_%j.err"
        echo ""
        echo "# Change to the directory where slx run was invoked"
        echo "cd $(printf '%q' "$PWD")"
        echo ""
        echo "# Execute the command"
        # Properly quote command arguments
        echo -n "exec"
        for arg in "${cmd_args[@]}"; do
            printf ' %q' "$arg"
        done
        echo ""
    } > "$SCRIPT_FILE"
    
    chmod +x "$SCRIPT_FILE"
    
    echo -e "${BLUE}Submitting batch job...${NC}"
    
    # Submit the job
    local JOB_OUTPUT
    JOB_OUTPUT=$(sbatch "$SCRIPT_FILE" 2>&1)
    local EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        local JOB_ID
        JOB_ID=$(echo "$JOB_OUTPUT" | grep -oP '\d+' | head -1)
        echo -e "${GREEN}Job submitted successfully!${NC}"
        echo -e "Job ID: ${GREEN}${JOB_ID}${NC}"
        echo ""
        echo -e "Logs will be at:"
        echo -e "  ${CYAN}${SLX_LOG_DIR}/${JOB_NAME}_${JOB_ID}.out${NC}"
        echo -e "  ${CYAN}${SLX_LOG_DIR}/${JOB_NAME}_${JOB_ID}.err${NC}"
        echo ""
        echo -e "Monitor with: ${CYAN}slx tail ${JOB_ID}${NC}"
        
        # Clean up the temporary script (optional - keep for debugging)
        # rm -f "$SCRIPT_FILE"
    else
        echo -e "${RED}Failed to submit job${NC}"
        echo "$JOB_OUTPUT"
        rm -f "$SCRIPT_FILE"
        return 1
    fi
}
