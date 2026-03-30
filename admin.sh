#!/bin/bash
# ==============================================================================
# Business AI Infrastructure — Admin Roster Management
#
# Restricted to administrators. Manages the employee roster on the network drive.
# The roster is the single source of truth for role, department, and clearance.
# Employees may update their own name and email, but role and clearance are
# admin-controlled and cannot be self-modified.
#
# Usage:
#   ./admin.sh init         Initialise the vault and roster (first-time setup)
#   ./admin.sh add          Add a new employee to the roster
#   ./admin.sh list         List all employees in the roster
#   ./admin.sh update       Update an existing employee's role or department
#   ./admin.sh remove       Deactivate an employee
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.vault-path"

# Read saved vault path from config, or use default
if [ -f "$CONFIG_FILE" ]; then
    DEFAULT_VAULT="$(cat "$CONFIG_FILE" | tr -d '\n')"
else
    DEFAULT_VAULT="W:\\MEMORY"
fi

VAULT_PATH="${VAULT_PATH:-$DEFAULT_VAULT}"
ADMIN_DIR="$VAULT_PATH/.admin"
ROSTER_FILE="$ADMIN_DIR/roster.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ----------------------------------------------------------
# Helpers
# ----------------------------------------------------------
ensure_roster() {
    if [ ! -f "$ROSTER_FILE" ]; then
        echo -e "${RED}ERROR: Roster not found at $ROSTER_FILE${NC}"
        echo "Run './admin.sh init' first, or set VAULT_PATH."
        exit 1
    fi
}

# ----------------------------------------------------------
# Commands
# ----------------------------------------------------------
cmd_init() {
    echo -e "${BLUE}Initializing vault and admin roster...${NC}"
    echo ""

    echo "  Where should the Memory Vault be stored?"
    echo "  This can be a network drive, local folder, or any shared path."
    echo "  Examples: W:\\MEMORY, /mnt/shared/vault, ~/company-vault"
    echo ""
    read -p "  Vault path [$DEFAULT_VAULT]: " VAULT_INPUT
    VAULT_PATH="${VAULT_INPUT:-$DEFAULT_VAULT}"
    ADMIN_DIR="$VAULT_PATH/.admin"
    ROSTER_FILE="$ADMIN_DIR/roster.json"

    # Save chosen path so setup.sh and future runs use it as the default
    echo -n "$VAULT_PATH" > "$CONFIG_FILE"
    echo -e "  ${GREEN}✓${NC} Vault path saved to .vault-path"

    # Create vault directories
    mkdir -p "$VAULT_PATH/PUBLIC/processes"
    mkdir -p "$VAULT_PATH/PUBLIC/onboarding"
    mkdir -p "$VAULT_PATH/PUBLIC/tools"
    mkdir -p "$VAULT_PATH/INTERNAL/engineering"
    mkdir -p "$VAULT_PATH/INTERNAL/product"
    mkdir -p "$VAULT_PATH/INTERNAL/design"
    mkdir -p "$VAULT_PATH/INTERNAL/projects"
    mkdir -p "$VAULT_PATH/CONFIDENTIAL/hr"
    mkdir -p "$VAULT_PATH/CONFIDENTIAL/finance"
    mkdir -p "$VAULT_PATH/CONFIDENTIAL/product"
    mkdir -p "$VAULT_PATH/RESTRICTED/strategy"
    mkdir -p "$VAULT_PATH/RESTRICTED/compensation"
    mkdir -p "$VAULT_PATH/RESTRICTED/personnel"
    mkdir -p "$VAULT_PATH/AUDIT"
    mkdir -p "$ADMIN_DIR"
    echo -e "  ${GREEN}✓${NC} Vault directories created"

    # Create empty roster
    if [ ! -f "$ROSTER_FILE" ]; then
        cat > "$ROSTER_FILE" << 'EOF'
{
  "version": "1.0",
  "updated_by": "admin",
  "updated_at": "",
  "employees": {}
}
EOF
        echo -e "  ${GREEN}✓${NC} Empty roster created at $ROSTER_FILE"
    else
        echo -e "  ${YELLOW}!${NC} Roster already exists, skipping"
    fi

    echo ""
    echo -e "${GREEN}Vault initialized. Now run './admin.sh add' to add employees.${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT — Set these file/folder permissions on the vault:${NC}"
    echo ""
    echo "  Everyone (read-only):"
    echo "    $VAULT_PATH/.admin/roster.json    ← all employees must READ this"
    echo "    $VAULT_PATH/PUBLIC/               ← read + write for all"
    echo "    $VAULT_PATH/INTERNAL/             ← read + write for all"
    echo "    $VAULT_PATH/AUDIT/                ← write for all (append logs)"
    echo "    $VAULT_PATH/_index.jsonl           ← read + write for all"
    echo ""
    echo "  Admin only (you):"
    echo "    $VAULT_PATH/.admin/               ← write access only for admin"
    echo ""
    echo "  Managers + Execs only:"
    echo "    $VAULT_PATH/CONFIDENTIAL/         ← read + write for managers/execs"
    echo ""
    echo "  Execs + HR only:"
    echo "    $VAULT_PATH/RESTRICTED/           ← read + write for execs/HR leads"
    echo ""
    echo "  Set appropriate permissions for your OS (Windows ACLs, Unix chmod, etc.)."
    echo "  The hooks add a second layer of protection on top of these OS-level controls."
}

