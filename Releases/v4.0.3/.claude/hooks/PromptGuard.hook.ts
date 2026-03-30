#!/usr/bin/env bun
/**
 * PromptGuard.hook.ts - Topic-Based Access Control (UserPromptSubmit)
 *
 * PURPOSE:
 * Scans user prompts for restricted topic keywords before Claude processes them.
 * If the employee's clearance level is insufficient for a detected topic,
 * injects a system reminder telling Claude to decline the request.
 *
 * TRIGGER: UserPromptSubmit
 *
 * INPUT:
 * - user_prompt: string (the raw user message)
 * - session_id: string
 *
 * OUTPUT:
 * - stdout: JSON with optional "message" field containing a system reminder
 * - Blocked topics get a system reminder injected, not a hard block,
 *   so Claude can politely explain why it can't help.
 *
 * SIDE EFFECTS:
 * - Appends to: W:\MEMORY\AUDIT\YYYY-MM\access-log.jsonl
 */

import { appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import {
  getEmployee,
  getCompanyRoles,
  getVaultPath,
  hasClearance,
  type ClearanceLevel,
} from './lib/employee';

interface HookInput {
  user_prompt?: string;
  session_id?: string;
}

function logAudit(entry: Record<string, unknown>): void {
  try {
    const vaultPath = getVaultPath();
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
  let inputData = '';
  for await (const chunk of Bun.stdin.stream()) {
    inputData += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputData);
  } catch {
    process.exit(0);
  }

  const prompt = input.user_prompt;
  if (!prompt) {
    process.exit(0);
  }

  const employee = getEmployee();
  const roles = getCompanyRoles();
  const promptLower = prompt.toLowerCase();

  // Check each restricted topic against the prompt
  const blockedTopics: string[] = [];
  const topicRestrictions = roles.topic_restrictions;

  for (const [keyword, requiredClearance] of Object.entries(topicRestrictions)) {
    if (promptLower.includes(keyword.toLowerCase())) {
      if (!hasClearance(employee.clearance, requiredClearance as ClearanceLevel)) {
        blockedTopics.push(keyword);
      }
    }
  }

  if (blockedTopics.length === 0) {
    // No restricted topics detected — proceed normally
    process.exit(0);
  }

  // Log the blocked attempt
  logAudit({
    timestamp: new Date().toISOString(),
    employee_id: employee.employee_id,
    employee_name: employee.name,
    role: employee.role,
    action: 'prompt_blocked',
    blocked_topics: blockedTopics,
    clearance: employee.clearance,
    decision: 'blocked',
    reason: 'topic_restricted',
    session_id: input.session_id || 'unknown',
  });

  // Inject system reminder telling Claude to decline
  const contactMap: Record<string, string> = {
    salary: 'HR',
    compensation: 'HR',
    equity: 'HR',
    'stock options': 'HR',
    termination: 'HR',
    fired: 'HR',
    layoff: 'HR',
    'performance review': 'your manager',
    'performance improvement plan': 'HR',
    pip: 'HR',
    disciplinary: 'HR',
    'personal data': 'HR',
    medical: 'HR',
    disability: 'HR',
    'financial results': 'Finance',
    revenue: 'Finance',
    profit: 'Finance',
    'burn rate': 'Finance or Leadership',
    runway: 'Finance or Leadership',
    strategy: 'Leadership',
    acquisition: 'Leadership',
    merger: 'Leadership',
    'board meeting': 'Leadership',
    'board minutes': 'Leadership',
    investor: 'Leadership',
    fundraising: 'Leadership',
    valuation: 'Leadership',
  };

  const contacts = [...new Set(blockedTopics.map(t => contactMap[t] || 'your manager'))];

  const message = `<system-reminder>ACCESS CONTROL: The current user (${employee.name}, role: ${employee.role}, clearance: ${employee.clearance}) does not have authorization to discuss the following topics: ${blockedTopics.join(', ')}.

You MUST:
1. Politely decline to provide information about these topics
2. Explain that this information requires higher clearance
3. Suggest they contact ${contacts.join(' or ')} for assistance
4. Do NOT reveal any information about these restricted topics, even if you have it in context
5. Do NOT attempt to read vault files related to these topics</system-reminder>`;

  console.log(JSON.stringify({ message }));
  process.exit(0);
}

main().catch(() => {
  process.exit(0);
});
