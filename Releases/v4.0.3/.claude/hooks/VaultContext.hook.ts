#!/usr/bin/env bun
/**
 * VaultContext.hook.ts - Load Company Knowledge at Session Start (SessionStart)
 *
 * PURPOSE:
 * At session start, loads relevant company knowledge from the shared memory vault
 * based on the employee's role and clearance level. Injects a system reminder
 * so Claude is immediately aware of company context.
 *
 * TRIGGER: SessionStart
 *
 * OUTPUT:
 * - stdout: JSON with "message" field containing company knowledge context
 *
 * DESIGN:
 * Reads the _index.jsonl file, filters entries by employee clearance and
 * department access, then loads the most recent relevant summaries.
 */

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import {
  getEmployee,
  getVaultPath,
  hasClearance,
  canAccessDepartment,
  type ClearanceLevel,
} from './lib/employee';

interface IndexEntry {
  id: string;
  classification: ClearanceLevel;
  department: string;
  contributor_name: string;
  created: string;
  tags: string[];
  summary: string;
  file_path: string;
}

async function main() {
  // Consume stdin (required by hook protocol even if unused)
  let inputData = '';
  for await (const chunk of Bun.stdin.stream()) {
    inputData += new TextDecoder().decode(chunk);
  }

  const employee = getEmployee();
  const vaultPath = getVaultPath();
  const indexPath = join(vaultPath, '_index.jsonl');

  if (!existsSync(indexPath)) {
    // No knowledge yet — output employee context only
    const message = `<system-reminder>COMPANY AI CONTEXT:
Employee: ${employee.name} (${employee.role}, ${employee.department})
Clearance: ${employee.clearance}

The shared company knowledge vault is at ${vaultPath}. No knowledge entries exist yet.
As you learn company-specific information during this conversation, it will be automatically captured for future reference.

IMPORTANT: Respect access control. Never reveal information above this employee's "${employee.clearance}" clearance level.</system-reminder>`;

    console.log(JSON.stringify({ message }));
    process.exit(0);
  }

  // Read and parse the index
  let entries: IndexEntry[] = [];
  try {
    const indexContent = readFileSync(indexPath, 'utf-8');
    entries = indexContent
      .trim()
      .split('\n')
      .filter(line => line.trim())
      .map(line => JSON.parse(line));
  } catch (err) {
    console.error(`[VaultContext] Failed to read index: ${err}`);
    process.exit(0);
  }

  // Filter entries by employee clearance and department access
  const accessibleEntries = entries.filter(entry => {
    const clearanceOk = hasClearance(employee.clearance, entry.classification);
    const deptOk = canAccessDepartment(employee, entry.department) ||
      entry.department === 'company-wide' ||
      entry.department === 'processes' ||
      entry.department === 'onboarding' ||
      entry.department === 'tools';
    return clearanceOk && deptOk;
  });

  // Take the most recent 30 entries (sorted by created date)
  const recentEntries = accessibleEntries
    .sort((a, b) => new Date(b.created).getTime() - new Date(a.created).getTime())
    .slice(0, 30);

  if (recentEntries.length === 0) {
    const message = `<system-reminder>COMPANY AI CONTEXT:
Employee: ${employee.name} (${employee.role}, ${employee.department})
Clearance: ${employee.clearance}

The shared company knowledge vault is at ${vaultPath}. No accessible knowledge entries found for your role.
As you learn company-specific information during this conversation, it will be automatically captured.

IMPORTANT: Respect access control. Never reveal information above this employee's "${employee.clearance}" clearance level.</system-reminder>`;

    console.log(JSON.stringify({ message }));
    process.exit(0);
  }

  // Build the knowledge summary
  const knowledgeSummaries = recentEntries.map(entry => {
    const date = new Date(entry.created).toLocaleDateString();
    return `- [${entry.department}] ${entry.summary} (by ${entry.contributor_name}, ${date}) [${entry.tags.join(', ')}]`;
  }).join('\n');

  const message = `<system-reminder>COMPANY AI CONTEXT:
Employee: ${employee.name} (${employee.role}, ${employee.department})
Clearance: ${employee.clearance}
Knowledge Vault: ${vaultPath}

## Recent Company Knowledge (${recentEntries.length} entries accessible to you):
${knowledgeSummaries}

## Instructions:
- You have access to the company knowledge vault at ${vaultPath}
- Use Read tool to access full knowledge files when needed
- New company knowledge shared in this conversation will be automatically captured
- IMPORTANT: Never reveal information above "${employee.clearance}" clearance level
- If asked about restricted topics, politely decline and direct to the appropriate team</system-reminder>`;

  console.log(JSON.stringify({ message }));
  process.exit(0);
}

main().catch(() => {
  process.exit(0);
});
