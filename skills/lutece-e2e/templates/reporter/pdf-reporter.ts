import type {
  Reporter, FullConfig, Suite, TestCase, TestResult, FullResult,
} from '@playwright/test/reporter';
import * as fs from 'fs';
import * as path from 'path';
import { spawnSync } from 'child_process';
import { renderHtml, TestEntry, ShotEntry, AnnotationEntry, verdictOf } from './render';

interface Options {
  outputDir?: string;
}

interface AnnotationCarrier {
  annotations?: { type: string; description?: string }[];
}

export default class PdfReporter implements Reporter {
  private outputDir: string;
  private shotsDir: string;
  private entries: TestEntry[] = [];
  private startedAt = 0;

  constructor(options: Options = {}) {
    this.outputDir = path.resolve(process.cwd(), options.outputDir || 'report');
    this.shotsDir = path.join(this.outputDir, 'screenshots');
  }

  /** Purge uniquement rapport.html, rapport.pdf et screenshots/ ; laisse intacts les autres fichiers de report/. */
  onBegin(_config: FullConfig, _suite: Suite): void {
    fs.rmSync(this.shotsDir, { recursive: true, force: true });
    fs.rmSync(path.join(this.outputDir, 'rapport.html'), { force: true });
    fs.rmSync(path.join(this.outputDir, 'rapport.pdf'), { force: true });
    fs.mkdirSync(this.shotsDir, { recursive: true });
    this.startedAt = Date.now();
  }

  onTestEnd(test: TestCase, result: TestResult): void {
    const suiteName = this.suiteOf(test);
    const shots: ShotEntry[] = [];
    let idx = 0;
    for (const att of result.attachments) {
      if (!att.contentType?.startsWith('image/')) continue;
      let buffer: Buffer | undefined;
      if (att.body) buffer = att.body;
      else if (att.path && fs.existsSync(att.path)) buffer = fs.readFileSync(att.path);
      if (!buffer) continue;
      idx += 1;
      const fname = `${this.slug(test.title)}-${idx}.png`;
      fs.writeFileSync(path.join(this.shotsDir, fname), buffer);
      shots.push({ label: att.name || `shot-${idx}`, file: `screenshots/${fname}` });
    }
    this.entries.push({
      title: test.title,
      suite: suiteName,
      status: result.status,
      durationMs: result.duration,
      error: result.error?.message?.split('\n').slice(0, 4).join('\n'),
      shots,
      annotations: this.annotationsOf(test, result),
    });
  }

  /** Fusionne les annotations portées par le résultat et par le cas de test (selon la version de Playwright). */
  private annotationsOf(test: TestCase, result: TestResult): AnnotationEntry[] {
    const sources: AnnotationEntry[][] = [
      (result as AnnotationCarrier).annotations || [],
      (test as AnnotationCarrier).annotations || [],
    ];
    const out: AnnotationEntry[] = [];
    const seen = new Set<string>();
    for (const list of sources) {
      for (const a of list) {
        if (!a || typeof a.type !== 'string') continue;
        const key = `${a.type}|${a.description || ''}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push({ type: a.type, description: a.description });
      }
    }
    return out;
  }

  async onEnd(result: FullResult): Promise<void> {
    const totalMs = Date.now() - this.startedAt;
    const html = renderHtml(this.entries, {
      status: result.status,
      totalMs,
      generatedAt: new Date().toLocaleString('fr-FR'),
    });
    const htmlPath = path.join(this.outputDir, 'rapport.html');
    fs.writeFileSync(htmlPath, html, 'utf-8');
    const nb = (v: string): number => this.entries.filter((e) => verdictOf(e) === v).length;
    // eslint-disable-next-line no-console
    console.log(`\n[reporter] HTML écrit : ${htmlPath}`);
    // eslint-disable-next-line no-console
    console.log(`[reporter] échecs réels : ${nb('failed')} | non applicable : ${nb('na')} | environnement absent : ${nb('env-absent')} | réussis : ${nb('passed')}`);
    // eslint-disable-next-line no-console
    console.log('[reporter] captures et PDF : données personnelles possibles — ne pas versionner, ne pas transmettre.');

    const pdfPath = path.join(this.outputDir, 'rapport.pdf');
    const chrome = process.env.CHROME_BIN || 'google-chrome';
    const args = [
      '--headless=new', '--no-sandbox', '--disable-gpu',
      '--no-pdf-header-footer',
      `--print-to-pdf=${pdfPath}`,
      `file://${htmlPath}`,
    ];
    const res = spawnSync(chrome, args, { timeout: 60_000, encoding: 'utf-8' });
    if (res.status === 0 && fs.existsSync(pdfPath)) {
      // eslint-disable-next-line no-console
      console.log(`[reporter] PDF écrit : ${pdfPath}`);
    } else {
      // eslint-disable-next-line no-console
      console.warn(`[reporter] Échec génération PDF (chrome exit=${res.status}). HTML disponible.`, res.stderr || '');
    }
  }

  private suiteOf(test: TestCase): string {
    const file = test.location.file;
    if (/fo-crawl/.test(file)) return 'FO — Parcours complet';
    if (/fo-functional/.test(file)) return 'FO — Fonctionnel';
    if (/bo-crawl/.test(file)) return 'BO — Parcours complet';
    // CRUD généré : tests/bo-<plugin>-<entité>-crud.spec.ts
    if (/bo-.*-crud/.test(file)) return 'BO — Fonctionnel (CRUD)';
    // Flux à conteneurs mock (env de test)
    if (/bo-mail/.test(file)) return 'BO — Mail (env de test)';
    if (/fo-login/.test(file)) return 'FO — Authentification';
    if (/fo-contact/.test(file)) return 'FO — Contact (env de test)';
    return 'Autres';
  }

  private slug(s: string): string {
    return s.replace(/[^a-z0-9]+/gi, '-').replace(/^-+|-+$/g, '').slice(0, 60).toLowerCase() || 'test';
  }

  printsToStdio(): boolean {
    return false;
  }
}
