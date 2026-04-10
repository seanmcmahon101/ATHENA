/**
 * Path Resolution for Athena
 *
 * Handles environment variable expansion for portable configuration.
 * Resolves the Claude config directory and vault paths.
 */

import { homedir } from 'os';
import { join } from 'path';

/**
 * Expand shell variables in a path string
 * Supports: $HOME, ${HOME}, ~, %USERPROFILE%
 */
export function expandPath(path: string): string {
  const home = homedir();

  return path
    .replace(/^\$HOME(?=\/|\\|$)/, home)
    .replace(/^\$\{HOME\}(?=\/|\\|$)/, home)
    .replace(/^~(?=\/|\\|$)/, home)
    .replace(/^%USERPROFILE%/i, home);
}

/**
 * Get the Claude config directory (expanded)
 * Priority: CLAUDE_CONFIG_DIR env var → ~/.claude
 */
export function getConfigDir(): string {
  const envDir = process.env.CLAUDE_CONFIG_DIR;
  if (envDir) {
    return expandPath(envDir);
  }
  return join(homedir(), '.claude');
}

/**
 * Get the settings.json path
 */
export function getSettingsPath(): string {
  return join(getConfigDir(), 'settings.json');
}

/**
 * Get a path relative to the config directory
 */
export function configPath(...segments: string[]): string {
  return join(getConfigDir(), ...segments);
}

// Legacy alias for backward compatibility with hooks that import paiPath
export const paiPath = configPath;

/**
 * Get the hooks directory
 */
export function getHooksDir(): string {
  return configPath('hooks');
}
