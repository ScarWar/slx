#!/bin/bash
# slx project commands
# Project management: new, submit, list

# Project management commands
cmd_project() {
    local subcmd="$1"
    shift || true
    
    case "$subcmd" in
        new)
            project_new "$@"
            ;;
        submit)
            project_submit "$@"
            ;;
        list)
            project_list "$@"
            ;;
        ""|help)
            echo -e "${BOLD}Project commands:${NC}"
            echo "  slx project new [--git|--no-git]   Create a new project"
            echo "  slx project submit <name>          Submit a project's job"
            echo "  slx project list                   List all projects"
            echo ""
            echo -e "${BOLD}Options for 'new':${NC}"
            echo "  --git       Initialize a git repository with README.md and .gitignore"
            echo "  --no-git    Skip git initialization (default if not prompted)"
            ;;
        *)
            echo -e "${RED}Unknown project command: $subcmd${NC}"
            echo "Run 'slx project help' for usage"
            exit 1
            ;;
    esac
}

# Create a new project
project_new() {
    # Parse --git/--no-git flags
    local INIT_GIT=""
    local args=()
    for arg in "$@"; do
        case "$arg" in
            --git)
                INIT_GIT="yes"
                ;;
            --no-git)
                INIT_GIT="no"
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    set -- "${args[@]}"
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Create New Project${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Check if initialized
    if [ ! -f "$SLX_CONFIG_FILE" ]; then
        echo -e "${YELLOW}slx is not initialized. Running init first...${NC}"
        echo ""
        cmd_init
        echo ""
    fi
    
    local PROJECT_NAME=""
    local RUN_NAME="run"
    local SBATCH_NAME=""
    local JOB_NAME=""
    
    # Project name (required)
    while [ -z "$PROJECT_NAME" ]; do
        get_input "Project name (required)" "" "PROJECT_NAME"
        if [ -z "$PROJECT_NAME" ]; then
            echo -e "${RED}Project name is required${NC}"
        fi
    done
    
    # Sanitize project name (replace spaces with underscores)
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    
    local PROJECT_DIR="${SLX_WORKDIR}/projects/${PROJECT_NAME}"
    
    # Check if project already exists
    if [ -d "$PROJECT_DIR" ]; then
        echo -e "${YELLOW}Project '${PROJECT_NAME}' already exists at: ${PROJECT_DIR}${NC}"
        echo -ne "${YELLOW}Overwrite? [y/N]${NC}: "
        read -r overwrite
        if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
            echo "Cancelled"
            return 1
        fi
    fi
    
    echo ""
    get_input "Run script name" "$RUN_NAME" "RUN_NAME"
    
    # Default sbatch name is based on run name
    SBATCH_NAME="${RUN_NAME}"
    get_input "Sbatch file name" "$SBATCH_NAME" "SBATCH_NAME"
    
    # Default job name is project name
    JOB_NAME="$PROJECT_NAME"
    get_input "SLURM job name" "$JOB_NAME" "JOB_NAME"
    
    echo ""
    echo -e "${CYAN}Job resource settings (defaults from config, override as needed):${NC}"
    echo ""
    
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
    
    # Check if user wants to customize settings
    echo -e "Current defaults: Partition=${CYAN}${P_PARTITION:-<auto>}${NC}, Account=${CYAN}${P_ACCOUNT:-<auto>}${NC}"
    echo -ne "${YELLOW}Customize job settings? [y/N]${NC}: "
    read -r customize
    
    if [ "$customize" = "y" ] || [ "$customize" = "Y" ]; then
        # Use cluster-aware menus for partition/account/qos
        select_partition "P_PARTITION" "$P_PARTITION"
        select_account "P_ACCOUNT" "$P_ACCOUNT"
        select_qos "P_QOS" "$P_QOS"
        
        echo ""
        echo -e "${CYAN}Resource limits:${NC}"
        get_input "Time (minutes)" "$P_TIME" "P_TIME"
        get_input "Nodes" "$P_NODES" "P_NODES"
        get_input "Tasks" "$P_NTASKS" "P_NTASKS"
        get_input "CPUs per task" "$P_CPUS" "P_CPUS"
        get_input "Memory (MB)" "$P_MEM" "P_MEM"
        get_input "GPUs" "$P_GPUS" "P_GPUS"
        
        echo ""
        echo -e "${CYAN}Node preferences:${NC}"
        select_nodes "P_NODELIST" "$P_NODELIST" \
            "Preferred Nodes (NodeList)" \
            "Select preferred nodes for this project:"
        select_nodes "P_EXCLUDE" "$P_EXCLUDE" \
            "Exclude Nodes" \
            "Select nodes to exclude for this project:"
    fi
    
    # Prompt for git init if not specified via flags
    if [ -z "$INIT_GIT" ]; then
        echo ""
        echo -ne "${YELLOW}Initialize git repository? [y/N]${NC}: "
        read -r git_choice
        if [ "$git_choice" = "y" ] || [ "$git_choice" = "Y" ]; then
            INIT_GIT="yes"
        else
            INIT_GIT="no"
        fi
    fi
    
    # If git is enabled, ask for repo directory name
    local GIT_REPO_NAME=""
    if [ "$INIT_GIT" = "yes" ]; then
        GIT_REPO_NAME="$PROJECT_NAME"
        get_input "Git repo directory name" "$GIT_REPO_NAME" "GIT_REPO_NAME"
        # Sanitize repo name
        GIT_REPO_NAME=$(echo "$GIT_REPO_NAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')
    fi
    
    echo ""
    echo -e "${BLUE}Project Summary:${NC}"
    echo -e "  Name:      ${GREEN}${PROJECT_NAME}${NC}"
    echo -e "  Directory: ${GREEN}${PROJECT_DIR}${NC}"
    echo -e "  Run:       ${GREEN}${RUN_NAME}.sh${NC}"
    echo -e "  Sbatch:    ${GREEN}${SBATCH_NAME}.sbatch${NC}"
    if [ "$INIT_GIT" = "yes" ]; then
        echo -e "  Git repo:  ${GREEN}${GIT_REPO_NAME}/${NC}"
    else
        echo -e "  Git:       ${YELLOW}no${NC}"
    fi
    echo ""
    
    echo -ne "${YELLOW}Create project? [Y/n]${NC}: "
    read -r confirm
    if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
        echo "Cancelled"
        return 1
    fi
    
    # Create project structure
    mkdir -p "$PROJECT_DIR/logs"
    
    # Generate sbatch file from template
    local SBATCH_FILE="${PROJECT_DIR}/${SBATCH_NAME}.sbatch"
    local TEMPLATE_DIR=$(find_template_dir)
    
    if [ -z "$TEMPLATE_DIR" ] || [ ! -f "${TEMPLATE_DIR}/job.sbatch.tmpl" ]; then
        echo -e "${RED}Error: Template file not found${NC}" >&2
        echo -e "${RED}Expected: ${TEMPLATE_DIR:-<unknown>}/job.sbatch.tmpl${NC}" >&2
        echo -e "${YELLOW}Please ensure slx is installed correctly or run from the repository.${NC}" >&2
        return 1
    fi
    
    process_template "${TEMPLATE_DIR}/job.sbatch.tmpl" \
        "JOB_NAME=${JOB_NAME}" \
        "PARTITION=${P_PARTITION}" \
        "ACCOUNT=${P_ACCOUNT}" \
        "QOS=${P_QOS}" \
        "TIME=${P_TIME}" \
        "NODES=${P_NODES}" \
        "NTASKS=${P_NTASKS}" \
        "CPUS=${P_CPUS}" \
        "MEM=${P_MEM}" \
        "GPUS=${P_GPUS}" \
        "NODELIST=${P_NODELIST}" \
        "EXCLUDE=${P_EXCLUDE}" \
        "RUN_NAME=${RUN_NAME}" > "$SBATCH_FILE"
    
    # Generate run script
    local RUN_FILE="${PROJECT_DIR}/${RUN_NAME}.sh"
    cat > "$RUN_FILE" << EOF
#!/bin/bash
# ${PROJECT_NAME} - Main run script
# Generated by slx on $(date)

echo "Starting ${PROJECT_NAME}..."
echo "Job ID: \${SLURM_JOB_ID}"
echo "Node: \$(hostname)"
echo "Working directory: \$(pwd)"
echo ""

# ============================================
# Add your code below
# ============================================

echo "Hello from ${PROJECT_NAME}!"

# Example: Activate a virtual environment
# source /path/to/venv/bin/activate

# Example: Run a Python script
# python main.py

# Example: Run with GPU
# python train.py --gpus=\${SLURM_GPUS}

echo ""
echo "Job completed at: \$(date)"
EOF
    
    chmod +x "$RUN_FILE"
    chmod +x "$SBATCH_FILE"
    
    # Initialize git repository if requested
    if [ "$INIT_GIT" = "yes" ]; then
        if has_cmd git; then
            local GIT_REPO_DIR="${PROJECT_DIR}/${GIT_REPO_NAME}"
            
            # Create git repo subdirectory
            mkdir -p "$GIT_REPO_DIR"
            
            # Only init if .git doesn't already exist
            if [ ! -d "$GIT_REPO_DIR/.git" ]; then
                git -C "$GIT_REPO_DIR" init --quiet
                echo -e "${GREEN}Initialized git repository in ${GIT_REPO_NAME}/${NC}"
            fi
            
            # Create .gitignore only if it doesn't exist
            local GITIGNORE_FILE="${GIT_REPO_DIR}/.gitignore"
            if [ ! -f "$GITIGNORE_FILE" ]; then
                process_template "${TEMPLATE_DIR}/gitignore.tmpl" > "$GITIGNORE_FILE"
            fi
            
            # Create README.md only if it doesn't exist
            local README_FILE="${GIT_REPO_DIR}/README.md"
            if [ ! -f "$README_FILE" ]; then
                process_template "${TEMPLATE_DIR}/readme.md.tmpl" \
                    "PROJECT_NAME=${PROJECT_NAME}" \
                    "GIT_REPO_NAME=${GIT_REPO_NAME}" \
                    "RUN_NAME=${RUN_NAME}" \
                    "SBATCH_NAME=${SBATCH_NAME}" > "$README_FILE"
            fi
        else
            echo -e "${YELLOW}Warning: git not found, skipping repository initialization${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Project created successfully!${NC}"
    echo ""
    echo -e "${BLUE}Project structure:${NC}"
    echo "  ${PROJECT_DIR}/"
    echo "    ├── ${RUN_NAME}.sh          # Your main script (edit this)"
    echo "    ├── ${SBATCH_NAME}.sbatch   # SLURM job file"
    echo "    ├── logs/                   # Job output logs"
    if [ "$INIT_GIT" = "yes" ] && has_cmd git; then
        echo "    └── ${GIT_REPO_NAME}/       # Git repository (your code)"
        echo "        ├── .git/"
        echo "        ├── .gitignore"
        echo "        └── README.md"
    fi
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  1. Edit your run script: ${RUN_FILE}"
    if [ "$INIT_GIT" = "yes" ] && has_cmd git; then
        echo "  2. Add your code to:     ${PROJECT_DIR}/${GIT_REPO_NAME}/"
        echo "  3. Submit the job:       slx project submit ${PROJECT_NAME}"
    else
        echo "  2. Submit the job:       slx project submit ${PROJECT_NAME}"
    fi
    echo ""
}

# Submit a project
project_submit() {
    local PROJECT_NAME="$1"
    local RUN_NAME="${2:-run}"
    local SBATCH_NAME="${3:-$RUN_NAME}"
    
    if [ -z "$PROJECT_NAME" ]; then
        echo -e "${RED}Error: Please provide a project name${NC}"
        echo "Usage: slx project submit <project_name> [run_name] [sbatch_name]"
        echo ""
        echo "Available projects:"
        project_list
        exit 1
    fi
    
    local PROJECT_DIR="${SLX_WORKDIR}/projects/${PROJECT_NAME}"
    local SBATCH_FILE="${PROJECT_DIR}/${SBATCH_NAME}.sbatch"
    
    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${RED}Error: Project '${PROJECT_NAME}' not found${NC}"
        echo "Available projects:"
        project_list
        exit 1
    fi
    
    if [ ! -f "$SBATCH_FILE" ]; then
        echo -e "${RED}Error: Sbatch file not found: ${SBATCH_FILE}${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Submitting project: ${PROJECT_NAME}${NC}"
    
    # Change to project directory and submit
    cd "$PROJECT_DIR"
    JOB_OUTPUT=$(sbatch "$SBATCH_FILE" 2>&1)
    
    if [ $? -eq 0 ]; then
        JOB_ID=$(echo "$JOB_OUTPUT" | grep -oP '\d+' | head -1)
        echo -e "${GREEN}Job submitted successfully!${NC}"
        echo -e "Job ID: ${GREEN}${JOB_ID}${NC}"
        echo ""
        echo -e "Logs will be at:"
        echo -e "  ${CYAN}${PROJECT_DIR}/logs/${PROJECT_NAME}_${JOB_ID}.out${NC}"
        echo -e "  ${CYAN}${PROJECT_DIR}/logs/${PROJECT_NAME}_${JOB_ID}.err${NC}"
        echo ""
        echo -e "Monitor with: ${CYAN}slx tail ${JOB_ID}${NC}"
    else
        echo -e "${RED}Failed to submit job${NC}"
        echo "$JOB_OUTPUT"
        exit 1
    fi
}

# List all projects
project_list() {
    local PROJECTS_DIR="${SLX_WORKDIR}/projects"
    
    if [ ! -d "$PROJECTS_DIR" ]; then
        echo -e "${YELLOW}No projects directory found at: ${PROJECTS_DIR}${NC}"
        echo "Run 'slx init' first, then 'slx project new' to create a project"
        return 0
    fi
    
    local projects=$(ls -1 "$PROJECTS_DIR" 2>/dev/null)
    
    if [ -z "$projects" ]; then
        echo -e "${YELLOW}No projects found${NC}"
        echo "Create one with: slx project new"
        return 0
    fi
    
    echo -e "${BLUE}Projects in ${PROJECTS_DIR}:${NC}"
    echo ""
    
    for proj in $projects; do
        if [ -d "${PROJECTS_DIR}/${proj}" ]; then
            local sbatch_count=$(ls -1 "${PROJECTS_DIR}/${proj}"/*.sbatch 2>/dev/null | wc -l)
            echo -e "  ${GREEN}${proj}${NC} (${sbatch_count} sbatch file(s))"
        fi
    done
    echo ""
}

