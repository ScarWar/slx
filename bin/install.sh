#!/bin/bash
# Installation script for SLURM Cluster Management Tools
# Supports bash, zsh, csh, and tcsh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the directory where this script is located (parent of bin/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SLURM Cluster Management Tools Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detect current shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    elif [ -n "$tcsh" ] || [ -n "$csh" ]; then
        # Check if it's tcsh or csh
        if [ -n "$tcsh" ] || echo "$SHELL" | grep -q "tcsh"; then
            echo "tcsh"
        else
            echo "csh"
        fi
    elif [ -n "$SHELL" ]; then
        # Parse from SHELL variable
        case "$SHELL" in
            *zsh*) echo "zsh" ;;
            *bash*) echo "bash" ;;
            *tcsh*) echo "tcsh" ;;
            *csh*) echo "csh" ;;
            *) echo "bash" ;; # Default to bash
        esac
    else
        echo "bash" # Default fallback
    fi
}

# Get user input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        echo -ne "${CYAN}$prompt${NC} ${YELLOW}[$default]${NC}: "
    else
        echo -ne "${CYAN}$prompt${NC}: "
    fi
    
    read -r input
    
    if [ -z "$input" ] && [ -n "$default" ]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$input'"
    fi
}

# Detect shell
DETECTED_SHELL=$(detect_shell)
echo -e "${GREEN}Detected shell: ${DETECTED_SHELL}${NC}"
echo ""

# Ask for shell type
get_input "Which shell do you want to configure?" "$DETECTED_SHELL" "SHELL_TYPE"

# Validate shell type
case "$SHELL_TYPE" in
    bash|zsh|csh|tcsh)
        echo -e "${GREEN}Using shell: $SHELL_TYPE${NC}"
        ;;
    *)
        echo -e "${RED}Invalid shell type: $SHELL_TYPE${NC}"
        echo -e "${YELLOW}Defaulting to: $DETECTED_SHELL${NC}"
        SHELL_TYPE="$DETECTED_SHELL"
        ;;
esac

echo ""

# Get HOME directory
DEFAULT_HOME="$HOME"
get_input "Enter your HOME directory" "$DEFAULT_HOME" "USER_HOME"

# Expand ~ and variables
USER_HOME=$(eval echo "$USER_HOME")

# Validate HOME directory
if [ ! -d "$USER_HOME" ]; then
    echo -e "${RED}Error: Directory '$USER_HOME' does not exist${NC}"
    exit 1
fi

echo ""

# Get WORKDIR
DEFAULT_WORKDIR="$SCRIPT_DIR"
get_input "Enter the cluster tools workdir" "$DEFAULT_WORKDIR" "WORKDIR"

# Expand ~ and variables
WORKDIR=$(eval echo "$WORKDIR")

# Validate WORKDIR
if [ ! -d "$WORKDIR" ]; then
    echo -e "${RED}Error: Directory '$WORKDIR' does not exist${NC}"
    exit 1
fi

# Check if cluster.sh exists
if [ ! -f "$WORKDIR/bin/cluster.sh" ]; then
    echo -e "${RED}Error: cluster.sh not found in '$WORKDIR/bin'${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  Shell: ${GREEN}$SHELL_TYPE${NC}"
echo -e "  HOME: ${GREEN}$USER_HOME${NC}"
echo -e "  WORKDIR: ${GREEN}$WORKDIR${NC}"
echo ""

# Confirm
echo -ne "${YELLOW}Proceed with installation? [y/N]${NC}: "
read -r confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo -e "${YELLOW}Installation cancelled${NC}"
    exit 0
fi

echo ""

# Determine shell config file
case "$SHELL_TYPE" in
    bash)
        SHELL_CONFIG="$USER_HOME/.bashrc"
        ALIAS_FILE="$WORKDIR/cluster_aliases.sh"
        ;;
    zsh)
        SHELL_CONFIG="$USER_HOME/.zshrc"
        ALIAS_FILE="$WORKDIR/cluster_aliases.sh"
        ;;
    tcsh)
        SHELL_CONFIG="$USER_HOME/.tcshrc"
        ALIAS_FILE="$WORKDIR/cluster_aliases.tcsh"
        ;;
    csh)
        SHELL_CONFIG="$USER_HOME/.cshrc"
        ALIAS_FILE="$WORKDIR/cluster_aliases.tcsh"
        ;;
