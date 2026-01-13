#!/bin/bash
# slx Installer Utilities
# Shared functions for install.sh and update.sh only
# NOTE: Runtime utilities are in lib/slx/common.sh

# Tool info
SLX_NAME="slx"
SLX_VERSION="1.1.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get the directory where this script is located (repo root is 2 levels up from lib/slx/)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# XDG directories (with fallbacks)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
LOCAL_BIN="$HOME/.local/bin"

# slx installation paths
SLX_CONFIG_DIR="${XDG_CONFIG_HOME}/${SLX_NAME}"
SLX_DATA_DIR="${XDG_DATA_HOME}/${SLX_NAME}"
SLX_BIN="${LOCAL_BIN}/${SLX_NAME}"

# Detect current shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$tcsh" ] || [ -n "$csh" ]; then
        if [ -n "$tcsh" ] || echo "$SHELL" | grep -q "tcsh"; then
            echo "tcsh"
        else
            echo "csh"
        fi
    elif [ -n "$SHELL" ]; then
        case "$SHELL" in
            *zsh*) echo "zsh" ;;
            *bash*) echo "bash" ;;
            *tcsh*) echo "tcsh" ;;
            *csh*) echo "csh" ;;
            *) echo "bash" ;;
        esac
    else
        echo "bash"
    fi
}

# Get shell config file and related paths
# Usage: get_shell_config <shell_type>
# Sets: SHELL_CONFIG, ALIAS_FILE, COMPLETION_FILE
get_shell_config() {
    local shell_type="$1"
    
    case "$shell_type" in
        bash)
            SHELL_CONFIG="$HOME/.bashrc"
            ALIAS_FILE="$SLX_CONFIG_DIR/aliases.sh"
            COMPLETION_FILE="$SLX_DATA_DIR/completions/slx.bash"
            ;;
        zsh)
            SHELL_CONFIG="$HOME/.zshrc"
            ALIAS_FILE="$SLX_CONFIG_DIR/aliases.sh"
            COMPLETION_FILE="$SLX_DATA_DIR/completions/slx.zsh"
            ;;
        tcsh)
            SHELL_CONFIG="$HOME/.tcshrc"
            ALIAS_FILE="$SLX_CONFIG_DIR/aliases.tcsh"
            COMPLETION_FILE=""  # No completion for tcsh
            ;;
        csh)
            SHELL_CONFIG="$HOME/.cshrc"
            ALIAS_FILE="$SLX_CONFIG_DIR/aliases.tcsh"
            COMPLETION_FILE=""  # No completion for csh
            ;;
        *)
            SHELL_CONFIG=""
            ALIAS_FILE=""
            COMPLETION_FILE=""
            ;;
    esac
}

# Copy files from repo to installation directory
# Usage: install_files [preserve_user_data]
# If preserve_user_data is true, preserves projects/ and slurm/ directories
install_files() {
    local preserve_user_data="${1:-false}"
    
    # Backup user data directories if preserving
    if [ "$preserve_user_data" = "true" ]; then
        if [ -d "$SLX_DATA_DIR/projects" ]; then
            echo -e "${YELLOW}  Preserving: projects/${NC}"
            mv "$SLX_DATA_DIR/projects" "$SLX_DATA_DIR/projects.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        if [ -d "$SLX_DATA_DIR/slurm" ]; then
            echo -e "${YELLOW}  Preserving: slurm/${NC}"
            mv "$SLX_DATA_DIR/slurm" "$SLX_DATA_DIR/slurm.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
        
        # Remove everything except user data backups
        find "$SLX_DATA_DIR" -mindepth 1 -maxdepth 1 ! -name 'projects*' ! -name 'slurm*' -exec rm -rf {} + 2>/dev/null || true
    else
        # Clean previous installation completely
        if [ -d "$SLX_DATA_DIR" ]; then
            rm -rf "$SLX_DATA_DIR"/*
        fi
    fi
    
    # Copy files (exclude .git, projects/, slurm/, and user files)
    rsync -a --exclude='.git' \
             --exclude='projects/' \
             --exclude='slurm/' \
             --exclude='*.pyc' \
             --exclude='__pycache__' \
             "$REPO_DIR/" "$SLX_DATA_DIR/" 2>/dev/null || {
        # Fallback if rsync is not available
        cp -r "$REPO_DIR"/* "$SLX_DATA_DIR/" 2>/dev/null || true
        rm -rf "$SLX_DATA_DIR/.git" 2>/dev/null || true
        rm -rf "$SLX_DATA_DIR/projects" 2>/dev/null || true
        rm -rf "$SLX_DATA_DIR/slurm" 2>/dev/null || true
    }
    
    # Restore user data directories if preserving
    if [ "$preserve_user_data" = "true" ]; then
        if [ -d "$SLX_DATA_DIR/projects.backup."* ] 2>/dev/null; then
            LATEST_PROJECTS_BACKUP=$(ls -td "$SLX_DATA_DIR/projects.backup."* 2>/dev/null | head -1)
            if [ -n "$LATEST_PROJECTS_BACKUP" ]; then
                mv "$LATEST_PROJECTS_BACKUP" "$SLX_DATA_DIR/projects" 2>/dev/null || true
                echo -e "${GREEN}  Restored: projects/${NC}"
            fi
        fi
        
        if [ -d "$SLX_DATA_DIR/slurm.backup."* ] 2>/dev/null; then
            LATEST_SLURM_BACKUP=$(ls -td "$SLX_DATA_DIR/slurm.backup."* 2>/dev/null | head -1)
            if [ -n "$LATEST_SLURM_BACKUP" ]; then
                mv "$LATEST_SLURM_BACKUP" "$SLX_DATA_DIR/slurm" 2>/dev/null || true
                echo -e "${GREEN}  Restored: slurm/${NC}"
            fi
        fi
    fi
}

# Create wrapper script in ~/.local/bin/slx
create_wrapper() {
    cat > "$SLX_BIN" << 'EOF'
#!/bin/bash
# slx wrapper - executes the installed slx
exec "$HOME/.local/share/slx/bin/slx" "$@"
EOF
    chmod +x "$SLX_BIN"
}

# Make scripts executable
make_executable() {
    chmod +x "$SLX_DATA_DIR/bin/slx"
    chmod +x "$SLX_DATA_DIR/bin/install.sh" 2>/dev/null || true
    chmod +x "$SLX_DATA_DIR/bin/update.sh" 2>/dev/null || true
    chmod +x "$SLX_DATA_DIR/lib/slx/installer.sh" 2>/dev/null || true
    chmod +x "$SLX_DATA_DIR/lib/slx/common.sh" 2>/dev/null || true
    chmod +x "$SLX_DATA_DIR/lib/slx/commands/"*.sh 2>/dev/null || true
}

# Get current installed version
get_current_version() {
    local current_version="unknown"
    if [ -f "$SLX_DATA_DIR/bin/slx" ]; then
        # Try to extract version from the installed slx script
        if grep -q "SLX_VERSION=" "$SLX_DATA_DIR/bin/slx" 2>/dev/null; then
            current_version=$(grep "SLX_VERSION=" "$SLX_DATA_DIR/bin/slx" | head -1 | sed 's/.*SLX_VERSION="\([^"]*\)".*/\1/' || echo "unknown")
        fi
    fi
    echo "$current_version"
}
