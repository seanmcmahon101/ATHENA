# Business AI Infrastructure

### Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

Inspired by [PAI](https://github.com/danielmiessler/Personal_AI_Infrastructure.git), by Daniel Miessler.

> Amplifying your team's collective intelligence — empowering employees with advanced AI-driven business knowledge management, not replacing them.

<img width="2816" height="1536" alt="workflow" src="https://github.com/user-attachments/assets/4e70bc1b-4da3-439f-b411-13a8c139c6c6" />

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
- [Bun](https://bun.sh) runtime installed on each employee machine

### Admin Setup (Once)

1. **Clone the repo and initialise the vault:**
   ```bash
   git clone <repo-url>
   cd Business_AI_Infrastructure
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
   ```

The roster lives in the vault at `.admin/roster.json` and is the **source of truth** for roles and clearance. Employees cannot change their own permissions.

### Employee Setup

1. **Clone the repo:**
   ```bash
   git clone <repo-url>
   cd Business_AI_Infrastructure
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

```
Employee A (Engineer)          Employee B (HR Manager)
     |                              |
     v                              v
 Claude Code                   Claude Code
 (~/.claude/employee.json)      (~/.claude/employee.json)
     |                              |
     |-- PromptGuard (topic check)  |-- PromptGuard (topic check)
     |-- AccessControl (file check) |-- AccessControl (file check)
     |                              |
     v                              v
          Memory Vault (Shared Storage)
          |-- PUBLIC/          <-- everyone
          |-- INTERNAL/        <-- all employees
          |-- CONFIDENTIAL/    <-- managers + execs
          |-- RESTRICTED/      <-- execs + HR only
          |-- AUDIT/           <-- access logs
          +-- _index.jsonl     <-- knowledge index
```

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `IntegrityCheck.hook.ts` | SessionStart | Validates employee identity against admin roster, auto-syncs role/clearance |
| `VaultContext.hook.ts` | SessionStart | Loads relevant company knowledge at session start |
| `SecurityValidator.hook.ts` | PreToolUse (Bash/Edit/Write/Read) | Blocks dangerous system operations |
| `AccessControl.hook.ts` | PreToolUse (Read) | Enforces clearance-based access to vault files |
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
2.  Clone this repo                   ->  git clone <repo-url> && cd Business_AI_Infrastructure
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
4.  Clone the repo                    ->  git clone <repo-url> && cd Business_AI_Infrastructure
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

## License

MIT
