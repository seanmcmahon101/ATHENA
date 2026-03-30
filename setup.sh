#!/bin/bash
# ==============================================================================
# Business AI Infrastructure — Employee Setup
#
# Run this after cloning the repo. It will:
#   1. Create your employee identity file (~/.claude/employee.json)
#   2. Copy hooks, settings, and configuration to ~/.claude/
#   3. Configure your vault path
#   4. Verify the setup is complete and ready
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/Releases/v4.0.3/.claude"
CLAUDE_DIR="$HOME/.claude"
EMPLOYEE_FILE="$CLAUDE_DIR/employee.json"
CONFIG_FILE="$SCRIPT_DIR/.vault-path"

# Read saved vault path from admin config, or use default
if [ -f "$CONFIG_FILE" ]; then
    DEFAULT_VAULT="$(cat "$CONFIG_FILE" | tr -d '\n')"
else
    DEFAULT_VAULT="W:\\MEMORY"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}   Business AI Infrastructure — Employee Setup  ${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# ----------------------------------------------------------
# Step 0: Check prerequisites
# ----------------------------------------------------------
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v bun &> /dev/null; then
    echo -e "${RED}ERROR: 'bun' is not installed.${NC}"
    echo "Install it from https://bun.sh"
    echo "  curl -fsSL https://bun.sh/install | bash"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} bun is installed ($(bun --version))"

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}ERROR: Source directory not found at $SOURCE_DIR${NC}"
    echo "Make sure you're running this from the repo root."
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Source files found"

# ----------------------------------------------------------
# Step 1: Create employee identity
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 1: Employee Identity${NC}"

if [ -f "$EMPLOYEE_FILE" ]; then
    echo -e "  ${GREEN}✓${NC} Employee file already exists at $EMPLOYEE_FILE"
    echo "    Current identity:"
    cat "$EMPLOYEE_FILE" | head -20
    echo ""
    read -p "  Overwrite? (y/N): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "  Keeping existing identity."
        SKIP_IDENTITY=true
    fi
fi

if [ "$SKIP_IDENTITY" != "true" ]; then
    echo ""
    echo "  Your admin assigns your role and clearance via the admin roster."
    echo "  You only need to provide your ID, name, and email here."
    echo ""
    read -p "  Employee ID (given to you by your admin, e.g., emp_001): " EMP_ID
    read -p "  Full name: " EMP_NAME
    read -p "  Email: " EMP_EMAIL

    mkdir -p "$CLAUDE_DIR"

    # Write employee.json with placeholder role/clearance
    # The IntegrityCheck hook will auto-sync these from the admin roster on first session
    cat > "$EMPLOYEE_FILE" << EOF
{
  "employee_id": "$EMP_ID",
  "name": "$EMP_NAME",
  "email": "$EMP_EMAIL",
  "department": "pending",
  "role": "viewer",
  "clearance": "public"
}
EOF

    echo -e "  ${GREEN}✓${NC} Created $EMPLOYEE_FILE"
    echo -e "  ${BLUE}i${NC} Role and clearance will be synced from the admin roster on first session."
    echo -e "  ${BLUE}i${NC} You can update your name/email anytime by editing $EMPLOYEE_FILE"
fi

# ----------------------------------------------------------
# Step 2: Copy configuration to ~/.claude/
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 2: Installing configuration...${NC}"

mkdir -p "$CLAUDE_DIR"

# Backup existing settings if present
if [ -f "$CLAUDE_DIR/settings.json" ]; then
    BACKUP="$CLAUDE_DIR/settings.json.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CLAUDE_DIR/settings.json" "$BACKUP"
    echo -e "  ${YELLOW}!${NC} Backed up existing settings.json → $(basename $BACKUP)"
fi

# Copy files
cp "$SOURCE_DIR/settings.json" "$CLAUDE_DIR/settings.json"
echo -e "  ${GREEN}✓${NC} Copied settings.json"

cp "$SOURCE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo -e "  ${GREEN}✓${NC} Copied CLAUDE.md"

