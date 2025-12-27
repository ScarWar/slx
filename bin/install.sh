#!/bin/bash
# slx (SLurm eXtended) Installation Script
# Installs slx to ~/.local with config in ~/.config/slx

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
echo -e "${BLUE}${BOLD}slx${NC}${BLUE} - SLurm eXtended Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "This will install ${BOLD}slx${NC} v${SLX_VERSION} to:"
echo -e "  Executable: ${CYAN}${SLX_BIN}${NC}"
echo -e "  Data:       ${CYAN}${SLX_DATA_DIR}${NC}"
echo -e "  Config:     ${CYAN}${SLX_CONFIG_DIR}${NC}"
echo ""

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

# Check for command conflicts
check_alias_conflicts() {
    local conflicts=""
    
    for alias in sx sxs sxl sxls sxr sxpd sxk sxka sxt sxi sxst sxh sxf sxcl sxp sxpn sxps sxpl; do
        if command -v "$alias" &> /dev/null; then
            local cmd_path=$(command -v "$alias")
            # Skip if it's our own alias
            if [[ "$cmd_path" != *"slx"* ]]; then
                conflicts+="  $alias -> $cmd_path\n"
            fi
        fi
    done
    
    if [ -n "$conflicts" ]; then
        echo -e "${YELLOW}Warning: Some aliases may conflict with existing commands:${NC}"
        echo -e "$conflicts"
        return 1
    fi
    return 0
}

# Confirm installation
echo -ne "${YELLOW}Continue with installation? [Y/n]${NC}: "
read -r confirm
if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
    echo "Installation cancelled"
    exit 0
fi

echo ""

# Detect shell
DETECTED_SHELL=$(detect_shell)
echo -e "${GREEN}Detected shell: ${DETECTED_SHELL}${NC}"

get_input "Which shell do you want to configure?" "$DETECTED_SHELL" "SHELL_TYPE"

# Validate shell type
case "$SHELL_TYPE" in
    bash|zsh|csh|tcsh)
        ;;
    *)
        echo -e "${YELLOW}Unknown shell type, defaulting to: $DETECTED_SHELL${NC}"
        SHELL_TYPE="$DETECTED_SHELL"
        ;;
esac

echo ""

# Create directories
echo -e "${BLUE}Creating directories...${NC}"
mkdir -p "$LOCAL_BIN"
mkdir -p "$SLX_DATA_DIR"
mkdir -p "$SLX_CONFIG_DIR"

# Copy payload to ~/.local/share/slx/
echo -e "${BLUE}Installing slx to ${SLX_DATA_DIR}...${NC}"

