/**
 * Employee Identity Loader
 * Reads employee identity from ~/.claude/employee.json (per-machine, per-employee).
 * Reads company role definitions from company-roles.json (shared, in repo).
 *
 * All business hooks import from here.
 */

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const HOME = process.env.HOME || process.env.USERPROFILE || '';
const EMPLOYEE_PATH = join(HOME, '.claude', 'employee.json');
const VAULT_PATH = process.env.VAULT_PATH || '';

// Company roles config lives alongside settings.json
const ROLES_PATH = join(__dirname, '..', '..', 'company-roles.json');

export interface Employee {
  employee_id: string;
  name: string;
  email: string;
  department: string;
  role: string;
  clearance: ClearanceLevel;
}

export type ClearanceLevel = 'public' | 'internal' | 'confidential' | 'restricted';

export interface RoleDefinition {
  clearance: ClearanceLevel;
  departments_visible: string[];
}

export interface TopicRestrictions {
  [keyword: string]: ClearanceLevel;
}

export interface CompanyRoles {
  roles: Record<string, RoleDefinition>;
  clearance_hierarchy: ClearanceLevel[];
  topic_restrictions: TopicRestrictions;
}

const DEFAULT_EMPLOYEE: Employee = {
  employee_id: 'unknown',
  name: 'Unknown Employee',
  email: '',
  department: 'unknown',
  role: 'viewer',
  clearance: 'public',
};

let cachedEmployee: Employee | null = null;
let cachedRoles: CompanyRoles | null = null;

/**
 * Load employee identity from ~/.claude/employee.json
 */
export function getEmployee(): Employee {
  if (cachedEmployee) return cachedEmployee;

  try {
    if (!existsSync(EMPLOYEE_PATH)) {
      console.error(`[employee] No employee.json found at ${EMPLOYEE_PATH}. Using default (public) identity.`);
      cachedEmployee = DEFAULT_EMPLOYEE;
      return cachedEmployee;
    }

    const content = readFileSync(EMPLOYEE_PATH, 'utf-8');
    const parsed = JSON.parse(content);
    cachedEmployee = { ...DEFAULT_EMPLOYEE, ...parsed };
    return cachedEmployee!;
  } catch (err) {
    console.error(`[employee] Failed to load employee.json: ${err}`);
    cachedEmployee = DEFAULT_EMPLOYEE;
    return cachedEmployee;
  }
}

/**
 * Load company role definitions from company-roles.json
 */
export function getCompanyRoles(): CompanyRoles {
  if (cachedRoles) return cachedRoles;

  try {
    if (!existsSync(ROLES_PATH)) {
      console.error(`[employee] No company-roles.json found at ${ROLES_PATH}`);
      cachedRoles = {
        roles: {},
        clearance_hierarchy: ['public', 'internal', 'confidential', 'restricted'],
        topic_restrictions: {},
      };
      return cachedRoles;
    }

    const content = readFileSync(ROLES_PATH, 'utf-8');
    cachedRoles = JSON.parse(content);
    return cachedRoles!;
  } catch (err) {
    console.error(`[employee] Failed to load company-roles.json: ${err}`);
    cachedRoles = {
      roles: {},
      clearance_hierarchy: ['public', 'internal', 'confidential', 'restricted'],
      topic_restrictions: {},
    };
    return cachedRoles;
  }
}

/**
 * Get the vault base path (set via VAULT_PATH env var in settings.json)
 */
export function getVaultPath(): string {
  if (!VAULT_PATH) {
    console.error('[employee] VAULT_PATH is not set. Run setup.sh to configure your vault location.');
  }
  return VAULT_PATH;
}

/**
 * Check if a clearance level is sufficient for a required level
 */
export function hasClearance(employeeClearance: ClearanceLevel, requiredClearance: ClearanceLevel): boolean {
  const hierarchy = getCompanyRoles().clearance_hierarchy;
  const employeeLevel = hierarchy.indexOf(employeeClearance);
  const requiredLevel = hierarchy.indexOf(requiredClearance);
  return employeeLevel >= requiredLevel;
}

/**
 * Get the clearance level for a vault directory path
 */
export function getPathClearance(filePath: string): ClearanceLevel | null {
  const vaultPath = getVaultPath();
  const normalizedPath = filePath.replace(/\\/g, '/');
  const normalizedVault = vaultPath.replace(/\\/g, '/');

  if (!normalizedPath.startsWith(normalizedVault)) return null;

  const relativePath = normalizedPath.slice(normalizedVault.length + 1).toUpperCase();

  if (relativePath.startsWith('RESTRICTED')) return 'restricted';
  if (relativePath.startsWith('CONFIDENTIAL')) return 'confidential';
  if (relativePath.startsWith('INTERNAL')) return 'internal';
  if (relativePath.startsWith('PUBLIC')) return 'public';
  if (relativePath.startsWith('AUDIT')) return 'restricted'; // Audit logs are restricted

  return 'internal'; // Default for unclassified vault files
}

/**
 * Check if an employee can access a specific department directory
 */
export function canAccessDepartment(employee: Employee, department: string): boolean {
  const roles = getCompanyRoles();
  const roleDef = roles.roles[employee.role];
  if (!roleDef) return false;
  if (roleDef.departments_visible.includes('*')) return true;
  return roleDef.departments_visible.includes(department);
}

/**
 * Get the department from a vault file path (e.g., INTERNAL/engineering/foo.md → engineering)
 */
export function getDepartmentFromPath(filePath: string): string | null {
  const vaultPath = getVaultPath();
  const normalizedPath = filePath.replace(/\\/g, '/');
  const normalizedVault = vaultPath.replace(/\\/g, '/');

  if (!normalizedPath.startsWith(normalizedVault)) return null;

  const parts = normalizedPath.slice(normalizedVault.length + 1).split('/');
  // Structure: CLASSIFICATION/department/file.md
  if (parts.length >= 2) return parts[1].toLowerCase();
  return null;
}

/**
 * Clear caches (for testing)
 */
export function clearCache(): void {
  cachedEmployee = null;
  cachedRoles = null;
}
