#!/bin/bash
# ==============================================================================
# Athena — Employee Setup
#
# Run this after cloning the repo. It will:
#   1. Check prerequisites (Bun, with user-space install fallback)
#   2. Create your employee identity file (~/.claude/employee.json)
#   3. Copy hooks, settings, and configuration to ~/.claude/
#   4. Resolve hook paths in settings.json
#   5. Configure your vault path
#   6. Verify the setup is complete and ready
#
# Works without admin rights — Bun installs to ~/.bun if not globally available.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${HOME:-$USERPROFILE}/.claude"
EMPLOYEE_FILE="$CLAUDE_DIR/employee.json"
CONFIG_FILE="$SCRIPT_DIR/.vault-path"
VERSION_FILE="$CLAUDE_DIR/.athena-version"
BACKUP_DIR="$CLAUDE_DIR/.athena-backup"

# Auto-detect latest release version
if [ -d "$SCRIPT_DIR/Releases" ]; then
    # sort -V (version sort) may not be available on all Git Bash installs; fall back to plain sort
    LATEST_VERSION=$(ls "$SCRIPT_DIR/Releases" 2>/dev/null | sort -V 2>/dev/null || ls "$SCRIPT_DIR/Releases" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    if [ -n "$LATEST_VERSION" ]; then
        SOURCE_DIR="$SCRIPT_DIR/Releases/$LATEST_VERSION/.claude"
    else
        echo "ERROR: No releases found in $SCRIPT_DIR/Releases/"
        exit 1
    fi
else
    echo "ERROR: Releases directory not found at $SCRIPT_DIR/Releases/"
    exit 1
fi

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

# ----------------------------------------------------------
# Detect Python command (python3, python, or py -3)
# ----------------------------------------------------------
detect_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        # Verify it's Python 3
        if python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
            PYTHON_CMD="python"
        else
            PYTHON_CMD=""
        fi
    elif command -v py &> /dev/null; then
        if py -3 -c "print('ok')" &> /dev/null; then
            PYTHON_CMD="py -3"
        else
            PYTHON_CMD=""
        fi
    else
        PYTHON_CMD=""
    fi
}

# ----------------------------------------------------------
# Detect Node.js (for fallback JSON manipulation)
# ----------------------------------------------------------
detect_node() {
    if command -v node &> /dev/null; then
        NODE_CMD="node"
    else
        NODE_CMD=""
    fi
}

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}       Athena — Employee Setup ($LATEST_VERSION)       ${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# ----------------------------------------------------------
# Step 0: Check prerequisites
# ----------------------------------------------------------
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check for Bun (preferred runtime for hooks)
if command -v bun &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} bun is installed ($(bun --version))"
    BUN_AVAILABLE=true
elif [ -f "$HOME/.bun/bin/bun" ]; then
    export PATH="$HOME/.bun/bin:$PATH"
    echo -e "  ${GREEN}✓${NC} bun found at ~/.bun ($(bun --version))"
    BUN_AVAILABLE=true
else
    echo -e "  ${YELLOW}!${NC} bun is not installed globally."
    echo ""
    echo "  Bun is required to run Athena hooks."
    echo "  It can be installed to your user directory (no admin rights needed)."
    echo ""
    read -p "  Install Bun to ~/.bun? (Y/n): " INSTALL_BUN
    if [ "$INSTALL_BUN" != "n" ] && [ "$INSTALL_BUN" != "N" ]; then
        echo "  Installing Bun..."
        # On Windows (msys/cygwin), prefer PowerShell installer; on Unix, use curl
        if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && command -v powershell &> /dev/null; then
            powershell -c "irm bun.sh/install.ps1 | iex" 2>&1 | tail -3
        elif command -v curl &> /dev/null; then
            curl -fsSL https://bun.sh/install | bash 2>&1 | tail -3
        elif command -v powershell &> /dev/null; then
            powershell -c "irm bun.sh/install.ps1 | iex" 2>&1 | tail -3
        else
            echo -e "  ${RED}ERROR: Neither curl nor powershell available to install Bun.${NC}"
            echo "  Install Bun manually from https://bun.sh"
            exit 1
        fi
        export PATH="$HOME/.bun/bin:$PATH"
        if command -v bun &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} bun installed successfully ($(bun --version))"
            BUN_AVAILABLE=true
        else
            echo -e "  ${RED}ERROR: Bun installation failed.${NC}"
            echo "  Install manually: https://bun.sh"
            exit 1
        fi
    else
        echo -e "  ${RED}ERROR: Bun is required. Install from https://bun.sh${NC}"
        exit 1
    fi