# Clean previous installation
if [ -d "$SLX_DATA_DIR" ]; then
    rm -rf "$SLX_DATA_DIR"/*
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

# Make scripts executable
chmod +x "$SLX_DATA_DIR/bin/slx"
chmod +x "$SLX_DATA_DIR/bin/install.sh" 2>/dev/null || true

# Create wrapper script in ~/.local/bin/slx
echo -e "${BLUE}Creating slx command...${NC}"
cat > "$SLX_BIN" << 'EOF'
#!/bin/bash
# slx wrapper - executes the installed slx
exec "$HOME/.local/share/slx/bin/slx" "$@"
EOF
chmod +x "$SLX_BIN"

echo -e "${GREEN}slx command installed to: ${SLX_BIN}${NC}"

# Check if ~/.local/bin is in PATH
PATH_CONFIGURED=false
if echo "$PATH" | grep -q "$LOCAL_BIN"; then
    PATH_CONFIGURED=true
    echo -e "${GREEN}~/.local/bin is already in PATH${NC}"
else
    echo -e "${YELLOW}~/.local/bin is not in your PATH${NC}"
fi

echo ""

# Ask about aliases
echo -e "${CYAN}Would you like to set up short aliases?${NC}"
echo "  (sx, sxs, sxl, sxls, sxr, sxpd, sxk, sxka, sxt, sxi, sxst, sxh, sxf, sxcl)"
echo -ne "${YELLOW}Install aliases? [Y/n]${NC}: "
read -r install_aliases

INSTALL_ALIASES=true
if [ "$install_aliases" = "n" ] || [ "$install_aliases" = "N" ]; then
    INSTALL_ALIASES=false
fi

# Check for conflicts if installing aliases
if [ "$INSTALL_ALIASES" = true ]; then
    if ! check_alias_conflicts; then
        echo -ne "${YELLOW}Continue anyway? [y/N]${NC}: "
        read -r continue_aliases
        if [ "$continue_aliases" != "y" ] && [ "$continue_aliases" != "Y" ]; then
            INSTALL_ALIASES=false
            echo -e "${YELLOW}Aliases will not be installed${NC}"
        fi
    fi
fi

# Create aliases file
if [ "$INSTALL_ALIASES" = true ]; then
    echo -e "${BLUE}Creating aliases...${NC}"
    
    if [ "$SHELL_TYPE" = "tcsh" ] || [ "$SHELL_TYPE" = "csh" ]; then
        # tcsh/csh aliases
        cat > "$SLX_CONFIG_DIR/aliases.tcsh" << 'EOF'
# slx aliases for tcsh/csh
# Source this file in your .tcshrc or .cshrc

alias slx '$HOME/.local/bin/slx'
alias sx 'slx'
alias sxs 'slx submit'
alias sxl 'slx logs'
alias sxls 'slx list'
alias sxr 'slx running'
alias sxpd 'slx pending'
alias sxk 'slx kill'
alias sxka 'slx killall'
alias sxt 'slx tail'
alias sxi 'slx info'
alias sxst 'slx status'
alias sxh 'slx history'
alias sxf 'slx find'
alias sxcl 'slx clean'
alias sxp 'slx project'
alias sxpn 'slx project new'
alias sxps 'slx project submit'
alias sxpl 'slx project list'
EOF
        echo -e "${GREEN}Aliases saved to: ${SLX_CONFIG_DIR}/aliases.tcsh${NC}"
    else
        # bash/zsh aliases
        cat > "$SLX_CONFIG_DIR/aliases.sh" << 'EOF'
# slx aliases for bash/zsh
# Source this file in your .bashrc or .zshrc

alias slx='$HOME/.local/bin/slx'
alias sx='slx'
alias sxs='slx submit'
alias sxl='slx logs'
alias sxls='slx list'
alias sxr='slx running'
alias sxpd='slx pending'
alias sxk='slx kill'
alias sxka='slx killall'
alias sxt='slx tail'
alias sxi='slx info'
alias sxst='slx status'
alias sxh='slx history'
alias sxf='slx find'
alias sxcl='slx clean'
alias sxp='slx project'
alias sxpn='slx project new'
alias sxps='slx project submit'
alias sxpl='slx project list'
EOF
        echo -e "${GREEN}Aliases saved to: ${SLX_CONFIG_DIR}/aliases.sh${NC}"
    fi
fi

echo ""

# Ask about completion
echo -ne "${CYAN}Enable tab completion? [Y/n]${NC}: "
read -r enable_completion

ENABLE_COMPLETION=true
if [ "$enable_completion" = "n" ] || [ "$enable_completion" = "N" ]; then
    ENABLE_COMPLETION=false
fi

echo ""

# Determine shell config file
case "$SHELL_TYPE" in
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
esac

# Create shell config if it doesn't exist
if [ ! -f "$SHELL_CONFIG" ]; then
    touch "$SHELL_CONFIG"
fi

# Build the configuration block
echo -e "${BLUE}Configuring shell...${NC}"

CONFIG_MARKER="# slx (SLurm eXtended)"

# Check if already configured
if grep -q "$CONFIG_MARKER" "$SHELL_CONFIG" 2>/dev/null; then
    echo -e "${YELLOW}slx configuration already exists in $SHELL_CONFIG${NC}"
    echo -ne "${YELLOW}Update existing configuration? [Y/n]${NC}: "
    read -r update_config
    
    if [ "$update_config" != "n" ] && [ "$update_config" != "N" ]; then
        # Remove old configuration
        if [ "$SHELL_TYPE" = "tcsh" ] || [ "$SHELL_TYPE" = "csh" ]; then
            sed -i '/# slx (SLurm eXtended)/,/^endif/d' "$SHELL_CONFIG" 2>/dev/null || \
            sed -i '' '/# slx (SLurm eXtended)/,/^endif/d' "$SHELL_CONFIG" 2>/dev/null || true
        else
            sed -i '/# slx (SLurm eXtended)/,/^fi$/d' "$SHELL_CONFIG" 2>/dev/null || \
            sed -i '' '/# slx (SLurm eXtended)/,/^fi$/d' "$SHELL_CONFIG" 2>/dev/null || true
        fi
        echo -e "${GREEN}Removed old configuration${NC}"
    else
        echo -e "${YELLOW}Keeping existing configuration${NC}"
    fi
fi

# Add new configuration if not present
if ! grep -q "$CONFIG_MARKER" "$SHELL_CONFIG" 2>/dev/null; then
    # Backup
    cp "$SHELL_CONFIG" "$SHELL_CONFIG.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    if [ "$SHELL_TYPE" = "tcsh" ] || [ "$SHELL_TYPE" = "csh" ]; then
        # tcsh/csh configuration
        cat >> "$SHELL_CONFIG" << EOF

# slx (SLurm eXtended)
if ( -d \$HOME/.local/bin ) then
    setenv PATH \$HOME/.local/bin:\$PATH
endif
EOF
        if [ "$INSTALL_ALIASES" = true ]; then
            cat >> "$SHELL_CONFIG" << EOF
if ( -f $ALIAS_FILE ) then
    source $ALIAS_FILE
endif
EOF
        fi
        echo "endif" >> "$SHELL_CONFIG"  # Close the slx block marker for cleanup
        
    else
        # bash/zsh configuration
        cat >> "$SHELL_CONFIG" << EOF

# slx (SLurm eXtended)
if [ -d "\$HOME/.local/bin" ]; then
    export PATH="\$HOME/.local/bin:\$PATH"
fi
EOF
        if [ "$INSTALL_ALIASES" = true ]; then
            cat >> "$SHELL_CONFIG" << EOF
if [ -f "$ALIAS_FILE" ]; then
    source "$ALIAS_FILE"
fi
EOF
        fi
        if [ "$ENABLE_COMPLETION" = true ] && [ -n "$COMPLETION_FILE" ]; then
            cat >> "$SHELL_CONFIG" << EOF
if [ -f "$COMPLETION_FILE" ]; then
    source "$COMPLETION_FILE"
fi
EOF
        fi
    fi
    
    echo -e "${GREEN}Configuration added to: $SHELL_CONFIG${NC}"
fi

# Create initial config.env if it doesn't exist
if [ ! -f "$SLX_CONFIG_DIR/config.env" ]; then
    cat > "$SLX_CONFIG_DIR/config.env" << EOF
# slx configuration file
# Run 'slx init' to update these settings interactively

# WORKDIR: Base directory for projects
SLX_WORKDIR="$HOME/workdir"

# Default SLURM job settings (empty = use cluster defaults)
SLX_PARTITION=""
SLX_ACCOUNT=""
SLX_QOS=""
SLX_TIME="1440"
SLX_NODES="1"
SLX_NTASKS="1"
SLX_CPUS="4"
SLX_MEM="50000"
SLX_GPUS=""
SLX_EXCLUDE=""

# Log directory
SLX_LOG_DIR="\${SLX_WORKDIR}/slurm/logs"
EOF
    echo -e "${GREEN}Initial config created: $SLX_CONFIG_DIR/config.env${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}${BOLD}Installation Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "slx has been installed successfully."
echo ""
echo -e "${YELLOW}To start using slx:${NC}"
echo -e "  1. Start a new shell session, or"
echo -e "  2. Run: ${CYAN}source $SHELL_CONFIG${NC}"
echo ""
echo -e "${YELLOW}Quick start:${NC}"
echo -e "  ${CYAN}slx init${NC}           # Configure slx for your cluster"
echo -e "  ${CYAN}slx project new${NC}    # Create a new project"
echo -e "  ${CYAN}slx project submit${NC} # Submit a project job"
echo -e "  ${CYAN}slx list${NC}           # List your jobs"
echo ""

if [ "$INSTALL_ALIASES" = true ]; then
    echo -e "${YELLOW}Available aliases:${NC}"
    echo -e "  ${CYAN}sx${NC}   - slx (base command)"
    echo -e "  ${CYAN}sxs${NC}  - slx submit"
    echo -e "  ${CYAN}sxl${NC}  - slx logs"
    echo -e "  ${CYAN}sxls${NC} - slx list"
    echo -e "  ${CYAN}sxpn${NC} - slx project new"
    echo -e "  ${CYAN}sxps${NC} - slx project submit"
    echo ""
fi

echo -e "For more information: ${CYAN}slx help${NC}"
echo ""
