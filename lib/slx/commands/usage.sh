#!/bin/bash
# slx usage and version commands
# Help and version information

# Print usage information
usage() {
    cat << EOF
${BOLD}slx${NC} - SLurm eXtended v${SLX_VERSION}
A production-ready SLURM project manager

${BOLD}USAGE:${NC}
    slx <command> [options]

${BOLD}PROJECT COMMANDS:${NC}
    init                     Initialize slx configuration
    project new [--profile]  Create a new project with sbatch/run scripts
    project submit <name>    Submit a project's sbatch file
    project list             List all projects

${BOLD}PROFILE COMMANDS:${NC}
    profile new              Create a new compute profile
    profile list             List all profiles
    profile show <name>      Show profile details
    profile delete <name>    Delete a profile

${BOLD}JOB COMMANDS:${NC}
    run [options] [command]  Run a command using a profile (srun or sbatch)
    submit <script>          Submit a SLURM job script
    list [--user USER]       List all running/pending jobs
    running                  List only running jobs
    pending                  List only pending jobs
    kill <job_id>            Cancel a specific job by ID
    killall                  Cancel all jobs for current user
    logs <job_id>            View logs for a specific job
    tail <job_id>            Tail logs for a running job
    info <job_id> [-n]       Show job info (use -n for nodes only)
    status                   Show summary of all user jobs
    history [--days N]       Show job history (default: 1 day)
    find <pattern>           Find jobs by name pattern
    clean                    Clean old log files (interactive)

${BOLD}OTHER:${NC}
    version                  Show version information
    help                     Show this help message

${BOLD}EXAMPLES:${NC}
    slx init
    slx project new
    slx project new --profile gpu-large
    slx project submit my-project
    slx profile new
    slx profile list
    slx run --profile gpu-large python train.py
    slx run --profile debug --mode sbatch ./long_job.sh
    slx run --profile gpu-large          # interactive shell
    slx submit job.sbatch
    slx list
    slx logs 123456
    slx info 123456 --nodes

${BOLD}CONFIGURATION:${NC}
    Config file: ${SLX_CONFIG_FILE}
    Projects:    \${SLX_WORKDIR}/projects/

EOF
}

# Show version
show_version() {
    echo -e "${BOLD}slx${NC} (SLurm eXtended) version ${SLX_VERSION}"
    echo "Config: ${SLX_CONFIG_FILE}"
    echo "Workdir: ${SLX_WORKDIR}"
}

