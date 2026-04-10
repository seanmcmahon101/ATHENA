# Athena
## An AI architechture for self improving business context & intelligence

### Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Inspired by [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure.git), by Daniel Miessler.

> Amplifying your team's collective intelligence — empowering employees with advanced AI-driven business knowledge management, not replacing them.

<img width="2816" height="1536" alt="workflow" src="https://github.com/user-attachments/assets/bc846fca-bf5f-42d5-aafb-681a602c3680" />

## Overview

A hook-based infrastructure that turns Claude Code into a **company-wide knowledge platform**. As your team works, it automatically:

1. **Learns** — Extracts company knowledge from conversations (decisions, processes, architecture, policies)
2. **Remembers** — Stores knowledge in a shared Memory Vault at a location you choose
3. **Shares** — Makes that knowledge available to other authorised employees
4. **Protects** — Enforces role-based access control so employees only see what they're authorised to see

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (CLI, desktop app, or IDE extension)
- A shared storage location for the Memory Vault (network drive, shared folder, or any accessible path)
- [Bun](https://bun.sh) runtime (setup.sh will offer to install to user-space if not found — no admin rights needed)

### Admin Setup (Once)

1. **Clone the repo and initialise the vault:**
   ```bash
   git clone <repo-url>
   cd Athena
   ./admin.sh init          # Creates vault directories + empty roster
   ```

   During init, you'll be prompted to choose where to store the Memory Vault.
   This can be a network drive (`W:\MEMORY`), a shared folder (`/mnt/shared/vault`),
   or any path accessible to your team. The chosen path is saved to `.vault-path`
   so all other scripts and employee setups automatically use it.

2. **Add employees to the roster:**
   ```bash
   ./admin.sh add           # Interactive — prompts for name, role, department
   ./admin.sh list          # View all employees
   ./admin.sh update        # Change someone's role/department
   ./admin.sh remove        # Deactivate an employee
   ./admin.sh verify        # Check vault health and integrity
   ./admin.sh permissions   # Output recommended OS-level permission commands
   ```

The roster lives in the vault at `.admin/roster.json` and is the **source of truth** for roles and clearance. Employees cannot change their own permissions.

### Employee Setup

1. **Clone the repo:**
   ```bash
   git clone <repo-url>
   cd Athena
   ```

2. **Run the setup script:**
   ```bash
   ./setup.sh
   ```
   You'll provide your employee ID (from your admin), name, and email.
   The vault path is auto-detected from the admin's configuration.
   Role and clearance are **automatically synced** from the admin roster on first session.

3. **Start Claude Code** — hooks auto-load and identity is verified against the roster.

> Employees may edit their name and email in `~/.claude/employee.json` at any time. Role, department, and clearance are admin-controlled and cannot be self-modified.

To update after config or hook changes:
```bash
git pull && ./setup.sh
```

## Architecture

<img width="1376" height="768" alt="nano-banana-pro-kn727pnrhybb3z6ycv05v2px7h83w110" src="https://github.com/user-attachments/assets/9fdd4fdc-a826-4bf1-9e1c-1c49faa5733f" />


## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `IntegrityCheck.hook.ts` | SessionStart | Validates employee identity against admin roster, auto-syncs role/clearance |
| `VaultContext.hook.ts` | SessionStart | Loads relevant company knowledge at session start |
| `SecurityValidator.hook.ts` | PreToolUse (Bash/Edit/Write/MultiEdit/Read) | Blocks dangerous system operations |
| `AccessControl.hook.ts` | PreToolUse (Read/Write/Edit/MultiEdit) | Enforces clearance-based access to vault files |
| `PromptGuard.hook.ts` | UserPromptSubmit | Intercepts prompts about restricted topics |
| `KnowledgeIngestion.hook.ts` | Stop | Extracts and stores new company knowledge |

## Roles & Clearance Levels

| Role | Clearance | Departments Visible |
|------|-----------|-------------------|
| `viewer` | public | -- |
| `engineer` | internal | engineering, product |
| `senior_engineer` | internal | engineering, product, design |
| `designer` | internal | design, product |
| `product_manager` | confidential | product, engineering, design |
| `hr_manager` | confidential | hr, company-wide |
| `finance_manager` | confidential | finance, company-wide |
| `director` | confidential | all |
| `executive` | restricted | all |

Roles are defined in `company-roles.json`. Modify to match your organisation's structure.

## Vault Structure

The Memory Vault path is configured during `./admin.sh init` and saved to `.vault-path`.

```
<VAULT_PATH>/
|-- PUBLIC/           # General processes, onboarding, tool docs
|-- INTERNAL/         # Technical decisions, project knowledge
|   |-- engineering/
|   |-- product/
|   |-- design/
|   +-- projects/
|-- CONFIDENTIAL/     # HR policies, financials, strategic plans
|   |-- hr/
|   |-- finance/
|   +-- product/
|-- RESTRICTED/       # Compensation, board strategy, personnel
|   |-- strategy/
|   |-- compensation/
|   +-- personnel/
|-- AUDIT/            # Access logs (who accessed what, when)
|   +-- YYYY-MM/
|       +-- access-log.jsonl
+-- _index.jsonl      # Searchable knowledge index
```

## Security

**Two layers of access control work together:**

### Layer 1: OS-level file permissions

Set these on your vault directory:

| Path | Everyone | Managers/Execs | Execs/HR | Admin only |
|------|----------|----------------|----------|------------|
| `.admin/roster.json` | Read | Read | Read | Read + Write |
| `PUBLIC/` | Read + Write | Read + Write | Read + Write | Read + Write |
| `INTERNAL/` | Read + Write | Read + Write | Read + Write | Read + Write |
| `CONFIDENTIAL/` | No access | Read + Write | Read + Write | Read + Write |
| `RESTRICTED/` | No access | No access | Read + Write | Read + Write |
| `AUDIT/` | Write (append) | Write (append) | Write (append) | Read + Write |

The roster file (`roster.json`) is **readable by everyone** — it only contains role assignments, not secrets. Employees need to read it so the IntegrityCheck hook can verify their identity. Only admins can write to it.

### Layer 2: Hook-level enforcement (defence in depth)

Even if OS permissions aren't set perfectly, hooks provide a second barrier:

- **IntegrityCheck**: Syncs role/clearance from admin roster on every session start — employees cannot escalate privileges by editing their local `employee.json`
- **AccessControl**: Hard blocks unauthorised vault reads at the application level
- **PromptGuard**: Intercepts restricted topic requests before the AI processes them
- **Audit trail**: Every access attempt (allowed and blocked) is logged to `AUDIT/`
- **Anti-prompt-injection**: Access control is enforced by hooks at the system level, not by instructions alone

## Updating

When hooks or roles change:
1. Push updates to the shared repo
2. Employees pull and re-run `./setup.sh`
3. Changes take effect on the next Claude Code session

---

## Deployment Guide

### Admin: First-Time Setup

```
1.  Install Bun                       ->  curl -fsSL https://bun.sh/install | bash
2.  Clone this repo                   ->  git clone <repo-url> && cd Athena
3.  Initialise the vault              ->  ./admin.sh init
                                          Choose your vault location (network drive, shared folder, etc.)
                                          Creates all folders + empty roster + saves path to .vault-path
4.  Add yourself                      ->  ./admin.sh add
                                          Select "executive" or "director" as your role
5.  Add your employees                ->  ./admin.sh add
                                          Repeat for each person and note their employee ID
6.  Set folder permissions            ->  Apply OS-level permissions on the vault:
                                            .admin/          -> everyone: read-only, you: full control
                                            CONFIDENTIAL/    -> managers + execs only
                                            RESTRICTED/      -> execs + HR only
                                            Everything else  -> everyone: full control
7.  Set up your own machine           ->  ./setup.sh
                                          Enter your employee ID, name, and email
8.  Open Claude Code                  ->  It should display "IDENTITY VERIFIED" — setup is complete
```

### Employee: Joining the Platform

```
1.  Install Bun                       ->  curl -fsSL https://bun.sh/install | bash
2.  Obtain your employee ID           ->  Provided by your admin (e.g. emp_001)
3.  Confirm vault access              ->  Check that you can access the vault path your admin provided
4.  Clone the repo                    ->  git clone <repo-url> && cd Athena
5.  Run setup                         ->  ./setup.sh
                                          Enter your employee ID, name, and email
                                          Vault path is auto-detected from admin config
6.  Open Claude Code                  ->  Identity is verified and company knowledge is loaded
```

### Troubleshooting

| Issue | Resolution |
|-------|-----------|
| "No employee.json found" | Run `./setup.sh` |
| "Employee ID not in roster" | Ask your admin to run `./admin.sh add` for you |
| "Employee account inactive" | Contact your admin — account may have been deactivated via `./admin.sh remove` |
| "No admin roster found" | The vault has not been initialised — ask your admin to run `./admin.sh init` |
| "VAULT_PATH is not set" | Run `./setup.sh` to configure your vault location |
| "ACCESS DENIED" on a file | Your clearance level does not permit access to this file. Speak with your manager |
| AI won't discuss salaries or strategy | Your role does not have clearance for that topic. Contact HR or your manager directly |
| Want to update your name or email | Edit `~/.claude/employee.json` directly — those fields are yours to manage |
| Want to change your role | Role changes are admin-controlled. Ask your admin to run `./admin.sh update` |
| Hooks not loading after a repo update | Re-run `./setup.sh` to apply the latest hooks and configuration |

## Testing Guide (No Admin Rights Required)

You can test the full system locally on your own machine — no network drive, no admin rights, no other employees needed. This creates a self-contained vault in a temp folder and simulates multiple roles.

### 1. Set Up a Local Vault

```bash
# Create a temporary vault anywhere you have write access
mkdir -p /tmp/athena-test
cd Athena

# Initialise the vault (enter /tmp/athena-test when prompted for the path)
./admin.sh init
```

### 2. Create Test Employees

Add a few employees with different roles to test access control:

```bash
# Add yourself as an executive (full access)
./admin.sh add
# ID: emp_001, Role: executive, Department: engineering

# Add a simulated engineer (limited access)
./admin.sh add
# ID: emp_002, Role: engineer, Department: engineering

# Add a simulated viewer (public only)
./admin.sh add
# ID: emp_003, Role: viewer, Department: engineering

# Verify the roster
./admin.sh list
./admin.sh verify
```

### 3. Run Setup As Each Role

```bash
# Set up as the executive first
./setup.sh
# Enter emp_001, your name, your email
# Vault path: /tmp/athena-test (or the path you used above)
```

### 4. Test the Hooks

Open Claude Code and verify:

**Identity check** — You should see `IDENTITY VERIFIED: <your name> (executive, engineering, clearance: restricted)` in the session start output.

**Knowledge ingestion** — Tell Claude something like:
> "We decided to use PostgreSQL for our main database. Our architecture uses a microservices pattern with REST APIs."

Then check the vault:
```bash
ls /tmp/athena-test/INTERNAL/engineering/
cat /tmp/athena-test/_index.jsonl
```

You should see a new `.md` file with the extracted knowledge.

**Access control** — Add a test file to a restricted area:
```bash
echo "Board strategy: acquire CompetitorCo" > /tmp/athena-test/RESTRICTED/strategy/board-plan.md
```

Then ask Claude to read it. With executive clearance it should succeed.

**Prompt guard** — Ask Claude about a restricted topic:
> "What are the current salary bands for engineers?"

With executive clearance, this should work. With a lower role, it should be blocked.

### 5. Test As a Lower-Clearance Role

To simulate a different employee, edit your identity file:

```bash
# Back up your current identity
cp ~/.claude/employee.json ~/.claude/employee.json.backup

# Switch to the engineer role
# Edit ~/.claude/employee.json and change employee_id to "emp_002"
```

Then restart Claude Code. The IntegrityCheck hook will auto-sync your role to `engineer` from the roster. Now test:

- **Try reading** `/tmp/athena-test/RESTRICTED/strategy/board-plan.md` — should be **blocked**
- **Try reading** `/tmp/athena-test/INTERNAL/engineering/` files — should **succeed**
- **Ask about salaries** — should be **blocked** by PromptGuard
- **Ask about architecture** — should work and reference vault knowledge

Repeat with `emp_003` (viewer) to test public-only access.

### 6. Test Security Validator

With Claude Code open, try asking it to run dangerous commands:
- `rm -rf /` — should be **hard blocked**
- `git push --force` — should **prompt for confirmation**
- `ls` — should be **allowed** (trusted command)

### 7. Test Knowledge Classification

With an executive role, discuss sensitive topics:
> "Our burn rate is $500k/month and runway is 18 months."

Check where it was stored — it should be classified as CONFIDENTIAL or higher, not INTERNAL, because "burn rate" and "runway" are restricted topic keywords.

### 8. Clean Up

```bash
# Restore your real identity
cp ~/.claude/employee.json.backup ~/.claude/employee.json

# Remove test vault
rm -rf /tmp/athena-test

# Re-run setup to restore your normal config
./setup.sh
```

### Quick Smoke Test Checklist

```
[ ] ./admin.sh init          — vault created, no errors
[ ] ./admin.sh add           — employees added with correct clearance
[ ] ./admin.sh list          — table displays correctly
[ ] ./admin.sh verify        — all checks pass
[ ] ./setup.sh               — completes with 0 errors
[ ] Claude Code starts       — "IDENTITY VERIFIED" message appears
[ ] Knowledge ingestion      — .md file created in vault after sharing decisions
[ ] Access control (read)    — blocked when reading above clearance
[ ] Access control (write)   — blocked when writing above clearance
[ ] Prompt guard             — restricted topics blocked for lower roles
[ ] Security validator       — dangerous commands blocked
[ ] Role switching           — IntegrityCheck auto-syncs from roster
[ ] Deduplication            — same knowledge not ingested twice
```

## License

MIT
