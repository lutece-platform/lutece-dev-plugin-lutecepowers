/**
 * Lutecepowers plugin for OpenCode.
 * Registers the skills directory and injects the bootstrap produced by hooks/session-start
 * into the first user message of each session.
 */

import { execFileSync } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PLUGIN_ROOT = path.resolve(__dirname, '../..');
const SKILLS_DIR = path.join(PLUGIN_ROOT, 'skills');
const HOOK = path.join(PLUGIN_ROOT, 'hooks', 'session-start');
const MARKER = 'EXTREMELY_IMPORTANT';

let bootstrapCache;

/**
 * Runs the shared session-start hook once and caches its additionalContext.
 */
const getBootstrap = () => {
  if (bootstrapCache !== undefined) return bootstrapCache;
  try {
    const out = execFileSync('bash', [HOOK, 'opencode'], { input: '', encoding: 'utf8', timeout: 15000 });
    const text = JSON.parse(out).hookSpecificOutput.additionalContext;
    if (text) bootstrapCache = text;
    return text || null;
  } catch {
    return null;
  }
};

/**
 * OpenCode plugin entry point: registers the skills directory and the bootstrap injection.
 */
export const LutecepowersPlugin = async () => {
  return {
    /** Adds the plugin skills directory to OpenCode skill discovery. */
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(SKILLS_DIR)) config.skills.paths.push(SKILLS_DIR);
    },

    /** Prepends the bootstrap once to the first user message, before each model call. */
    'experimental.chat.messages.transform': async (_input, output) => {
      const bootstrap = getBootstrap();
      if (!bootstrap || !output.messages.length) return;
      const firstUser = output.messages.find((m) => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;
      if (firstUser.parts.some((p) => p.type === 'text' && p.text.includes(MARKER))) return;
      const ref = firstUser.parts[0];
      firstUser.parts.unshift({
        id: `${ref.id}-lutecepowers`,
        sessionID: ref.sessionID,
        messageID: ref.messageID,
        type: 'text',
        text: bootstrap,
        synthetic: true,
      });
    },
  };
};

export default LutecepowersPlugin;
