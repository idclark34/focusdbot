import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { appendFile, existsSync, mkdirSync, readFileSync } from 'node:fs';
import crypto from 'node:crypto';

const app = express();
const PORT = process.env.PORT || 8787;

app.use(cors());
app.use(express.json());
app.use(morgan('tiny'));

// Serve the static marketing site at /
const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, '..');
const siteDir = join(repoRoot, 'site');
const publicDir = join(__dirname, 'public');
const staticRoot = existsSync(siteDir) ? siteDir : publicDir;
app.use('/', express.static(staticRoot));

// Social preview image: serve repo AppIcon.png as /assets/og.png
const ogImagePath = join(repoRoot, 'AppIcon.png');
app.get('/assets/og.png', (_req, res) => {
  res.sendFile(ogImagePath);
});

// Simple metrics storage
const dataDir = join(process.cwd(), 'data');
if (!existsSync(dataDir)) mkdirSync(dataDir, { recursive: true });
const csvPath = join(dataDir, 'signups.csv');
const downloadsCsvPath = join(dataDir, 'downloads.csv');
const HASH_SALT = process.env.METRICS_SALT || 'focusdbot-salt';

// In-memory counter remains for quick runtime view (resets on restart)
let downloadCount = 0;

app.post('/download', (req, res) => {
  downloadCount += 1;
  const ts = new Date().toISOString();
  const ua = (req.headers['user-agent'] || '').replaceAll('\n', ' ');
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').toString();
  const ipHash = crypto.createHash('sha256').update(ip + '|' + HASH_SALT).digest('hex').slice(0, 16);
  const file = 'FocusdBot-Simple.dmg';
  const row = `${ts},${file},${ipHash},"${ua}"
`;
  appendFile(downloadsCsvPath, row, () => {});
  res.json({ ok: true, downloads: downloadCount });
});

// Email capture (write to a CSV file locally)
app.post('/api/subscribe', (req, res) => {
  const { email } = req.body || {};
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return res.status(400).json({ ok: false, error: 'invalid_email' });
  }
  const row = `${new Date().toISOString()},${email}
`;
  appendFile(csvPath, row, (err) => {
    if (err) return res.status(500).json({ ok: false });
    res.json({ ok: true });
  });
});

// Metrics view: totals for downloads and signups
app.get('/metrics', (_req, res) => {
  let persistedDownloads = 0;
  let persistedSignups = 0;
  try {
    if (existsSync(downloadsCsvPath)) {
      const text = readFileSync(downloadsCsvPath, 'utf8');
      persistedDownloads = text.trim() ? text.trim().split('\n').length : 0;
    }
  } catch {}
  try {
    if (existsSync(csvPath)) {
      const text = readFileSync(csvPath, 'utf8');
      persistedSignups = text.trim() ? text.trim().split('\n').length : 0;
    }
  } catch {}
  res.json({
    downloads: {
      runtime: downloadCount,
      total: persistedDownloads
    },
    signups: {
      total: persistedSignups
    }
  });
});

app.listen(PORT, () => {
  console.log(`FocusdBot server listening on http://localhost:${PORT}`);
});
