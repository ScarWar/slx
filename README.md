# slx - SLurm eXtended

A production-ready SLURM project manager for HPC clusters. Manage jobs, create projects, and generate sbatch files with ease.

## Features

- **Project Management** - Create and manage SLURM projects with generated sbatch/run scripts
- **Job Operations** - Submit, list, kill, and monitor SLURM jobs
- **Cluster-Aware Setup** - Queries SLURM for available partitions, accounts, QoS, and nodes
- **Interactive Menus** - Multi-select UI with `whiptail`/`dialog` (falls back to text)
- **Tab Completion** - Full bash/zsh completion support
- **Short Aliases** - Optional quick aliases (`cs`, `cl`, `ck`, etc.)
- **Cluster-Friendly** - Separates config (HOME) from data (WORKDIR) for limited quotas

## Installation

### Quick Install

```bash
git clone git@github.com:ScarWar/slurm-cluster-tools.git
cd slurm-cluster-tools
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

## Install Layout

```
~/.local/
├── bin/
│   └── slx                    # Main command (wrapper)
└── share/
    └── slx/                   # Tool payload
        ├── bin/slx            # Main CLI script
        ├── completions/       # Tab completion scripts
        └── templates/         # Project templates

~/.config/
└── slx/
    ├── config.env             # User configuration
    └── aliases.sh             # Shell aliases (if enabled)

$WORKDIR/
└── projects/
    └── my-project/            # Your projects
        ├── run.sh             # Main script
        ├── run.sbatch         # SLURM job file
        └── logs/              # Job output logs
```

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
# Create a new project
slx project new

# List all projects
slx project list

# Submit a project job
slx project submit my-project
```

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

## Aliases

If you enabled aliases during installation, you can use these shortcuts:

| Alias | Command | Description |
|-------|---------|-------------|
| `c` | `slx` | Base command |
| `cs` | `slx submit` | Submit a job |
| `cl` | `slx logs` | View logs |
| `cls` | `slx list` | List jobs |
| `cr` | `slx running` | Running jobs |
| `cpd` | `slx pending` | Pending jobs |
| `ck` | `slx kill` | Kill a job |
| `cka` | `slx killall` | Kill all jobs |
| `ct` | `slx tail` | Tail logs |
| `ci` | `slx info` | Job info |
| `cst` | `slx status` | Status summary |
| `ch` | `slx history` | Job history |
| `cf` | `slx find` | Find jobs |
| `ccl` | `slx clean` | Clean logs |
| `cpn` | `slx project new` | New project |
| `cps` | `slx project submit` | Submit project |
| `cpl` | `slx project list` | List projects |

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

## Project Structure

When you run `slx project new`, it creates:

```
$WORKDIR/projects/my-project/
├── run.sh           # Your main script (edit this!)
├── run.sbatch       # SLURM job file (auto-generated)
└── logs/            # Job output logs
    ├── my-project_123456.out
    └── my-project_123456.err
```

### run.sh

This is your main script. Edit it to run your code:

```bash
#!/bin/bash
echo "Starting my-project..."

# Activate environment
source /path/to/venv/bin/activate

# Run your code
python train.py --gpus=${SLURM_GPUS}

echo "Job completed!"
```

### run.sbatch

The sbatch file is auto-generated with your settings. It:
- Sets SLURM job parameters
- Changes to the project directory
- Runs `run.sh`
- Saves logs to `logs/`

## Tab Completion

Tab completion is available for bash and zsh:

```bash
slx <TAB>                    # Show all commands
slx project <TAB>            # Show project subcommands
slx project submit <TAB>     # Complete project names
slx logs <TAB>               # Complete job IDs
```

## Requirements

- SLURM workload manager
- Bash shell (for the tool itself)
- rsync (for installation, with fallback to cp)

### Optional

- **whiptail** or **dialog** - For interactive TUI menus during `slx init` and `slx project new`. If not installed, falls back to text-based selection.

## File Structure (Repository)

```
.
├── bin/
│   ├── slx                  # Main CLI
│   ├── cluster.sh           # Deprecated wrapper
│   └── install.sh           # Installation script
├── completions/
│   ├── slx.bash             # Bash completion
│   └── slx.zsh              # Zsh completion
├── templates/
│   ├── run.sh.tmpl          # Run script template
│   └── job.sbatch.tmpl      # Sbatch template
├── LICENSE                  # MIT License
├── .gitignore
└── README.md
```

## Why Separate HOME and WORKDIR?

Many HPC clusters have:
- **Limited HOME quota** (e.g., 10GB) - for config files
- **Large scratch/data mount** (e.g., 1TB+) - for actual work

slx keeps minimal config in `~/.config/slx/` (a few KB) while storing projects in a configurable WORKDIR on your larger mount.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.