cmd_add() {
    ensure_roster
    echo -e "${BLUE}Add employee to roster${NC}"
    echo ""

    read -p "  Employee ID (e.g., emp_001): " EMP_ID

    # Check if already exists
    if command -v python3 &> /dev/null; then
        EXISTS=$(python3 -c "
import json
with open('$ROSTER_FILE') as f:
    r = json.load(f)
print('yes' if '$EMP_ID' in r.get('employees', {}) else 'no')
" 2>/dev/null || echo "no")
        if [ "$EXISTS" = "yes" ]; then
            echo -e "${YELLOW}  Employee '$EMP_ID' already exists. Use './admin.sh update' instead.${NC}"
            exit 1
        fi
    fi

    read -p "  Full name: " EMP_NAME
    read -p "  Email: " EMP_EMAIL

    echo ""
    echo "  Available departments: engineering, product, design, hr, finance, company-wide"
    read -p "  Department: " EMP_DEPT

    echo ""
    echo "  Available roles:"
    echo "    viewer           (public clearance)"
    echo "    engineer         (internal — engineering, product)"
    echo "    senior_engineer  (internal — engineering, product, design)"
    echo "    designer         (internal — design, product)"
    echo "    product_manager  (confidential — product, engineering, design)"
    echo "    hr_manager       (confidential — hr, company-wide)"
    echo "    finance_manager  (confidential — finance, company-wide)"
    echo "    director         (confidential — all departments)"
    echo "    executive        (restricted — all departments)"
    echo ""
    read -p "  Role: " EMP_ROLE

    # Map role to clearance
    case "$EMP_ROLE" in
        viewer) CLEARANCE="public" ;;
        engineer|senior_engineer|designer) CLEARANCE="internal" ;;
        product_manager|hr_manager|finance_manager|director) CLEARANCE="confidential" ;;
        executive) CLEARANCE="restricted" ;;
        *)
            echo -e "${YELLOW}  Unknown role '$EMP_ROLE', defaulting to 'internal' clearance.${NC}"
            CLEARANCE="internal"
            ;;
    esac

    echo ""
    echo -e "  ${BLUE}Summary:${NC}"
    echo "    ID:         $EMP_ID"
    echo "    Name:       $EMP_NAME"
    echo "    Email:      $EMP_EMAIL"
    echo "    Department: $EMP_DEPT"
    echo "    Role:       $EMP_ROLE"
    echo "    Clearance:  $CLEARANCE"
    echo ""
    read -p "  Confirm? (Y/n): " CONFIRM
    if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
        echo "  Cancelled."
        exit 0
    fi

    # Add to roster using python3 (available on most systems)
    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
from datetime import datetime

with open('$ROSTER_FILE', 'r') as f:
    roster = json.load(f)

roster['employees']['$EMP_ID'] = {
    'name': '$EMP_NAME',
    'email': '$EMP_EMAIL',
    'department': '$EMP_DEPT',
    'role': '$EMP_ROLE',
    'clearance': '$CLEARANCE',
    'active': True,
    'added_at': datetime.utcnow().isoformat() + 'Z'
}
roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'
roster['updated_by'] = 'admin'

with open('$ROSTER_FILE', 'w') as f:
    json.dump(roster, f, indent=2)

print('  Done.')
PYEOF
        echo -e "  ${GREEN}✓${NC} Added $EMP_NAME ($EMP_ID) to roster"
    else
        echo -e "${RED}ERROR: python3 required for roster management${NC}"
        exit 1
    fi
}

cmd_list() {
    ensure_roster
    echo -e "${BLUE}Employee Roster${NC}"
    echo ""

    if command -v python3 &> /dev/null; then
        python3 << 'PYEOF'
import json

with open('ROSTER_PLACEHOLDER', 'r') as f:
    roster = json.load(f)

employees = roster.get('employees', {})
if not employees:
    print("  No employees in roster.")
else:
    print(f"  {'ID':<14} {'Name':<20} {'Role':<18} {'Dept':<14} {'Clearance':<14} {'Active'}")
    print(f"  {'-'*13} {'-'*19} {'-'*17} {'-'*13} {'-'*13} {'-'*6}")
    for eid, emp in employees.items():
        active = "Yes" if emp.get('active', True) else "NO"
        print(f"  {eid:<14} {emp['name']:<20} {emp['role']:<18} {emp['department']:<14} {emp['clearance']:<14} {active}")
    print(f"\n  Total: {len(employees)} employees")
PYEOF
    fi
}

