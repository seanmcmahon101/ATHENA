#!/bin/bash
# ==============================================================================
# Athena — Admin Roster Management
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
#   ./admin.sh verify       Check vault health and integrity
#   ./admin.sh permissions  Output OS-level permission commands for the vault
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
# Detect Python command (python3, python, or py -3)
# ----------------------------------------------------------
PYTHON_CMD=""
detect_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        if python -c "import sys; sys.exit(0 if sys.version_info[0] >= 3 else 1)" 2>/dev/null; then
            PYTHON_CMD="python"
        fi
    elif command -v py &> /dev/null; then
        if py -3 -c "print('ok')" &> /dev/null; then
            PYTHON_CMD="py -3"
        fi
    fi

    if [ -z "$PYTHON_CMD" ]; then
        # Fallback to Node.js
        if command -v node &> /dev/null; then
            PYTHON_CMD=""
            NODE_CMD="node"
        else
            echo -e "${RED}ERROR: Python 3 or Node.js is required for roster management.${NC}"
            echo "Install Python from https://python.org or Node.js from https://nodejs.org"
            exit 1
        fi
    fi
}

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

validate_emp_id() {
    local id="$1"
    if ! echo "$id" | grep -qE '^emp_[0-9]{3,}$'; then
        echo -e "${YELLOW}  Warning: Employee ID '$id' doesn't match expected format (emp_001, emp_002, etc.)${NC}"
        read -p "  Continue anyway? (y/N): " FORCE
        if [ "$FORCE" != "y" ] && [ "$FORCE" != "Y" ]; then
            echo "  Aborted."
            exit 1
        fi
    fi
}

