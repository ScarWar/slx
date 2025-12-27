#!/bin/bash
# slx (SLurm eXtended) Update Script
# Updates slx installation while preserving user configuration

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

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
CURRENT_VERSION=$(get_current_version)

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

# Install files (preserve user data for update)
install_files true

# Make scripts executable
make_executable

# Update wrapper script (in case it changed)
create_wrapper

echo -e "${GREEN}slx files updated${NC}"
echo ""

# Check if shell config needs updating (only if completion file changed)
echo -e "${BLUE}Checking shell configuration...${NC}"

DETECTED_SHELL=$(detect_shell)

# Determine shell config file
get_shell_config "$DETECTED_SHELL"

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
