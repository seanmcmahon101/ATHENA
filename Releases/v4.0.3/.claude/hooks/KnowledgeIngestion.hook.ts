#!/usr/bin/env bun
/**
 * KnowledgeIngestion.hook.ts - Extract & Store Company Knowledge (Stop)
 *
 * PURPOSE:
 * After each Claude response, analyzes the conversation for extractable
 * company knowledge and stores it in the shared memory vault with proper
 * classification, attribution, and metadata.
 *
 * TRIGGER: Stop (runs after every Claude response)
 *
 * INPUT:
 * - stop_hook_active: boolean
 * - session_id: string
 * - transcript (from stdin): recent conversation messages
 *
 * OUTPUT:
 * - Writes knowledge files to W:\MEMORY\{classification}\{department}\
 * - Appends entries to W:\MEMORY\_index.jsonl
 * - Logs ingestion to W:\MEMORY\AUDIT\
 *
 * DESIGN:
 * This hook scans the last assistant response for signals that new company
 * knowledge was shared (decisions, processes, architecture, policies).
 * It extracts structured knowledge and writes it to the appropriate vault
 * directory based on the employee's department and clearance level.
 *
 * PERFORMANCE:
 * - Non-blocking: Runs on Stop event after response is delivered
 * - Typical execution: <100ms
 * - Writes are append-only (no reads of large data)
 */

import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { getEmployee, getVaultPath, hasClearance, type ClearanceLevel } from './lib/employee';

interface HookInput {
  session_id?: string;
  stop_hook_active?: boolean;
  transcript?: Array<{ role: string; content: string }>;
}

interface KnowledgeEntry {
  id: string;
  classification: ClearanceLevel;
  department: string;
  contributed_by: string;
  contributor_name: string;
  created: string;
  source_session: string;
  tags: string[];
  summary: string;
  file_path: string;
}

// Knowledge signal patterns — indicates the conversation contains extractable knowledge
const KNOWLEDGE_SIGNALS = [
  // Decisions
  /we decided to/i,
  /the decision was/i,
  /we chose to/i,
  /we went with/i,
  /we agreed on/i,
  // Processes
  /the process is/i,
  /our workflow for/i,
  /the procedure for/i,
  /how we handle/i,
  /our approach to/i,
  /standard practice/i,
  // Architecture & Technical
  /our architecture/i,
  /the system works by/i,
  /we use .+ for/i,
  /our stack includes/i,
  /the api .+ endpoint/i,
  /our database/i,
  /we deploy using/i,
  // Policies
  /company policy/i,
  /our policy on/i,
  /the rule is/i,
  /guidelines for/i,
  // Project Context
  /the project goal/i,
  /we're building/i,
  /the requirements are/i,
  /the deadline is/i,
  /the client wants/i,
  /blockers? (are|is)/i,
];

// Department detection from content
const DEPARTMENT_KEYWORDS: Record<string, string[]> = {
  engineering: ['code', 'api', 'deploy', 'database', 'architecture', 'bug', 'repository', 'CI/CD', 'pipeline', 'infrastructure', 'server', 'backend', 'frontend'],
  product: ['feature', 'roadmap', 'user story', 'requirement', 'specification', 'sprint', 'backlog', 'milestone', 'release'],
  design: ['mockup', 'wireframe', 'figma', 'design system', 'typography', 'color palette', 'UX', 'UI', 'user interface'],
  hr: ['onboarding', 'hiring', 'interview', 'benefits', 'leave policy', 'PTO', 'employee handbook'],
  finance: ['budget', 'invoice', 'expense', 'procurement', 'vendor', 'contract'],
  'company-wide': ['all-hands', 'company meeting', 'announcement', 'culture', 'values', 'mission'],
};

function detectDepartment(content: string): string {
  const contentLower = content.toLowerCase();
  let bestDept = 'company-wide';
  let bestScore = 0;

  for (const [dept, keywords] of Object.entries(DEPARTMENT_KEYWORDS)) {
    const score = keywords.filter(kw => contentLower.includes(kw.toLowerCase())).length;
    if (score > bestScore) {
      bestScore = score;
      bestDept = dept;
    }
  }

  return bestDept;
}

function generateId(summary: string): string {
  const now = new Date();
  const timestamp = now.toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const slug = summary
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .slice(0, 40);
  return `kb_${timestamp}_${slug}`;
}