cp "$SOURCE_DIR/company-roles.json" "$CLAUDE_DIR/company-roles.json"
echo -e "  ${GREEN}✓${NC} Copied company-roles.json"

# Copy hooks (remove old hooks first to avoid stale files)
if [ -d "$CLAUDE_DIR/hooks" ]; then
    rm -rf "$CLAUDE_DIR/hooks"
fi
cp -r "$SOURCE_DIR/hooks" "$CLAUDE_DIR/hooks"
echo -e "  ${GREEN}✓${NC} Copied hooks/"

# ----------------------------------------------------------
# Step 3: Configure vault path
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 3: Memory Vault${NC}"

if [ -f "$CONFIG_FILE" ]; then
    echo -e "  ${GREEN}✓${NC} Vault path auto-detected from admin config: $DEFAULT_VAULT"
fi
echo ""
read -p "  Vault path [$DEFAULT_VAULT]: " VAULT_INPUT
VAULT_PATH="${VAULT_INPUT:-$DEFAULT_VAULT}"

# Update VAULT_PATH in settings.json (replaces whatever value is currently set)
if command -v python3 &> /dev/null; then
    python3 -c "
import json
with open('$CLAUDE_DIR/settings.json', 'r') as f:
    settings = json.load(f)
settings['env']['VAULT_PATH'] = '''$VAULT_PATH'''
with open('$CLAUDE_DIR/settings.json', 'w') as f:
    json.dump(settings, f, indent=2)
"
    echo -e "  ${GREEN}✓${NC} Set VAULT_PATH to $VAULT_PATH in settings.json"
elif command -v sed &> /dev/null; then
    ESCAPED_PATH="$(echo "$VAULT_PATH" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')"
    sed -i "s|\"VAULT_PATH\": \"[^\"]*\"|\"VAULT_PATH\": \"$ESCAPED_PATH\"|" "$CLAUDE_DIR/settings.json"
    echo -e "  ${GREEN}✓${NC} Set VAULT_PATH to $VAULT_PATH in settings.json"
fi

# ----------------------------------------------------------
# Step 4: Check vault exists
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 4: Vault check${NC}"

if [ -d "$VAULT_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Vault directory exists at $VAULT_PATH"
    if [ -f "$VAULT_PATH/.admin/roster.json" ]; then
        echo -e "  ${GREEN}✓${NC} Admin roster found"
    else
        echo -e "  ${YELLOW}!${NC} No admin roster found. Ask your admin to run './admin.sh init'"
    fi
else
    echo -e "  ${YELLOW}!${NC} Vault not found at $VAULT_PATH"
    echo "    Ask your admin to run './admin.sh init' to set up the vault."
fi

# ----------------------------------------------------------
# Step 5: Verify
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 5: Verification${NC}"

ERRORS=0

if [ -f "$CLAUDE_DIR/employee.json" ]; then
    echo -e "  ${GREEN}✓${NC} employee.json exists"
else
    echo -e "  ${RED}✗${NC} employee.json missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo -e "  ${GREEN}✓${NC} settings.json exists"
else
    echo -e "  ${RED}✗${NC} settings.json missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo -e "  ${GREEN}✓${NC} CLAUDE.md exists"
else
    echo -e "  ${RED}✗${NC} CLAUDE.md missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/company-roles.json" ]; then
    echo -e "  ${GREEN}✓${NC} company-roles.json exists"
else
    echo -e "  ${RED}✗${NC} company-roles.json missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/hooks/AccessControl.hook.ts" ]; then
    echo -e "  ${GREEN}✓${NC} hooks installed ($(ls "$CLAUDE_DIR/hooks/"*.hook.ts 2>/dev/null | wc -l) hooks)"
else
    echo -e "  ${RED}✗${NC} hooks missing"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Setup complete! Start the AI assistant to begin.${NC}"
    echo -e "${GREEN}================================================${NC}"
else
    echo -e "${RED}Setup completed with $ERRORS error(s). Check above.${NC}"
fi

echo ""
echo "To update later, pull the repo and re-run this script."
echo ""
