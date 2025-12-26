# SLURM Cluster Management Tools

A collection of bash scripts and aliases for managing SLURM jobs on HPC clusters. This toolkit provides convenient commands for submitting jobs, viewing logs, monitoring job status, and more.

## Features

- 🚀 **Easy job submission** - Submit SLURM jobs with a single command
- 📊 **Job monitoring** - List, view, and track running/pending jobs
- 📝 **Log management** - View and tail job logs easily
- 🎯 **Quick aliases** - Short commands for common operations
- 🧹 **Log cleanup** - Interactive cleanup of old log files
- ⌨️ **Command completion** - Tab completion for commands, job IDs, and filenames

## Installation

### Quick Install (Recommended)

Run the interactive installation script:

```bash
git clone git@github.com:ScarWar/slurm-cluster-tools.git
cd slurm-cluster-tools
chmod +x install.sh
./install.sh
```

The script will:
- Automatically detect your shell (bash, zsh, tcsh, or csh)
- Prompt for configuration with sensible defaults
- Set up aliases and completion in your shell config file
- Create backups of existing configuration files

### Manual Installation

1. Clone this repository:
```bash
git clone git@github.com:ScarWar/slurm-cluster-tools.git
cd slurm-cluster-tools
```

2. Make the script executable:
```bash
chmod +x cluster.sh
```

3. Source the appropriate alias file for your shell:

**For bash/zsh:**
```bash
source cluster_aliases.sh
```

**For tcsh:**
```bash
source cluster_aliases.tcsh
```

4. (Optional) Add to your shell configuration file for permanent access:

**For bash/zsh** (`~/.bashrc` or `~/.zshrc`):
```bash
export CLUSTER_WORKDIR="$HOME/workdir"  # or your custom path
source $CLUSTER_WORKDIR/cluster_aliases.sh
```

**For tcsh** (`~/.tcshrc`):
```bash
setenv CLUSTER_WORKDIR $HOME/workdir  # or your custom path
source $CLUSTER_WORKDIR/cluster_aliases.tcsh
```

**Note:** Command completion is automatically enabled when you source `cluster_aliases.sh` for bash. For zsh, you may need to manually source `cluster-completion.zsh` or add it to your `~/.zshrc`.

## Configuration

The tools use environment variables for configuration:

- `CLUSTER_WORKDIR` - Directory where cluster tools are located (defaults to `$HOME/workdir`)
- `SLURM_LOG_DIR` - Directory where SLURM logs are stored (defaults to `slurm/logs`)

## Command Completion

The toolkit includes tab completion for enhanced productivity:

### Bash Completion

Completion is automatically enabled when you source `cluster_aliases.sh`. It provides:

- **Command completion**: Tab to complete command names (submit, list, logs, etc.)
- **File completion**: For `submit` command, tab completes `.sbatch` files
- **Job ID completion**: For `logs`, `tail`, `kill`, `info` commands, tab completes active job IDs
- **Job name completion**: For `find` command, tab completes job names
- **Option completion**: Tab completes options like `--user` and `--days`

**Manual setup** (if not using aliases):
```bash
source /path/to/cluster-completion.bash
```

### Zsh Completion

For zsh users, source the zsh completion file:

```bash
# Add to ~/.zshrc
source /path/to/cluster-completion.zsh
```

Or add to your fpath:
```bash
fpath=(/path/to/directory $fpath)
autoload -U compinit && compinit
```

### Completion Examples

```bash
# Tab completion for commands
./cluster.sh <TAB>          # Shows: submit, list, logs, kill, etc.

# Tab completion for job files
cs <TAB>                     # Shows all .sbatch files

# Tab completion for job IDs
cl <TAB>                     # Shows all active job IDs
ck <TAB>                     # Shows all active job IDs

# Tab completion for job names
cf <TAB>                     # Shows all job names
```

## Usage

### Direct Script Usage

```bash
./cluster.sh <command> [options]
```

### Using Aliases (Recommended)

Once you've sourced the alias file, you can use short commands:

| Alias | Command | Description |
|-------|---------|-------------|
| `c` | `cluster` | Base command (shows help) |
| `cs` | `cluster submit` | Submit a job script |
| `cl` | `cluster logs` | View job logs |
| `cls` | `cluster list` | List all jobs |
| `cr` | `cluster running` | List running jobs |
| `cpd` | `cluster pending` | List pending jobs |
| `ck` | `cluster kill` | Kill a job |
| `cka` | `cluster killall` | Kill all jobs |
| `ct` | `cluster tail` | Tail logs in real-time |
| `ci` | `cluster info` | Show job info |
| `cst` | `cluster status` | Show status summary |
| `ch` | `cluster history` | Show job history |
| `cf` | `cluster find` | Find jobs by pattern |
| `ccl` | `cluster clean` | Clean old logs |

**Note:** `cpd` and `ccl` are used instead of `cp` and `cc` to avoid conflicts with the standard Unix `cp` (copy) and `cc` (C compiler) commands.

## Commands

### Submit a Job

```bash
cs jupyter.sbatch
# or
./cluster.sh submit jupyter.sbatch
```

### List Jobs

```bash
cls                    # List all your jobs
cls --user username    # List jobs for specific user
cr                     # List only running jobs
cpd                    # List only pending jobs
```

### View Logs

```bash
cl 123456              # View complete logs for job 123456
ct 123456              # Tail logs in real-time
```

### Manage Jobs

```bash
ck 123456              # Kill a specific job
cka                    # Kill all your jobs (with confirmation)
ci 123456              # Show detailed job information
ci 123456 --nodes      # Show only the nodes allocated to the job
ci 123456 -n           # Short form: show only nodes
```

### Monitor Jobs

```bash
cst                    # Show summary of all jobs
ch                     # Show job history (last day)
ch --days 7            # Show job history (last 7 days)
cf jupyter             # Find jobs matching "jupyter"
```

### Cleanup

```bash
ccl                    # Interactive cleanup of old log files
```

## Examples

```bash
# Submit a new job
cs my_job.sbatch

# Check job status
cst

# View logs for a running job
cl 123456

# Monitor logs in real-time
ct 123456

# Kill a stuck job
ck 123456

# Find all jupyter jobs
cf jupyter
```

## File Structure

```
.
├── install.sh                  # Interactive installation script
├── cluster.sh                  # Main cluster management script
├── cluster_aliases.sh          # Bash/zsh aliases (auto-loads completion)
├── cluster_aliases.tcsh        # tcsh aliases
├── cluster-completion.bash     # Bash completion script
├── cluster-completion.zsh      # Zsh completion script
├── LICENSE                     # MIT License
├── .gitignore                  # Git ignore patterns
└── README.md                   # This file
```

## Requirements

- SLURM workload manager
- Bash shell
- Standard Unix utilities (grep, tail, find, etc.)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.

## Notes

- The script automatically searches for log files in common locations:
  - `slurm/logs/jupyter/` (subdirectory structure)
  - `slurm/logs/` (flat structure)
  - Current directory (SLURM default)

- All commands use your current user by default. Use `--user` flag to query other users' jobs (if permitted).

- The `killall` command requires confirmation before cancelling all jobs.

