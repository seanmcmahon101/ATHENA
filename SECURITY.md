# Security Model

## Access Control

This system uses a **defence-in-depth** approach to protect sensitive company information across four layers:

### Layer 1: Prompt Guard (UserPromptSubmit)
- Scans employee prompts for restricted topic keywords before the AI processes them
- Injects system reminders instructing the AI assistant to decline unauthorised requests
- Logs blocked attempts to the audit trail for review

### Layer 2: Access Control (PreToolUse - Read)
- Intercepts all file reads targeting the memory vault
- Checks employee clearance against the file's classification level
- Hard blocks (exit code 2) unauthorised access — the AI assistant never sees the content

### Layer 3: Security Validator (PreToolUse - Bash/Edit/Write/Read)
- Blocks dangerous system operations (e.g. `rm -rf`, disk formatting)
- Protects configuration files from modification
- Logs all security events to the audit trail

### Layer 4: Classification Enforcement
- Knowledge files are automatically classified on ingestion
- Directory structure enforces classification boundaries (PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED)
- Employees can only contribute knowledge at or below their own clearance level

## Audit Trail

All access attempts are logged to `W:\MEMORY\AUDIT\YYYY-MM\access-log.jsonl` with the following fields:

- Employee identity (id, name, role)
- Action (read, write, prompt_blocked, ingested)
- Target file and classification level
- Decision (allowed/blocked) with reason
- Session ID and timestamp

## Threat Mitigations

| Threat | Mitigation |
|--------|-----------|
| Employee edits their own role locally | `employee.json` and `company-roles.json` placed in settings "ask" list; IntegrityCheck overwrites on session start |
| Prompt injection to bypass access control | Hook-level enforcement operates outside the AI assistant's context |
| Direct vault file access | OS-level network drive permissions complement hook-level controls |
| Audit log tampering | `AUDIT/` directory marked as protected in SecurityValidator |
| Unauthorised topic discussion | PromptGuard intercepts before the AI processes the request |

## Admin Roster

The roster at `W:\MEMORY\.admin\roster.json` is the single source of truth for all employee roles and clearance levels.

**Key principle:** The roster must be **readable by all employees** (the IntegrityCheck hook reads it on every session start for identity verification) but **writable only by admins**. It contains role assignments only — seeing that "Jane is an engineer" is not sensitive information.

The IntegrityCheck hook auto-syncs each employee's local `employee.json` with the roster on every session start. Manual edits to role or clearance fields are silently overwritten.

## Required Network Drive Permissions

| Path | Permissions |
|------|-------------|
| `.admin/` | Admin: read + write. Everyone else: read-only |
| `PUBLIC/` | Everyone: read + write |
| `INTERNAL/` | Everyone: read + write |
| `CONFIDENTIAL/` | Managers, execs, HR: read + write. Everyone else: no access |
| `RESTRICTED/` | Execs and HR leads only: read + write. Everyone else: no access |
| `AUDIT/` | Everyone: write (append). Admin: read + write |

On Windows: right-click each folder → Properties → Security tab → configure ACLs per group.

## Recommendations

1. Configure OS-level file permissions as described above — this is the primary security layer
2. Regularly review audit logs (`W:\MEMORY\AUDIT\`) for unusual access patterns
3. Run `./admin.sh update` promptly when employees change roles — sessions auto-sync on next start
4. Run `./admin.sh remove` immediately when an employee departs the organisation
5. Keep `company-roles.json` under version control with a formal change review process
