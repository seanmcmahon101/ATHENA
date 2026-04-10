/**
 * Identity Loader (Athena)
 *
 * Minimal identity module for Athena. Reads principal timezone
 * from settings.json for timestamp generation.
 */

import { readFileSync, existsSync } from 'fs';
import { getSettingsPath } from './paths';

export interface Principal {
  name: string;
  timezone: string;
}

interface Settings {
  principal?: Partial<Principal>;
  env?: Record<string, string>;
  [key: string]: unknown;
}

let cachedSettings: Settings | null = null;

function loadSettings(): Settings {
  if (cachedSettings) return cachedSettings;

  try {
    const settingsPath = getSettingsPath();
    if (!existsSync(settingsPath)) {
      cachedSettings = {};
      return cachedSettings;
    }

    const content = readFileSync(settingsPath, 'utf-8');
    cachedSettings = JSON.parse(content);
    return cachedSettings!;
  } catch {
    cachedSettings = {};
    return cachedSettings;
  }
}

/**
 * Get Principal identity from settings.json
 */
export function getPrincipal(): Principal {
  const settings = loadSettings();
  const principal = settings.principal || {};
  const envPrincipal = settings.env?.PRINCIPAL;

  return {
    name: principal.name || envPrincipal || 'User',
    timezone: principal.timezone || 'UTC',
  };
}

/**
 * Get just the Principal name
 */
export function getPrincipalName(): string {
  return getPrincipal().name;
}

/**
 * Clear cache (for testing)
 */
export function clearCache(): void {
  cachedSettings = null;
}