function extractSummary(content: string): string {
  // Take the first meaningful sentence as summary
  const sentences = content.split(/[.!?]\s+/);
  for (const sentence of sentences) {
    const trimmed = sentence.trim();
    if (trimmed.length > 20 && trimmed.length < 200) {
      return trimmed;
    }
  }
  return content.slice(0, 150).trim();
}

function extractTags(content: string): string[] {
  const tags: string[] = [];
  const contentLower = content.toLowerCase();

  // Simple tag extraction from common technical/business terms
  const tagCandidates = [
    'api', 'database', 'deployment', 'testing', 'security', 'performance',
    'architecture', 'design', 'process', 'policy', 'integration',
    'authentication', 'authorization', 'monitoring', 'logging',
    'infrastructure', 'frontend', 'backend', 'mobile', 'cloud',
  ];

  for (const tag of tagCandidates) {
    if (contentLower.includes(tag)) tags.push(tag);
  }

  return tags.slice(0, 8); // Max 8 tags
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
    // Silent
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

  // Get the conversation content — focus on the last few messages
  const transcript = input.transcript;
  if (!transcript || transcript.length === 0) {
    process.exit(0);
  }

  // Combine the last user message and assistant response
  const recentMessages = transcript.slice(-4);
  const userContent = recentMessages
    .filter(m => m.role === 'user')
    .map(m => m.content)
    .join('\n');
  const assistantContent = recentMessages
    .filter(m => m.role === 'assistant')
    .map(m => m.content)
    .join('\n');
  const combinedContent = `${userContent}\n${assistantContent}`;

  // Check if the conversation contains knowledge signals
  const hasKnowledgeSignal = KNOWLEDGE_SIGNALS.some(pattern => pattern.test(combinedContent));
  if (!hasKnowledgeSignal) {
    process.exit(0);
  }

  const employee = getEmployee();
  const vaultPath = getVaultPath();

  // Determine classification — employee can only contribute at or below their clearance
  const classification: ClearanceLevel = employee.clearance === 'restricted' ? 'internal' :
    employee.clearance === 'confidential' ? 'internal' : 'internal';
  // Most ingested knowledge defaults to INTERNAL. Confidential/restricted content
  // should be manually classified by authorized personnel.

  const department = employee.department !== 'unknown' ? employee.department : detectDepartment(combinedContent);
  const summary = extractSummary(userContent || combinedContent);
  const tags = extractTags(combinedContent);
  const id = generateId(summary);

  // Build the knowledge file
  const classificationDir = classification.toUpperCase();
  const targetDir = join(vaultPath, classificationDir, department);

  if (!existsSync(targetDir)) {
    mkdirSync(targetDir, { recursive: true });
  }

  const fileName = `${id}.md`;
  const filePath = join(targetDir, fileName);

  const knowledgeFile = `---
id: "${id}"
classification: "${classification}"
department: "${department}"
contributed_by: "${employee.employee_id}"
contributor_name: "${employee.name}"
created: "${new Date().toISOString()}"
source_session: "${input.session_id || 'unknown'}"
tags: ${JSON.stringify(tags)}
summary: "${summary.replace(/"/g, '\\"')}"
---

${combinedContent.slice(0, 2000)}
`;

  // Write knowledge file
  try {
    writeFileSync(filePath, knowledgeFile);
  } catch (err) {
    console.error(`[KnowledgeIngestion] Failed to write knowledge file: ${err}`);
    process.exit(0);
  }

  // Append to index
  const indexEntry: KnowledgeEntry = {
    id,
    classification,
    department,
    contributed_by: employee.employee_id,
    contributor_name: employee.name,
    created: new Date().toISOString(),
    source_session: input.session_id || 'unknown',
    tags,
    summary,
    file_path: `${classificationDir}/${department}/${fileName}`,
  };

  try {
    const indexPath = join(vaultPath, '_index.jsonl');
    appendFileSync(indexPath, JSON.stringify(indexEntry) + '\n');
  } catch {
    // Index append failure is non-critical
  }

  // Audit log
  logAudit({
    timestamp: new Date().toISOString(),
    employee_id: employee.employee_id,
    employee_name: employee.name,
    role: employee.role,
    action: 'ingested',
    target: `${classificationDir}/${department}/${fileName}`,
    classification,
    department,
    decision: 'allowed',
    reason: 'knowledge_ingestion',
    session_id: input.session_id || 'unknown',
  });

  process.exit(0);
}

main().catch(() => {
  process.exit(0);
});
