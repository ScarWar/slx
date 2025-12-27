#!/bin/bash
# slx (SLurm eXtended) Update Script
# Updates slx installation while preserving user configuration

set -e

# Tool info
SLX_NAME="slx"
SLX_VERSION="1.0.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Get the directory where this script is located (repo root is parent of bin/)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# XDG directories (with fallbacks)
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
LOCAL_BIN="$HOME/.local/bin"

# slx installation paths
SLX_CONFIG_DIR="${XDG_CONFIG_HOME}/${SLX_NAME}"
SLX_DATA_DIR="${XDG_DATA_HOME}/${SLX_NAME}"
SLX_BIN="${LOCAL_BIN}/${SLX_NAME}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}${BOLD}slx${NC}${BLUE} - SLurm eXtended Updater${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if slx is installed
if [ ! -d "$SLX_DATA_DIR" ] || [ ! -f "$SLX_BIN" ]; then
    echo -e "${RED}Error: slx is not installed.${NC}"
    echo -e "Please run ${CYAN}./bin/install.sh${NC} first."
    exit 1
fi

# Get current version if available
CURRENT_VERSION="unknown"
if [ -f "$SLX_DATA_DIR/bin/slx" ]; then
    # Try to extract version from the installed slx script
    if grep -q "SLX_VERSION=" "$SLX_DATA_DIR/bin/slx" 2>/dev/null; then
        CURRENT_VERSION=$(grep "SLX_VERSION=" "$SLX_DATA_DIR/bin/slx" | head -1 | sed 's/.*SLX_VERSION="\([^"]*\)".*/\1/' || echo "unknown")
    fi
fi

echo -e "Current version: ${CYAN}${CURRENT_VERSION}${NC}"
echo -e "New version:     ${CYAN}${SLX_VERSION}${NC}"
echo ""

# Backup user configuration
echo -e "${BLUE}Backing up user configuration...${NC}"
BACKUP_DIR="$SLX_CONFIG_DIR/backup.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup config files
if [ -f "$SLX_CONFIG_DIR/config.env" ]; then
    cp "$SLX_CONFIG_DIR/config.env" "$BACKUP_DIR/config.env"
    echo -e "${GREEN}  Backed up: config.env${NC}"
fi

if [ -f "$SLX_CONFIG_DIR/aliases.sh" ]; then
    cp "$SLX_CONFIG_DIR/aliases.sh" "$BACKUP_DIR/aliases.sh"
    echo -e "${GREEN}  Backed up: aliases.sh${NC}"
fi

if [ -f "$SLX_CONFIG_DIR/aliases.tcsh" ]; then
    cp "$SLX_CONFIG_DIR/aliases.tcsh" "$BACKUP_DIR/aliases.tcsh"
    echo -e "${GREEN}  Backed up: aliases.tcsh${NC}"
fi

echo ""

# Update the payload
echo -e "${BLUE}Updating slx files...${NC}"

# Clean previous installation (but preserve user data in projects/ and slurm/ if they exist)
if [ -d "$SLX_DATA_DIR" ]; then
    # Backup user data directories if they exist
    if [ -d "$SLX_DATA_DIR/projects" ]; then
        echo -e "${YELLOW}  Preserving: projects/${NC}"
        mv "$SLX_DATA_DIR/projects" "$SLX_DATA_DIR/projects.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    if [ -d "$SLX_DATA_DIR/slurm" ]; then
        echo -e "${YELLOW}  Preserving: slurm/${NC}"
        mv "$SLX_DATA_DIR/slurm" "$SLX_DATA_DIR/slurm.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi
    
    # Remove everything except config
    find "$SLX_DATA_DIR" -mindepth 1 -maxdepth 1 ! -name 'projects*' ! -name 'slurm*' -exec rm -rf {} + 2>/dev/null || true
fi

# Copy new files
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

# Restore user data directories
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

# Make scripts executable
chmod +x "$SLX_DATA_DIR/bin/slx"
chmod +x "$SLX_DATA_DIR/bin/install.sh" 2>/dev/null || true
chmod +x "$SLX_DATA_DIR/bin/update.sh" 2>/dev/null || true

# Update wrapper script (in case it changed)
cat > "$SLX_BIN" << 'EOF'
#!/bin/bash
# slx wrapper - executes the installed slx
exec "$HOME/.local/share/slx/bin/slx" "$@"
EOF
chmod +x "$SLX_BIN"

echo -e "${GREEN}slx files updated${NC}"
echo ""

# Check if shell config needs updating (only if completion file changed)
echo -e "${BLUE}Checking shell configuration...${NC}"

# Detect shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$SHELL" ]; then
        case "$SHELL" in
            *zsh*) echo "zsh" ;;
            *bash*) echo "bash" ;;
            *) echo "bash" ;;
        esac
    else
        echo "bash"
    fi
}

DETECTED_SHELL=$(detect_shell)

# Determine shell config file
case "$DETECTED_SHELL" in
    bash)
        SHELL_CONFIG="$HOME/.bashrc"
        COMPLETION_FILE="$SLX_DATA_DIR/completions/slx.bash"
        ;;
    zsh)
        SHELL_CONFIG="$HOME/.zshrc"
        COMPLETION_FILE="$SLX_DATA_DIR/completions/slx.zsh"
        ;;
    *)
        SHELL_CONFIG=""
        COMPLETION_FILE=""
        ;;
esac

# Check if completion is already configured
if [ -n "$SHELL_CONFIG" ] && [ -f "$SHELL_CONFIG" ]; then
    if grep -q "$COMPLETION_FILE" "$SHELL_CONFIG" 2>/dev/null; then
        echo -e "${GREEN}  Shell completion already configured${NC}"
    else
        echo -e "${YELLOW}  Shell completion not configured${NC}"
        echo -e "${YELLOW}  Run ${CYAN}./bin/install.sh${NC} to enable completion${NC}"
    fi
fi

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}${BOLD}Update Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "slx has been updated from ${CYAN}${CURRENT_VERSION}${NC} to ${CYAN}${SLX_VERSION}${NC}"
echo ""
echo -e "${YELLOW}Configuration preserved:${NC}"
echo -e "  Config:     ${CYAN}${SLX_CONFIG_DIR}/config.env${NC}"
if [ -f "$SLX_CONFIG_DIR/aliases.sh" ] || [ -f "$SLX_CONFIG_DIR/aliases.tcsh" ]; then
    echo -e "  Aliases:    ${CYAN}${SLX_CONFIG_DIR}/aliases.*${NC}"
fi
echo -e "  Backup:     ${CYAN}${BACKUP_DIR}${NC}"
echo ""
echo -e "${YELLOW}To use the updated version:${NC}"
echo -e "  Start a new shell session, or"
if [ -n "$SHELL_CONFIG" ]; then
    echo -e "  Run: ${CYAN}source $SHELL_CONFIG${NC}"
fi
echo ""
echo -e "For more information: ${CYAN}slx help${NC}"
echo ""
