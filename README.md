# slx - SLurm eXtended

A production-ready SLURM project manager for HPC clusters. Manage jobs, create projects, and generate sbatch files with ease.

## Features

- **Project Management** - Create and manage SLURM projects with generated sbatch/run scripts
- **Compute Profiles** - Save and reuse SLURM job presets (partition, GPUs, memory, node preferences)
- **Git Integration** - Optionally initialize a git repository for your project code
- **Job Operations** - Submit, list, kill, and monitor SLURM jobs
- **Cluster-Aware Setup** - Queries SLURM for available partitions, accounts, QoS, and nodes
- **Interactive Menus** - Multi-select UI with `whiptail`/`dialog` (falls back to text)
- **Rich Node Info** - Shows CPU/memory/GPU details when selecting nodes
- **Tab Completion** - Full bash/zsh completion support
- **Short Aliases** - Optional quick aliases (`sx`, `sxs`, `sxl`, `sxk`, etc.)
- **Cluster-Friendly** - Separates config (HOME) from data (WORKDIR) for limited quotas

## Quick Start

```bash
# Install
git clone git@github.com:ScarWar/slx.git
cd slx && ./bin/install.sh

# Setup (run once per cluster)
slx init

# Create and run a project
slx project new --git
slx project submit my-project
```

## Installation

### Quick Install

```bash
git clone git@github.com:ScarWar/slx.git
cd slx
./bin/install.sh
```

The installer will:

- Copy slx to `~/.local/share/slx/`
- Create the `slx` command in `~/.local/bin/`
- Set up configuration in `~/.config/slx/`
- Optionally configure aliases and tab completion

### After Installation

