/**
 * Shared Stdin Reader
 *
 * Provides a robust, runtime-agnostic stdin reader that works with both
 * Bun and Node.js. Replaces all direct Bun.stdin.stream() calls.
 *
 * Claude Code pipes JSON via stdin to hooks. This utility reads it with
 * a timeout fallback to handle cases where stdin doesn't close promptly
 * (a known issue with Bun's stdin handling).
 */

/**
 * Read all data from stdin with a timeout safety net.
 *
 * @param timeoutMs - Maximum time to wait for stdin to close (default: 1000ms)
 * @returns The raw stdin content as a string
 */
export async function readStdin(timeoutMs = 1000): Promise<string> {
  return new Promise((resolve) => {
    let data = '';
    let resolved = false;

    const done = (result: string) => {
      if (!resolved) {
        resolved = true;
        clearTimeout(timer);
        // Clean up listeners so the process can exit promptly
        process.stdin.removeAllListeners('data');
        process.stdin.removeAllListeners('end');
        process.stdin.removeAllListeners('error');
        process.stdin.pause();
        resolve(result);
      }
    };

    const timer = setTimeout(() => done(data), timeoutMs);

    process.stdin.on('data', (chunk: Buffer | Uint8Array) => {
      data += chunk.toString();
    });

    process.stdin.on('end', () => done(data));
    process.stdin.on('error', () => done(data));

    // Ensure stdin is in flowing mode
    process.stdin.resume();
  });
}

/**
 * Read and parse JSON from stdin.
 * Returns null if stdin is empty or contains invalid JSON.
 */
export async function readStdinJSON<T = unknown>(timeoutMs = 1000): Promise<T | null> {
  const raw = await readStdin(timeoutMs);
  if (!raw.trim()) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}