fi

detect_python
detect_node

if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}ERROR: Source directory not found at $SOURCE_DIR${NC}"
    echo "Make sure you're running this from the repo root."
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Source files found ($LATEST_VERSION)"

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

    # Validate employee ID format
    if ! echo "$EMP_ID" | grep -qE '^emp_[0-9]{3,}$'; then
        echo -e "  ${YELLOW}!${NC} Employee ID should follow the format: emp_001, emp_002, etc."
        read -p "  Continue with '$EMP_ID' anyway? (y/N): " FORCE_ID
        if [ "$FORCE_ID" != "y" ] && [ "$FORCE_ID" != "Y" ]; then
            echo "  Aborted. Re-run setup with a valid employee ID."
            exit 1
        fi
    fi

    read -p "  Full name: " EMP_NAME
    read -p "  Email: " EMP_EMAIL

    mkdir -p "$CLAUDE_DIR"

    # Write employee.json safely (handles special characters in name/email)
    if [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "
const fs = require('fs');
const data = {
  employee_id: process.argv[1],
  name: process.argv[2],
  email: process.argv[3],
  department: 'pending',
  role: 'viewer',
  clearance: 'public'
};
fs.writeFileSync(process.argv[4], JSON.stringify(data, null, 2) + '\n');
" "$EMP_ID" "$EMP_NAME" "$EMP_EMAIL" "$EMPLOYEE_FILE"
    elif [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, sys
data = {
    'employee_id': sys.argv[1],
    'name': sys.argv[2],
    'email': sys.argv[3],
    'department': 'pending',
    'role': 'viewer',
    'clearance': 'public'
}
with open(sys.argv[4], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$EMP_ID" "$EMP_NAME" "$EMP_EMAIL" "$EMPLOYEE_FILE"
    else
        # Last-resort fallback: escape quotes manually
        SAFE_NAME=$(echo "$EMP_NAME" | sed 's/"/\\"/g')
        SAFE_EMAIL=$(echo "$EMP_EMAIL" | sed 's/"/\\"/g')
        cat > "$EMPLOYEE_FILE" << EOF
{
  "employee_id": "$EMP_ID",
  "name": "$SAFE_NAME",
  "email": "$SAFE_EMAIL",
  "department": "pending",
  "role": "viewer",
  "clearance": "public"
}
EOF
    fi

    echo -e "  ${GREEN}✓${NC} Created $EMPLOYEE_FILE"
    echo -e "  ${BLUE}i${NC} Role and clearance will be synced from the admin roster on first session."
    echo -e "  ${BLUE}i${NC} You can update your name/email anytime by editing $EMPLOYEE_FILE"
fi

# ----------------------------------------------------------
# Step 2: Backup existing config and copy new files
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 2: Installing configuration...${NC}"

mkdir -p "$CLAUDE_DIR"

# Backup existing config if upgrading
INSTALLED_VERSION=""
if [ -f "$VERSION_FILE" ]; then
    INSTALLED_VERSION=$(cat "$VERSION_FILE" | tr -d '\n')
fi

if [ -f "$CLAUDE_DIR/settings.json" ] || [ -d "$CLAUDE_DIR/hooks" ]; then
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    mkdir -p "$BACKUP_DIR/$TIMESTAMP"

    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        cp "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/$TIMESTAMP/settings.json"
    fi
    if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
        cp "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/$TIMESTAMP/CLAUDE.md"
    fi
    if [ -d "$CLAUDE_DIR/hooks" ]; then
        cp -r "$CLAUDE_DIR/hooks" "$BACKUP_DIR/$TIMESTAMP/hooks"
    fi

    if [ -n "$INSTALLED_VERSION" ]; then
        echo -e "  ${YELLOW}!${NC} Backed up existing config ($INSTALLED_VERSION) → .athena-backup/$TIMESTAMP"
    else
        echo -e "  ${YELLOW}!${NC} Backed up existing config → .athena-backup/$TIMESTAMP"
    fi
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
echo -e "  ${GREEN}✓${NC} Copied hooks/ ($(ls "$CLAUDE_DIR/hooks/"*.hook.ts 2>/dev/null | wc -l | tr -d ' ') hooks)"

# Save installed version
echo -n "$LATEST_VERSION" > "$VERSION_FILE"

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

# ----------------------------------------------------------
# Step 4: Resolve paths in settings.json
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 4: Configuring paths...${NC}"

# Normalize CLAUDE_DIR for the platform
HOOKS_PATH="$CLAUDE_DIR/hooks"

# Use Node, Python, or sed to update settings.json
if [ -n "$NODE_CMD" ]; then
    $NODE_CMD -e "
const fs = require('fs');
const path = '$CLAUDE_DIR/settings.json';
let content = fs.readFileSync(path, 'utf-8');
const settings = JSON.parse(content);

// Set VAULT_PATH
settings.env.VAULT_PATH = process.argv[1];

// Replace HOOKS_DIR placeholder with actual hooks path
content = JSON.stringify(settings, null, 2);
content = content.replace(/HOOKS_DIR\//g, process.argv[2].replace(/\\\\/g, '/') + '/');
fs.writeFileSync(path, content);
" "$VAULT_PATH" "$HOOKS_PATH"
    echo -e "  ${GREEN}✓${NC} Set VAULT_PATH to $VAULT_PATH"
    echo -e "  ${GREEN}✓${NC} Resolved hook paths to $HOOKS_PATH"
elif [ -n "$PYTHON_CMD" ]; then
    $PYTHON_CMD -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    content = f.read()
settings = json.loads(content)
settings['env']['VAULT_PATH'] = sys.argv[2]
content = json.dumps(settings, indent=2)
content = content.replace('HOOKS_DIR/', sys.argv[3].replace('\\\\', '/') + '/')
with open(sys.argv[1], 'w') as f:
    f.write(content)
" "$CLAUDE_DIR/settings.json" "$VAULT_PATH" "$HOOKS_PATH"
    echo -e "  ${GREEN}✓${NC} Set VAULT_PATH to $VAULT_PATH"
    echo -e "  ${GREEN}✓${NC} Resolved hook paths to $HOOKS_PATH"
else
    # Fallback: sed-based replacement
    ESCAPED_VAULT="$(echo "$VAULT_PATH" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')"
    sed -i "s|\"VAULT_PATH\": \"[^\"]*\"|\"VAULT_PATH\": \"$ESCAPED_VAULT\"|" "$CLAUDE_DIR/settings.json"

    ESCAPED_HOOKS="$(echo "$HOOKS_PATH" | sed 's/\\/\//g')"
    sed -i "s|HOOKS_DIR/|$ESCAPED_HOOKS/|g" "$CLAUDE_DIR/settings.json"

    echo -e "  ${GREEN}✓${NC} Set VAULT_PATH to $VAULT_PATH"
    echo -e "  ${GREEN}✓${NC} Resolved hook paths (via sed)"
fi

# ----------------------------------------------------------
# Step 5: Check vault exists
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 5: Vault check${NC}"

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
# Step 6: Verify
# ----------------------------------------------------------
echo ""
echo -e "${YELLOW}Step 6: Verification${NC}"

ERRORS=0

if [ -f "$CLAUDE_DIR/employee.json" ]; then
    echo -e "  ${GREEN}✓${NC} employee.json exists"
else
    echo -e "  ${RED}✗${NC} employee.json missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/settings.json" ]; then
    echo -e "  ${GREEN}✓${NC} settings.json exists"
    # Verify HOOKS_DIR placeholder was replaced
    if grep -q "HOOKS_DIR/" "$CLAUDE_DIR/settings.json"; then
        echo -e "  ${RED}✗${NC} settings.json still contains unresolved HOOKS_DIR placeholder"
        ERRORS=$((ERRORS + 1))
    fi
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
    echo -e "  ${GREEN}✓${NC} hooks installed ($(ls "$CLAUDE_DIR/hooks/"*.hook.ts 2>/dev/null | wc -l | tr -d ' ') hooks)"
else
    echo -e "  ${RED}✗${NC} hooks missing"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "$CLAUDE_DIR/hooks/patterns.yaml" ]; then
    echo -e "  ${GREEN}✓${NC} security patterns installed"
else
    echo -e "  ${YELLOW}!${NC} patterns.yaml not found — SecurityValidator will use shipped defaults"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  Setup complete! ($LATEST_VERSION)${NC}"
    echo -e "${GREEN}  Start Claude Code to begin.${NC}"
    echo -e "${GREEN}================================================${NC}"
    if [ -n "$INSTALLED_VERSION" ] && [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
        echo ""
        echo -e "  ${BLUE}i${NC} Upgraded from $INSTALLED_VERSION to $LATEST_VERSION"
        echo -e "  ${BLUE}i${NC} Previous config backed up to $BACKUP_DIR"
    fi
else
    echo -e "${RED}Setup completed with $ERRORS error(s). Check above.${NC}"
fi

echo ""
echo "To update later: git pull && ./setup.sh"
echo "To rollback:     restore files from ~/.claude/.athena-backup/"
echo ""
