import { env } from './helpers';

const BASE = env('MAILHOG_URL', 'http://localhost:8025');

export interface Mail {
  to: string[];
  from: string;
  subject: string;
  body: string;
}

function parse(item: any): Mail {
  const h = (item.Content && item.Content.Headers) || {};
  const to = (h.To || []).join(', ').split(',').map((s: string) => s.trim()).filter(Boolean);
  return {
    to,
    from: (h.From || [''])[0] || '',
    subject: (h.Subject || [''])[0] || '',
    body: (item.Content && item.Content.Body) || '',
  };
}

/**
 * Vrai si l'API MailHog répond dans le délai imparti. Ne lève jamais : renvoie `false` quand
 * l'environnement de test n'est pas démarré, pour permettre un saut annoté plutôt qu'un échec.
 */
export async function mailhogUp(timeoutMs = 1500): Promise<boolean> {
  const ctrl = new AbortController();
  const minuteur = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`${BASE}/api/v2/messages?limit=1`, { signal: ctrl.signal });
    return r.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(minuteur);
  }
}

/** Vide la boîte MailHog (à appeler avant un test pour isoler). */
export async function clearMails(): Promise<void> {
  await fetch(`${BASE}/api/v1/messages`, { method: 'DELETE' });
}

/** Tous les mails actuellement capturés. */
export async function getMails(): Promise<Mail[]> {
  const r = await fetch(`${BASE}/api/v2/messages`);
  const j = await r.json();
  return ((j && j.items) || []).map(parse);
}

/** Attend (jusqu'à timeoutMs) un mail satisfaisant le prédicat ; sinon throw. */
export async function waitForMail(pred: (m: Mail) => boolean, timeoutMs = 10_000): Promise<Mail> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const m = (await getMails()).find(pred);
    if (m) return m;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error('Aucun mail correspondant reçu dans MailHog dans le délai imparti');
}
