#!/usr/bin/env bun
/**
 * KnowledgeIngestion.hook.ts - Extract & Store Company Knowledge (Stop)
 *
 * PURPOSE:
 * After each Claude response, analyzes the conversation for extractable
 * company knowledge and stores it in the shared memory vault with proper
 * classification, attribution, and metadata.
 *
 * CLASSIFICATION LOGIC:
 * - Scans content for sensitive topic keywords from company-roles.json
 * - If restricted topics detected → classifies as CONFIDENTIAL (not INTERNAL)
 * - Requires 2+ knowledge signal matches for quality control
 * - Default classification: INTERNAL
 *
 * TRIGGER: Stop (runs after every Claude response)
 */

import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';
import { createHash } from 'crypto';
import { readStdinJSON } from './lib/stdin';
import { getEmployee, getVaultPath, getCompanyRoles, hasClearance, type ClearanceLevel } from './lib/employee';

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
  /\bwe decided to\b/i,
  /\bthe decision was\b/i,
  /\bwe chose to\b/i,
  /\bwe went with\b/i,
  /\bwe agreed on\b/i,
  // Processes
  /\bthe process is\b/i,
  /\bour workflow for\b/i,
  /\bthe procedure for\b/i,
  /\bhow we handle\b/i,
  /\bour approach to\b/i,
  /\bstandard practice\b/i,
  // Architecture & Technical
  /\bour architecture\b/i,
  /\bthe system works by\b/i,
  /\bwe use \w+ for\b/i,
  /\bour stack includes\b/i,
  /\bthe api \w+ endpoint\b/i,
  /\bour database\b/i,
  /\bwe deploy using\b/i,
  // Policies
  /\bcompany policy\b/i,
  /\bour policy on\b/i,
  /\bthe rule is\b/i,
  /\bguidelines for\b/i,
  // Project Context
  /\bthe project goal\b/i,
  /\bwe're building\b/i,
  /\bthe requirements are\b/i,
  /\bthe deadline is\b/i,
  /\bthe client wants\b/i,
  /\bblockers? (?:are|is)\b/i,
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

/**
 * Detect if content contains sensitive topics that require elevated classification.
 * Returns the minimum clearance level needed based on detected topics.
 */
function detectSensitiveClassification(content: string): ClearanceLevel {
  const roles = getCompanyRoles();
  const topicRestrictions = roles.topic_restrictions;
  let maxClearance: ClearanceLevel = 'internal';
  const hierarchy: ClearanceLevel[] = ['public', 'internal', 'confidential', 'restricted'];

  for (const [keyword, requiredClearance] of Object.entries(topicRestrictions)) {
    const escaped = keyword.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(`\\b${escaped}\\b`, 'i');
    if (regex.test(content)) {
      const currentIdx = hierarchy.indexOf(maxClearance);
      const newIdx = hierarchy.indexOf(requiredClearance as ClearanceLevel);
      if (newIdx > currentIdx) {
        maxClearance = requiredClearance as ClearanceLevel;
      }
    }
  }

  return maxClearance;
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

  const tagCandidates = [
    'api', 'database', 'deployment', 'testing', 'security', 'performance',
    'architecture', 'design', 'process', 'policy', 'integration',
    'authentication', 'authorization', 'monitoring', 'logging',
    'infrastructure', 'frontend', 'backend', 'mobile', 'cloud',
  ];

  for (const tag of tagCandidates) {
    if (contentLower.includes(tag)) tags.push(tag);
  }

  return tags.slice(0, 8);
}

/**
 * Generate a hash of the knowledge entry for deduplication.
 */
function generateContentHash(summary: string, department: string, tags: string[]): string {
  const hashInput = `${summary.toLowerCase().trim()}|${department}|${tags.sort().join(',')}`;
  return createHash('sha256').update(hashInput).digest('hex').slice(0, 16);
}

/**
 * Check if a similar entry already exists in the index.
 */
function isDuplicate(indexPath: string, contentHash: string): boolean {
  if (!existsSync(indexPath)) return false;
  try {
    const content = readFileSync(indexPath, 'utf-8');
    // Check if the hash appears in any existing entry
    return content.includes(`"content_hash":"${contentHash}"`);
  } catch {
    return false;
  }
}

function logAudit(entry: Record<string, unknown>): void {
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
    // Silent
  }
}

async function main() {
  const input = await readStdinJSON<HookInput>();

  if (!input) {
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

  // Require 2+ knowledge signal matches for quality control
  const signalCount = KNOWLEDGE_SIGNALS.filter(pattern => pattern.test(combinedContent)).length;
  if (signalCount < 2) {
    process.exit(0);
  }

  const employee = getEmployee();
  const vaultPath = getVaultPath();
  if (!vaultPath) {
    process.exit(0);
  }

  // Determine classification based on content sensitivity
  // Detect sensitive topics and elevate classification accordingly
  const detectedClearance = detectSensitiveClassification(combinedContent);

  // If content is more sensitive than the employee's clearance, skip ingestion entirely.
  // We cannot safely store it: downgrading would leak confidential content,
  // and the employee shouldn't have been discussing it (PromptGuard should block).
  const hierarchy: ClearanceLevel[] = ['public', 'internal', 'confidential', 'restricted'];
  const employeeIdx = hierarchy.indexOf(employee.clearance);
  const detectedIdx = hierarchy.indexOf(detectedClearance);

  if (detectedIdx > employeeIdx) {
    // Sensitive content above employee's clearance — do not persist at lower level
    process.exit(0);
  }

  // Classify at the detected sensitivity level (never below what the content demands)
  const classification: ClearanceLevel = detectedClearance;

  const department = employee.department !== 'unknown' && employee.department !== 'pending'
    ? employee.department
    : detectDepartment(combinedContent);
  const summary = extractSummary(userContent || combinedContent);
  const tags = extractTags(combinedContent);
  const id = generateId(summary);

  // Deduplication check
  const indexPath = join(vaultPath, '_index.jsonl');
  const contentHash = generateContentHash(summary, department, tags);
  if (isDuplicate(indexPath, contentHash)) {
    process.exit(0);
  }

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
content_hash: "${contentHash}"
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

  // Append to index (with content_hash for dedup)
  const indexEntry = {
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
    content_hash: contentHash,
  };

  try {
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
