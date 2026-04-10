#!/usr/bin/env bun
/**
 * AccessControl.hook.ts - Role-Based Access Control for Memory Vault (PreToolUse)
 *
 * PURPOSE:
 * Intercepts Read, Write, and Edit operations on the shared memory vault.
 * Checks the employee's clearance level and department access against the
 * requested file's classification. Hard blocks unauthorized access.
 *
 * TRIGGER: PreToolUse (matcher: Read, Write, Edit)
 *
 * INPUT:
 * - tool_name: "Read" | "Write" | "Edit"
 * - tool_input: { file_path: string }
 *
 * OUTPUT:
 * - exit(0) + { "continue": true } → Access allowed
 * - exit(2) → Access denied (hard block)
 *
 * SIDE EFFECTS:
 * - Appends to: VAULT_PATH/AUDIT/YYYY-MM/access-log.jsonl
 */

import { appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { readStdinJSON } from './lib/stdin';
import {
  getEmployee,
  getVaultPath,
  getPathClearance,
  hasClearance,
  canAccessDepartment,
  getDepartmentFromPath,
} from './lib/employee';

interface HookInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
  session_id?: string;
}

interface AuditEntry {
  timestamp: string;
  employee_id: string;
  employee_name: string;
  role: string;
  action: 'read' | 'write';
  target: string;
  classification: string;
  department: string | null;
  decision: 'allowed' | 'blocked';
  reason: string;
  session_id: string;
}

function logAudit(entry: AuditEntry): void {
  try {
    const vaultPath = getVaultPath();
    if (!vaultPath) return;

    const now = new Date();
    const yearMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    const auditDir = join(vaultPath, 'AUDIT', yearMonth);

    if (!existsSync(auditDir)) {
      mkdirSync(auditDir, { recursive: true });
    }

    const logFile = join(auditDir, 'access-log.jsonl');
    appendFileSync(logFile, JSON.stringify(entry) + '\n');
  } catch {
    // Audit logging should never block operations
  }
}

async function main() {
  const input = await readStdinJSON<HookInput>();

  if (!input) {
    console.log(JSON.stringify({ continue: true }));
    process.exit(0);
  }

  const filePath = input.tool_input?.file_path;
  if (!filePath) {
    console.log(JSON.stringify({ continue: true }));
    process.exit(0);
  }

  // Only check files within the vault
  const vaultPath = getVaultPath();
  if (!vaultPath) {
    console.log(JSON.stringify({ continue: true }));
    process.exit(0);
  }

  const normalizedPath = filePath.replace(/\\/g, '/');
  const normalizedVault = vaultPath.replace(/\\/g, '/');

  if (!normalizedPath.startsWith(normalizedVault)) {
    // Not a vault file — allow
    console.log(JSON.stringify({ continue: true }));
    process.exit(0);
  }

  const employee = getEmployee();
  const requiredClearance = getPathClearance(filePath);
  const department = getDepartmentFromPath(filePath);
  const isWrite = input.tool_name === 'Write' || input.tool_name === 'Edit' || input.tool_name === 'MultiEdit';
  const action: 'read' | 'write' = isWrite ? 'write' : 'read';

  if (!requiredClearance) {
    console.log(JSON.stringify({ continue: true }));
    process.exit(0);
  }

  // Check clearance level
  const clearanceOk = hasClearance(employee.clearance, requiredClearance);

  // Check department access (only for INTERNAL and CONFIDENTIAL directories)
  let departmentOk = true;
  if (department && department !== 'projects' && department !== 'processes' && department !== 'onboarding' && department !== 'tools') {
    departmentOk = canAccessDepartment(employee, department);
  }

  // For writes, additionally block writing to .admin/ unless super_admin
  let adminWriteOk = true;
  const relativePath = normalizedPath.slice(normalizedVault.length + 1);
  if (isWrite && relativePath.startsWith('.admin')) {
    adminWriteOk = employee.clearance === 'super_admin';
  }

  const allowed = clearanceOk && departmentOk && adminWriteOk;

  // Log the access attempt
  logAudit({
    timestamp: new Date().toISOString(),
    employee_id: employee.employee_id,
    employee_name: employee.name,
    role: employee.role,
    action,
    target: normalizedPath.replace(normalizedVault, ''),
    classification: requiredClearance,
    department,
    decision: allowed ? 'allowed' : 'blocked',
    reason: !clearanceOk
      ? `clearance_insufficient: has ${employee.clearance}, needs ${requiredClearance}`
      : !departmentOk
        ? `department_access_denied: ${department} not visible to ${employee.role}`
        : !adminWriteOk
          ? `admin_directory_write_denied: only admins can write to .admin/`
          : 'authorized',
    session_id: input.session_id || 'unknown',
  });

  if (!allowed) {
    const reason = !clearanceOk
      ? `Your role (${employee.role}) has "${employee.clearance}" clearance but this file requires "${requiredClearance}" clearance.`
      : !departmentOk
        ? `Your role (${employee.role}) does not have access to the "${department}" department.`
        : `Only super_admin users can write to the .admin/ directory.`;

    console.error(`ACCESS DENIED: ${reason} Contact your manager if you need access.`);
    process.exit(2);
  }

  console.log(JSON.stringify({ continue: true }));
  process.exit(0);
}

main().catch(() => {
  console.log(JSON.stringify({ continue: true }));
  process.exit(0);
});