1. Start a new shell session, or run: `source ~/.bashrc` (or your shell's rc file)
2. Initialize slx for your cluster: `slx init`
3. Create your first project: `slx project new`

### Updating slx

```bash
cd slx
git pull
./bin/update.sh
```

The update script preserves your configuration, aliases, projects, and job data.

## Usage

### Initialize slx

Configure slx for your cluster (run once):

```bash
slx init
```

This queries your cluster and presents interactive menus:

- **WORKDIR**: Where to store projects (auto-detects `/scratch`, `/data`, etc.)
- **Partition**: Choose from available partitions (queried via `sinfo`)
- **Account**: Choose from your accounts (queried via `sacctmgr`)
- **QoS**: Choose from available QoS levels (queried via `sacctmgr`)
- **NodeList**: Multi-select preferred nodes for jobs
- **Exclude**: Multi-select nodes to exclude from jobs
- **Resource limits**: Time, nodes, CPUs, memory, GPUs

If `whiptail` or `dialog` is installed, you get a nice TUI menu. Otherwise, a text-based menu is used.

### Project Commands

```bash
# Create a new project (interactive)
slx project new

# Create with git repository
slx project new --git

# Skip git (non-interactive)
slx project new --no-git

# Create with a specific compute profile
slx project new --profile gpu-large

# Combine options
slx project new --git --profile debug

# List all projects
slx project list

# Submit a project job
slx project submit my-project
```

#### Project Options

| Option             | Description                                               |
|--------------------|-----------------------------------------------------------|
| `--git`            | Initialize a git repository with README.md and .gitignore |
| `--no-git`         | Skip git initialization (no prompt)                       |
| `--profile <name>` | Use a compute profile for job defaults                    |

When creating a project, you'll be prompted for:

- **Project name** (required)
- **Run script name** (default: `run`)
- **Sbatch file name** (default: same as run script)
- **SLURM job name** (default: project name)
- **Job settings** (optional customization)
- **Git repository** (if not specified via flag)
- **Git repo directory name** (if git enabled, defaults to project name)

### Compute Profiles

Profiles let you save SLURM job presets for different workload types:

```bash
# Create a new profile
slx profile new

# List all profiles
slx profile list

# Show profile details
slx profile show gpu-large

# Delete a profile
slx profile delete debug
```

#### Example Profiles

- **cpu-small**: CPU jobs with 4 cores, 16GB RAM, short time limit
- **gpu-large**: Multi-GPU jobs on A100 nodes, high memory
- **debug**: Quick test runs with minimal resources

#### Profile Settings

Each profile stores:
- Partition, account, QoS
- Time limit, nodes, tasks, CPUs
- Memory, GPUs
- Preferred nodes (NodeList)
- Excluded nodes

Profiles are stored in `~/.config/slx/profiles.d/<name>.env`.

#### Using Profiles

When creating a project, you can either:
1. Select a profile interactively (if profiles exist)
2. Specify via command line: `slx project new --profile gpu-large`

The profile settings become the starting defaults, which you can still customize.

### Job Commands

```bash
# Submit a job script directly
slx submit job.sbatch

# List your jobs
slx list
slx running          # Only running jobs
slx pending          # Only pending jobs

# View job information
slx info 123456
slx info 123456 -n   # Show only allocated nodes

# View job logs
slx logs 123456
slx tail 123456      # Follow logs in real-time

# Cancel jobs
slx kill 123456
slx killall          # Cancel all your jobs

# Job history and search
slx status
slx history --days 7
slx find jupyter

# Cleanup old logs
slx clean
```

## Project Structure

### Basic Project

When you run `slx project new`, it creates:

```shell
$WORKDIR/projects/my-project/
├── run.sh           # Your main script (edit this!)
├── run.sbatch       # SLURM job file (auto-generated)
└── logs/            # Job output logs
    ├── my-project_123456.out
    └── my-project_123456.err
```

### Project with Git (`--git`)

With `slx project new --git`, it creates a git repository subdirectory for your code:

```shell
$WORKDIR/projects/my-project/
├── run.sh           # SLURM run script (edit to call your code)
├── run.sbatch       # SLURM job file (auto-generated)
├── logs/            # Job output logs
└── my-project/      # Git repository (your code goes here)
    ├── .git/
    ├── .gitignore
    └── README.md
```

**Why this structure?**

- SLURM scripts (`run.sh`, `run.sbatch`) stay outside the git repo
- Your code lives in a clean git repository
- Logs are separate and won't clutter your repo
- The git repo name is customizable during creation

### run.sh

This is your main script. Edit it to run your code:

```bash
#!/bin/bash
echo "Starting my-project..."

# Activate environment
source /path/to/venv/bin/activate

# Run your code (from the git repo)
cd my-project
python train.py --gpus=${SLURM_GPUS}

echo "Job completed!"
```

### run.sbatch

The sbatch file is auto-generated with your settings. It:

- Sets SLURM job parameters (partition, account, time, resources, etc.)
- Changes to the project directory
- Runs `run.sh`
- Saves logs to `logs/`

## Aliases

If you enabled aliases during installation, you can use these shortcuts:

| Alias  | Command                | Description       |
|--------|------------------------|-------------------|
| `slx`  | `$HOME/.local/bin/slx` | Base command      |
| `sx`   | `slx`                  | Base command      |
| `sxs`  | `slx submit`           | Submit a job      |
| `sxl`  | `slx logs`             | View logs         |
| `sxls` | `slx list`             | List jobs         |
| `sxr`  | `slx running`          | Running jobs      |
| `sxpd` | `slx pending`          | Pending jobs      |
| `sxk`  | `slx kill`             | Kill a job        |
| `sxka` | `slx killall`          | Kill all jobs     |
| `sxt`  | `slx tail`             | Tail logs         |
| `sxi`  | `slx info`             | Job info          |
| `sxst` | `slx status`           | Status summary    |
| `sxh`  | `slx history`          | Job history       |
| `sxf`  | `slx find`             | Find jobs         |
| `sxcl` | `slx clean`            | Clean logs        |
| `sxp`  | `slx project`          | Project command   |
| `sxpn` | `slx project new`      | New project       |
| `sxps` | `slx project submit`   | Submit project    |
| `sxpl` | `slx project list`     | List projects     |

## Configuration

Configuration is stored in `~/.config/slx/config.env`:

```bash
# Base directory for projects (use a large mount)
SLX_WORKDIR="/scratch/$USER/workdir"

# Default SLURM job settings
SLX_PARTITION="gpu"
SLX_ACCOUNT="my-account"
SLX_QOS="normal"
SLX_TIME="1440"
SLX_NODES="1"
SLX_NTASKS="1"
SLX_CPUS="4"
SLX_MEM="50000"
SLX_GPUS="1"
SLX_NODELIST=""              # Preferred nodes (--nodelist)
SLX_EXCLUDE="node-01,node-02" # Excluded nodes (--exclude)
```

Run `slx init` to update these settings interactively with cluster-aware menus.

### Node Inventory (Optional)

For clusters where SLURM doesn't expose detailed node info, you can create a custom inventory file at `~/.config/slx/nodes.tsv` to show GPU/CPU/memory details in the node selection dialog:

```tsv
nodeName	gpu	cpu	mem	notes
gpu-node01	A100x4	64	512G	Fast interconnect
gpu-node02	A100x4	64	512G	Fast interconnect
cpu-node01		128	1T	High memory
```

The file is tab-separated with columns: `nodeName`, `gpu`, `cpu`, `mem`, `notes`. The header line is optional. This information augments what SLURM reports.

## Tab Completion

Tab completion is available for bash and zsh:

```bash
slx <TAB>                    # Show all commands
slx project <TAB>            # Show project subcommands
slx project submit <TAB>     # Complete project names
slx logs <TAB>               # Complete job IDs
```

## Install Layout

```shell
~/.local/
├── bin/
│   └── slx                    # Main command (wrapper)
└── share/
    └── slx/                   # Tool payload
        ├── bin/slx            # Main CLI script
        ├── lib/slx/           # Library modules
        │   ├── common.sh      # Shared functions
        │   └── commands/      # Command implementations
        ├── completions/       # Tab completion scripts
        └── templates/         # Project templates

~/.config/
└── slx/
    ├── config.env             # User configuration
    ├── aliases.sh             # Shell aliases (if enabled)
    ├── profiles.d/            # Compute profiles
    │   ├── cpu-small.env
    │   └── gpu-large.env
    └── nodes.tsv              # Optional node inventory (see below)

$WORKDIR/
└── projects/
    └── my-project/            # Your projects
```

## Requirements

- SLURM workload manager
- Bash shell (for the tool itself)
- rsync (for installation, with fallback to cp)

### Optional

- **whiptail** or **dialog** - For interactive TUI menus during `slx init` and `slx project new`. If not installed, falls back to text-based selection.
- **git** - For `slx project new --git` to initialize repositories

## Why Separate HOME and WORKDIR?

Many HPC clusters have:

- **Limited HOME quota** (e.g., 10GB) - for config files
- **Large scratch/data mount** (e.g., 1TB+) - for actual work

slx keeps minimal config in `~/.config/slx/` (a few KB) while storing projects in a configurable WORKDIR on your larger mount.

## Repository Structure

```shell
.
├── bin/
│   ├── slx                  # Main CLI entry point
│   ├── install.sh           # Installation script
│   └── update.sh            # Update script
├── lib/
│   └── slx/
│       ├── common.sh        # Shared functions
│       └── commands/        # Command implementations
│           ├── project.sh   # Project commands
│           ├── submit.sh    # Job submission
│           ├── logs.sh      # Log viewing
│           └── ...
├── completions/
│   ├── slx.bash             # Bash completion
│   └── slx.zsh              # Zsh completion
├── templates/
│   ├── job.sbatch.tmpl      # Sbatch template
│   ├── run.sh.tmpl          # Run script template
│   ├── gitignore.tmpl       # Project .gitignore
│   └── readme.md.tmpl       # Project README
├── tests/
│   └── test_slx_init.sh     # Test suite
├── LICENSE
└── README.md
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.