# Run a Python or Node script for JSON manipulation
run_json_script() {
    local py_script="$1"
    local node_script="$2"

    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "$py_script"
    elif [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "$node_script"
    else
        echo -e "${RED}ERROR: No JSON processor available.${NC}"
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
    mkdir -p "$VAULT_PATH/AUDIT/SECURITY"
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

    # Create empty index
    if [ ! -f "$VAULT_PATH/_index.jsonl" ]; then
        touch "$VAULT_PATH/_index.jsonl"
        echo -e "  ${GREEN}✓${NC} Knowledge index created"
    fi

    echo ""
    echo -e "${GREEN}Vault initialized. Now run './admin.sh add' to add employees.${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT — Set folder permissions on the vault.${NC}"
    echo "Run './admin.sh permissions' to see the recommended commands."
}

cmd_add() {
    detect_python
    ensure_roster
    echo -e "${BLUE}Add employee to roster${NC}"
    echo ""

    read -p "  Employee ID (e.g., emp_001): " EMP_ID
    validate_emp_id "$EMP_ID"

    # Check if already exists (using args, not string interpolation)
    EXISTS_CHECK=""
    if [ -n "$PYTHON_CMD" ]; then
        EXISTS_CHECK=$($PYTHON_CMD -c "
import json, sys
with open(sys.argv[1]) as f:
    r = json.load(f)
print('EXISTS' if sys.argv[2] in r.get('employees', {}) else 'OK')
" "$ROSTER_FILE" "$EMP_ID" 2>/dev/null)
    elif [ -n "$NODE_CMD" ]; then
        EXISTS_CHECK=$($NODE_CMD -e "
const fs = require('fs');
const r = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));
console.log(r.employees && r.employees[process.argv[3]] ? 'EXISTS' : 'OK');
" "$ROSTER_FILE" "$EMP_ID" 2>/dev/null)
    fi
    if [ "$EXISTS_CHECK" = "EXISTS" ]; then
        echo -e "${YELLOW}  Employee '$EMP_ID' already exists. Use './admin.sh update' instead.${NC}"
        exit 1
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

    # Use command-line arguments (not string interpolation) to safely handle special characters
    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, sys
from datetime import datetime
roster_file, emp_id, emp_name, emp_email, emp_dept, emp_role, clearance = sys.argv[1:8]
with open(roster_file, 'r') as f:
    roster = json.load(f)
roster['employees'][emp_id] = {
    'name': emp_name, 'email': emp_email, 'department': emp_dept,
    'role': emp_role, 'clearance': clearance, 'active': True,
    'added_at': datetime.utcnow().isoformat() + 'Z'
}
roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'
roster['updated_by'] = 'admin'
with open(roster_file, 'w') as f:
    json.dump(roster, f, indent=2)
" "$ROSTER_FILE" "$EMP_ID" "$EMP_NAME" "$EMP_EMAIL" "$EMP_DEPT" "$EMP_ROLE" "$CLEARANCE"
    elif [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "
const fs = require('fs');
const [,, rosterFile, empId, empName, empEmail, empDept, empRole, clearance] = process.argv;
const roster = JSON.parse(fs.readFileSync(rosterFile, 'utf-8'));
roster.employees[empId] = {
    name: empName, email: empEmail, department: empDept,
    role: empRole, clearance: clearance, active: true,
    added_at: new Date().toISOString()
};
roster.updated_at = new Date().toISOString();
roster.updated_by = 'admin';
fs.writeFileSync(rosterFile, JSON.stringify(roster, null, 2));
" "$ROSTER_FILE" "$EMP_ID" "$EMP_NAME" "$EMP_EMAIL" "$EMP_DEPT" "$EMP_ROLE" "$CLEARANCE"
    fi
    echo -e "  ${GREEN}✓${NC} Added $EMP_NAME ($EMP_ID) to roster"
}

cmd_list() {
    detect_python
    ensure_roster
    echo -e "${BLUE}Employee Roster${NC}"
    echo ""

    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, sys
with open(sys.argv[1], 'r') as f:
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
" "$ROSTER_FILE"
    elif [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "
const fs = require('fs');
const roster = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));
const emps = roster.employees || {};
const keys = Object.keys(emps);
if (keys.length === 0) { console.log('  No employees in roster.'); process.exit(0); }
console.log('  ' + 'ID'.padEnd(14) + 'Name'.padEnd(20) + 'Role'.padEnd(18) + 'Dept'.padEnd(14) + 'Clearance'.padEnd(14) + 'Active');
console.log('  ' + '-'.repeat(13) + ' ' + '-'.repeat(19) + ' ' + '-'.repeat(17) + ' ' + '-'.repeat(13) + ' ' + '-'.repeat(13) + ' ' + '-'.repeat(6));
for (const eid of keys) {
    const e = emps[eid];
    const active = e.active !== false ? 'Yes' : 'NO';
    console.log('  ' + eid.padEnd(14) + e.name.padEnd(20) + e.role.padEnd(18) + e.department.padEnd(14) + e.clearance.padEnd(14) + active);
}
console.log('\n  Total: ' + keys.length + ' employees');
" "$ROSTER_FILE"
    fi
}

cmd_update() {
    detect_python
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

    # Use command-line arguments to safely handle special characters
    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, sys
from datetime import datetime
roster_file, emp_id, new_role, new_dept = sys.argv[1:5]
with open(roster_file, 'r') as f:
    roster = json.load(f)
if emp_id not in roster['employees']:
    print(f'  ERROR: Employee {emp_id} not found in roster.')
    sys.exit(1)
emp = roster['employees'][emp_id]
role_map = {'viewer':'public','engineer':'internal','senior_engineer':'internal','designer':'internal','product_manager':'confidential','hr_manager':'confidential','finance_manager':'confidential','director':'confidential','executive':'restricted'}
if new_role:
    emp['role'] = new_role
    emp['clearance'] = role_map.get(new_role, emp.get('clearance', 'internal'))
if new_dept:
    emp['department'] = new_dept
roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'
roster['updated_by'] = 'admin'
with open(roster_file, 'w') as f:
    json.dump(roster, f, indent=2)
print(f\"  Updated {emp['name']}: role={emp['role']}, dept={emp['department']}, clearance={emp['clearance']}\")
" "$ROSTER_FILE" "$EMP_ID" "$NEW_ROLE" "$NEW_DEPT"
    elif [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "
const fs = require('fs');
const [,, rosterFile, empId, newRole, newDept] = process.argv;
const roster = JSON.parse(fs.readFileSync(rosterFile, 'utf-8'));
if (!roster.employees[empId]) { console.log('  ERROR: Employee ' + empId + ' not found.'); process.exit(1); }
const emp = roster.employees[empId];
const roleMap = {viewer:'public',engineer:'internal',senior_engineer:'internal',designer:'internal',product_manager:'confidential',hr_manager:'confidential',finance_manager:'confidential',director:'confidential',executive:'restricted'};
if (newRole) { emp.role = newRole; emp.clearance = roleMap[newRole] || emp.clearance || 'internal'; }
if (newDept) { emp.department = newDept; }
roster.updated_at = new Date().toISOString();
roster.updated_by = 'admin';
fs.writeFileSync(rosterFile, JSON.stringify(roster, null, 2));
console.log('  Updated ' + emp.name + ': role=' + emp.role + ', dept=' + emp.department + ', clearance=' + emp.clearance);
" "$ROSTER_FILE" "$EMP_ID" "$NEW_ROLE" "$NEW_DEPT"
    fi
    echo -e "  ${GREEN}✓${NC} Roster updated. Employee will see the change on next session."
}

cmd_remove() {
    detect_python
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

    if [ -n "$PYTHON_CMD" ]; then
        $PYTHON_CMD -c "
import json, sys
from datetime import datetime
roster_file, emp_id = sys.argv[1:3]
with open(roster_file, 'r') as f:
    roster = json.load(f)
if emp_id not in roster['employees']:
    print(f'  ERROR: Employee {emp_id} not found.')
    sys.exit(1)
roster['employees'][emp_id]['active'] = False
roster['updated_at'] = datetime.utcnow().isoformat() + 'Z'
with open(roster_file, 'w') as f:
    json.dump(roster, f, indent=2)
print(f\"  Deactivated {roster['employees'][emp_id]['name']}. Their AI sessions will be blocked.\")
" "$ROSTER_FILE" "$EMP_ID"
    elif [ -n "$NODE_CMD" ]; then
        $NODE_CMD -e "
const fs = require('fs');
const [,, rosterFile, empId] = process.argv;
const roster = JSON.parse(fs.readFileSync(rosterFile, 'utf-8'));
if (!roster.employees[empId]) { console.log('  ERROR: Employee ' + empId + ' not found.'); process.exit(1); }
roster.employees[empId].active = false;
roster.updated_at = new Date().toISOString();
fs.writeFileSync(rosterFile, JSON.stringify(roster, null, 2));
console.log('  Deactivated ' + roster.employees[empId].name + '. Their AI sessions will be blocked.');
" "$ROSTER_FILE" "$EMP_ID"
    fi
    echo -e "  ${GREEN}✓${NC} Employee deactivated"
}

cmd_verify() {
    echo -e "${BLUE}Vault Health Check${NC}"
    echo ""
    ERRORS=0
    WARNINGS=0

    # Check vault path
    if [ -d "$VAULT_PATH" ]; then
        echo -e "  ${GREEN}✓${NC} Vault directory exists at $VAULT_PATH"
    else
        echo -e "  ${RED}✗${NC} Vault directory not found at $VAULT_PATH"
        ERRORS=$((ERRORS + 1))
    fi

    # Check required directories
    for dir in PUBLIC INTERNAL CONFIDENTIAL RESTRICTED AUDIT .admin; do
        if [ -d "$VAULT_PATH/$dir" ]; then
            echo -e "  ${GREEN}✓${NC} $dir/ exists"
        else
            echo -e "  ${RED}✗${NC} $dir/ missing"
            ERRORS=$((ERRORS + 1))
        fi
    done

    # Check roster
    if [ -f "$ROSTER_FILE" ]; then
        echo -e "  ${GREEN}✓${NC} roster.json exists"

        # Validate JSON
        if [ -n "$PYTHON_CMD" ]; then
            if $PYTHON_CMD -c "import json, sys; json.load(open(sys.argv[1]))" "$ROSTER_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} roster.json is valid JSON"

                # Count employees
                COUNT=$($PYTHON_CMD -c "import json, sys; r=json.load(open(sys.argv[1])); print(len(r.get('employees',{})))" "$ROSTER_FILE")
                ACTIVE=$($PYTHON_CMD -c "import json, sys; r=json.load(open(sys.argv[1])); print(sum(1 for e in r.get('employees',{}).values() if e.get('active',True)))" "$ROSTER_FILE")
                echo -e "  ${GREEN}✓${NC} $COUNT employees registered ($ACTIVE active)"
            else
                echo -e "  ${RED}✗${NC} roster.json is invalid JSON"
                ERRORS=$((ERRORS + 1))
            fi
        elif [ -n "$NODE_CMD" ]; then
            if $NODE_CMD -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf-8'))" "$ROSTER_FILE" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} roster.json is valid JSON"
            else
                echo -e "  ${RED}✗${NC} roster.json is invalid JSON"
                ERRORS=$((ERRORS + 1))
            fi
        fi
    else
        echo -e "  ${RED}✗${NC} roster.json missing — run './admin.sh init'"
        ERRORS=$((ERRORS + 1))
    fi

    # Check index
    if [ -f "$VAULT_PATH/_index.jsonl" ]; then
        ENTRIES=$(wc -l < "$VAULT_PATH/_index.jsonl" | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} _index.jsonl exists ($ENTRIES entries)"
    else
        echo -e "  ${YELLOW}!${NC} _index.jsonl not found (will be created on first knowledge ingestion)"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check audit log size
    if [ -d "$VAULT_PATH/AUDIT" ]; then
        AUDIT_SIZE=$(du -sh "$VAULT_PATH/AUDIT" 2>/dev/null | cut -f1)
        echo -e "  ${GREEN}✓${NC} AUDIT/ size: $AUDIT_SIZE"
    fi

    # Check .vault-path config
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${GREEN}✓${NC} .vault-path config exists"
    else
        echo -e "  ${YELLOW}!${NC} .vault-path not saved — run './admin.sh init'"
        WARNINGS=$((WARNINGS + 1))
    fi

    echo ""
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "  ${GREEN}All checks passed.${NC}"
    elif [ $ERRORS -eq 0 ]; then
        echo -e "  ${YELLOW}$WARNINGS warning(s), no errors.${NC}"
    else
        echo -e "  ${RED}$ERRORS error(s), $WARNINGS warning(s).${NC}"
    fi
}

cmd_permissions() {
    echo -e "${BLUE}Recommended Vault Permissions${NC}"
    echo ""
    echo "  Apply these permissions to your vault at: $VAULT_PATH"
    echo ""

    # Detect OS
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || command -v icacls &>/dev/null; then
        echo -e "  ${YELLOW}Windows (icacls) commands:${NC}"
        echo ""
        echo "  # Everyone: read-only on admin directory"
        echo "  icacls \"$VAULT_PATH\\.admin\" /grant:r \"Everyone:(OI)(CI)(R)\" /T"
        echo ""
        echo "  # Everyone: full control on PUBLIC and INTERNAL"
        echo "  icacls \"$VAULT_PATH\\PUBLIC\" /grant \"Everyone:(OI)(CI)(F)\" /T"
        echo "  icacls \"$VAULT_PATH\\INTERNAL\" /grant \"Everyone:(OI)(CI)(F)\" /T"
        echo ""
        echo "  # Managers group: full control on CONFIDENTIAL"
        echo "  icacls \"$VAULT_PATH\\CONFIDENTIAL\" /grant \"Managers:(OI)(CI)(F)\" /T"
        echo "  icacls \"$VAULT_PATH\\CONFIDENTIAL\" /remove \"Everyone\" /T"
        echo ""
        echo "  # Executives group: full control on RESTRICTED"
        echo "  icacls \"$VAULT_PATH\\RESTRICTED\" /grant \"Executives:(OI)(CI)(F)\" /T"
        echo "  icacls \"$VAULT_PATH\\RESTRICTED\" /remove \"Everyone\" /T"
        echo ""
        echo "  # Everyone: write (append) on AUDIT"
        echo "  icacls \"$VAULT_PATH\\AUDIT\" /grant \"Everyone:(OI)(CI)(W)\" /T"
        echo ""
        echo -e "  ${YELLOW}NOTE:${NC} Replace 'Managers' and 'Executives' with your actual AD groups."
        echo "  These commands require admin rights on the file server."
    else
        echo -e "  ${YELLOW}Unix (chmod/setfacl) commands:${NC}"
        echo ""
        echo "  # Everyone: read-only on admin directory"
        echo "  chmod 755 \"$VAULT_PATH/.admin\""
        echo "  chmod 644 \"$VAULT_PATH/.admin/roster.json\""
        echo ""
        echo "  # Everyone: full access on PUBLIC and INTERNAL"
        echo "  chmod -R 777 \"$VAULT_PATH/PUBLIC\""
        echo "  chmod -R 777 \"$VAULT_PATH/INTERNAL\""
        echo ""
        echo "  # Restricted groups (using setfacl if available)"
        echo "  chmod -R 770 \"$VAULT_PATH/CONFIDENTIAL\""
        echo "  setfacl -R -m g:managers:rwx \"$VAULT_PATH/CONFIDENTIAL\""
        echo ""
        echo "  chmod -R 770 \"$VAULT_PATH/RESTRICTED\""
        echo "  setfacl -R -m g:executives:rwx \"$VAULT_PATH/RESTRICTED\""
        echo ""
        echo "  # Append-only AUDIT"
        echo "  chmod -R 733 \"$VAULT_PATH/AUDIT\""
    fi
    echo ""
}

# ----------------------------------------------------------
# Main
# ----------------------------------------------------------
detect_python

case "${1:-}" in
    init)        cmd_init ;;
    add)         cmd_add ;;
    list)        cmd_list ;;
    update)      cmd_update ;;
    remove)      cmd_remove ;;
    verify)      cmd_verify ;;
    permissions) cmd_permissions ;;
    *)
        echo "Athena — Admin Tool"
        echo ""
        echo "Usage: ./admin.sh <command>"
        echo ""
        echo "Commands:"
        echo "  init         Initialise vault directories and empty roster"
        echo "  add          Add a new employee to the roster"
        echo "  list         List all employees and their roles"
        echo "  update       Change an employee's role or department"
        echo "  remove       Deactivate an employee"
        echo "  verify       Check vault health and integrity"
        echo "  permissions  Show recommended OS-level permission commands"
        echo ""
        echo "Vault path: $VAULT_PATH"
        echo "Set VAULT_PATH env var to override."
        ;;
esac
