#!/usr/bin/env bun
/**
 * IntegrityCheck.hook.ts - Validate Employee Identity Against Admin Roster (SessionStart)
 *
 * PURPOSE:
 * Validates that the employee's local employee.json has role/department/clearance
 * values that match the admin-controlled roster on the network drive.
 * Employees can freely edit their name and email, but role, department, and
 * clearance MUST match the roster. Mismatches are auto-corrected.
 *
 * TRIGGER: SessionStart (runs before VaultContext)
 *
 * OUTPUT:
 * - On success: { "message": "<system-reminder>...</system-reminder>" } with employee context
 * - On mismatch: Auto-syncs employee.json, then confirms identity
 * - On missing roster: Allows session with warning
 * - On inactive employee: Blocks session via exit(2)
 */

import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import { readStdin } from './lib/stdin';

const HOME = process.env.HOME || process.env.USERPROFILE || '';
const EMPLOYEE_PATH = join(HOME, '.claude', 'employee.json');
const VAULT_PATH = process.env.VAULT_PATH || '';
const ROSTER_PATH = VAULT_PATH ? join(VAULT_PATH, '.admin', 'roster.json') : '';

interface RosterEmployee {
  name: string;
  email: string;
  department: string;
  role: string;
  clearance: string;
  active: boolean;
  added_at?: string;
}

interface Roster {
  version: string;
  employees: Record<string, RosterEmployee>;
}

interface LocalEmployee {
  employee_id: string;
  name: string;
  email: string;
  department: string;
  role: string;
  clearance: string;
}

async function main() {
  // Consume stdin (required by hook protocol)
  await readStdin();

  // Load local employee.json
  if (!existsSync(EMPLOYEE_PATH)) {
    console.error('[IntegrityCheck] No employee.json found. Run setup.sh first.');
    console.log(JSON.stringify({
      message: '<system-reminder>WARNING: No employee identity configured. Run setup.sh to set up your employee profile. Operating in public/read-only mode.</system-reminder>'
    }));
    process.exit(0);
  }

  let local: LocalEmployee;
  try {
    local = JSON.parse(readFileSync(EMPLOYEE_PATH, 'utf-8'));
  } catch {
    console.error('[IntegrityCheck] Failed to parse employee.json');
    process.exit(2);
  }

  // Load admin roster
  if (!ROSTER_PATH || !existsSync(ROSTER_PATH)) {
    console.error('[IntegrityCheck] No admin roster found. Skipping integrity check.');
    console.log(JSON.stringify({
      message: '<system-reminder>NOTE: No admin roster found. Employee permissions are based on local employee.json only. Contact your admin to set up the roster.</system-reminder>'
    }));
    process.exit(0);
  }

  let roster: Roster;
  try {
    roster = JSON.parse(readFileSync(ROSTER_PATH, 'utf-8'));
  } catch {
    console.error('[IntegrityCheck] Failed to parse roster.json');
    process.exit(0); // Don't block on corrupt roster — fail open with local values
  }

  // Look up employee in roster
  const rosterEntry = roster.employees[local.employee_id];

  if (!rosterEntry) {
    console.error(`[IntegrityCheck] Employee '${local.employee_id}' not found in admin roster.`);
    console.log(JSON.stringify({
      message: `<system-reminder>ACCESS DENIED: Your employee ID "${local.employee_id}" is not registered in the admin roster. Contact your admin to be added. Operating in public/read-only mode until registered.</system-reminder>`
    }));
    // Override local clearance to public for safety
    local.clearance = 'public';
    local.role = 'viewer';
    try {
      writeFileSync(EMPLOYEE_PATH, JSON.stringify(local, null, 2) + '\n');
    } catch {
      // Best-effort update
    }
    process.exit(0);
  }

  // Check if employee is active
  if (rosterEntry.active === false) {
    console.error(`[IntegrityCheck] Employee '${local.employee_id}' is deactivated.`);
    console.error('Contact your admin if this is an error.');
    process.exit(2);
  }

  // Check for mismatches in admin-controlled fields and auto-sync
  const mismatches: string[] = [];
  let needsUpdate = false;

  if (local.role !== rosterEntry.role) {
    mismatches.push(`role: "${local.role}" → "${rosterEntry.role}"`);
    needsUpdate = true;
  }
  if (local.department !== rosterEntry.department) {
    mismatches.push(`department: "${local.department}" → "${rosterEntry.department}"`);
    needsUpdate = true;
  }
  if (local.clearance !== rosterEntry.clearance) {
    mismatches.push(`clearance: "${local.clearance}" → "${rosterEntry.clearance}"`);
    needsUpdate = true;
  }

  if (needsUpdate) {
    console.error(`[IntegrityCheck] Syncing employee.json with admin roster: ${mismatches.join(', ')}`);

    local.role = rosterEntry.role;
    local.department = rosterEntry.department;
    local.clearance = rosterEntry.clearance;

    try {
      writeFileSync(EMPLOYEE_PATH, JSON.stringify(local, null, 2) + '\n');
      console.error('[IntegrityCheck] employee.json updated to match roster.');
    } catch (err) {
      console.error(`[IntegrityCheck] Failed to update employee.json: ${err}`);
    }
  }

  // Success
  console.log(JSON.stringify({
    message: `<system-reminder>IDENTITY VERIFIED: ${local.name} (${rosterEntry.role}, ${rosterEntry.department}, clearance: ${rosterEntry.clearance}). Identity matches admin roster.</system-reminder>`
  }));
  process.exit(0);
}

main().catch((err) => {
  console.error(`[IntegrityCheck] Unexpected error: ${err}`);
  process.exit(0);
});