cmd_update() {
    ensure_roster
    echo -e "${BLUE}Update employee role/department${NC}"
    echo ""

    # Show current roster
    cmd_list
    echo ""

    read -p "  Employee ID to update: " EMP_ID
    echo ""
    echo "  Leave blank to keep current value."
    read -p "  New role (blank to skip): " NEW_ROLE
    read -p "  New department (blank to skip): " NEW_DEPT

    if [ -z "$NEW_ROLE" ] && [ -z "$NEW_DEPT" ]; then
        echo "  Nothing to update."
        exit 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
from datetime import datetime

with open('$ROSTER_FILE', 'r') as f:
    roster = json.load(f)

if '$EMP_ID' not in roster['employees']:
    print('  ERROR: Employee $EMP_ID not found in roster.')
    exit(1)

emp = roster['employees']['$EMP_ID']
role_map = {
    'viewer': 'public',
    'engineer': 'internal', 'senior_engineer': 'internal', 'designer': 'internal',
    'product_manager': 'confidential', 'hr_manager': 'confidential',
    'finance_manager': 'confidential', 'director': 'confidential',
    'executive': 'restricted'
}

if '$NEW_ROLE':
    emp['role'] = '$NEW_ROLE'
    emp['clearance'] = role_map.get('$NEW_ROLE', emp.get('clearance', 'internal'))
if '$NEW_DEPT':
    emp['department'] = '$NEW_DEPT'

roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'
roster['updated_by'] = 'admin'

with open('$ROSTER_FILE', 'w') as f:
    json.dump(roster, f, indent=2)

print(f"  Updated {emp['name']}: role={emp['role']}, dept={emp['department']}, clearance={emp['clearance']}")
PYEOF
        echo -e "  ${GREEN}✓${NC} Roster updated. Employee will see the change on next session."
    fi
}

cmd_remove() {
    ensure_roster
    echo -e "${BLUE}Deactivate employee${NC}"
    echo ""
    cmd_list
    echo ""

    read -p "  Employee ID to deactivate: " EMP_ID
    read -p "  Confirm deactivation of $EMP_ID? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "  Cancelled."
        exit 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYEOF
import json
from datetime import datetime

with open('$ROSTER_FILE', 'r') as f:
    roster = json.load(f)

if '$EMP_ID' not in roster['employees']:
    print('  ERROR: Employee $EMP_ID not found.')
    exit(1)

roster['employees']['$EMP_ID']['active'] = False
roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'

with open('$ROSTER_FILE', 'w') as f:
    json.dump(roster, f, indent=2)

print(f"  Deactivated {roster['employees']['$EMP_ID']['name']}. Their AI sessions will be blocked.")
PYEOF
        echo -e "  ${GREEN}✓${NC} Employee deactivated"
    fi
}

# Fix the ROSTER_PLACEHOLDER in cmd_list
cmd_list() {
    ensure_roster
    echo -e "${BLUE}Employee Roster${NC}"
    echo ""

    if command -v python3 &> /dev/null; then
        python3 -c "
import json
with open('$ROSTER_FILE', 'r') as f:
    roster = json.load(f)
employees = roster.get('employees', {})
if not employees:
    print('  No employees in roster.')
else:
    print(f\"  {'ID':<14} {'Name':<20} {'Role':<18} {'Dept':<14} {'Clearance':<14} {'Active'}\")
    print(f\"  {'-'*13} {'-'*19} {'-'*17} {'-'*13} {'-'*13} {'-'*6}\")
    for eid, emp in employees.items():
        active = 'Yes' if emp.get('active', True) else 'NO'
        print(f\"  {eid:<14} {emp['name']:<20} {emp['role']:<18} {emp['department']:<14} {emp['clearance']:<14} {active}\")
    print(f\"\n  Total: {len(employees)} employees\")
"
    fi
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
case "${1:-}" in
    init)   cmd_init ;;
    add)    cmd_add ;;
    list)   cmd_list ;;
    update) cmd_update ;;
    remove) cmd_remove ;;
    *)
        echo "Business AI Infrastructure — Admin Tool"
        echo ""
        echo "Usage: ./admin.sh <command>"
        echo ""
        echo "Commands:"
        echo "  init      Initialise vault directories and empty roster"
        echo "  add       Add a new employee to the roster"
        echo "  list      List all employees and their roles"
        echo "  update    Change an employee's role or department"
        echo "  remove    Deactivate an employee"
        echo ""
        echo "Set VAULT_PATH env var if vault is not at $DEFAULT_VAULT"
        ;;
esac