esac

# Check if alias file exists
if [ ! -f "$ALIAS_FILE" ]; then
    echo -e "${RED}Error: Alias file '$ALIAS_FILE' not found${NC}"
    exit 1
fi

# Create shell config if it doesn't exist
if [ ! -f "$SHELL_CONFIG" ]; then
    echo -e "${YELLOW}Creating $SHELL_CONFIG${NC}"
    touch "$SHELL_CONFIG"
fi

# Check if already configured
CONFIG_MARKER="# SLURM Cluster Management Tools"
if grep -q "$CONFIG_MARKER" "$SHELL_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}Configuration already exists in $SHELL_CONFIG${NC}"
    echo -ne "${YELLOW}Update existing configuration? [y/N]${NC}: "
    read -r update
    if [ "$update" != "y" ] && [ "$update" != "Y" ]; then
        echo -e "${YELLOW}Skipping configuration update${NC}"
    else
        # Remove old configuration
        if [ "$SHELL_TYPE" = "tcsh" ] || [ "$SHELL_TYPE" = "csh" ]; then
            sed -i '/# SLURM Cluster Management Tools/,/^fi$/d' "$SHELL_CONFIG" 2>/dev/null || \
            sed -i '/# SLURM Cluster Management Tools/,/^endif$/d' "$SHELL_CONFIG" 2>/dev/null || true
        else
            sed -i '/# SLURM Cluster Management Tools/,/^fi$/d' "$SHELL_CONFIG" 2>/dev/null || true
        fi
        echo -e "${GREEN}Removed old configuration${NC}"
    fi
fi

# Add configuration
if ! grep -q "$CONFIG_MARKER" "$SHELL_CONFIG" 2>/dev/null || [ "$update" = "y" ] || [ "$update" = "Y" ]; then
    echo -e "${GREEN}Adding configuration to $SHELL_CONFIG${NC}"
    
    # Create backup
    cp "$SHELL_CONFIG" "$SHELL_CONFIG.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Add configuration based on shell type
    if [ "$SHELL_TYPE" = "tcsh" ] || [ "$SHELL_TYPE" = "csh" ]; then
        cat >> "$SHELL_CONFIG" << EOF

# SLURM Cluster Management Tools
setenv CLUSTER_WORKDIR $WORKDIR
if ( -f \$CLUSTER_WORKDIR/cluster_aliases.tcsh ) then
    source \$CLUSTER_WORKDIR/cluster_aliases.tcsh
endif
EOF
    else
        # bash/zsh
        cat >> "$SHELL_CONFIG" << EOF

# SLURM Cluster Management Tools
export CLUSTER_WORKDIR="$WORKDIR"
if [ -f "\$CLUSTER_WORKDIR/cluster_aliases.sh" ]; then
    source "\$CLUSTER_WORKDIR/cluster_aliases.sh"
fi
EOF
    fi
    
    echo -e "${GREEN}Configuration added successfully!${NC}"
else
    echo -e "${YELLOW}Configuration already exists, skipping${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "The cluster management tools have been configured for ${GREEN}$SHELL_TYPE${NC}."
echo ""
echo -e "${YELLOW}To use the tools:${NC}"
echo -e "  1. Start a new shell session, or"
echo -e "  2. Run: ${CYAN}source $SHELL_CONFIG${NC}"
echo ""
echo -e "${YELLOW}Available aliases:${NC}"
echo -e "  ${CYAN}cs${NC}  - Submit a job"
echo -e "  ${CYAN}cl${NC}  - View job logs"
echo -e "  ${CYAN}cls${NC} - List jobs"
echo -e "  ${CYAN}cr${NC}  - List running jobs"
echo -e "  ${CYAN}cpd${NC} - List pending jobs"
echo -e "  ${CYAN}ck${NC}  - Kill a job"
echo -e "  ${CYAN}ct${NC}  - Tail logs"
echo -e "  ${CYAN}ci${NC}  - Show job info"
echo -e "  ${CYAN}cst${NC} - Show status"
echo -e "  ${CYAN}ch${NC}  - Show history"
echo -e "  ${CYAN}cf${NC}  - Find jobs"
echo -e "  ${CYAN}ccl${NC} - Clean logs"
echo ""
echo -e "For more information, see: ${CYAN}$WORKDIR/README.md${NC}"
echo ""

