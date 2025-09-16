import express from 'express';
import cors from 'cors';
import morgan from 'morgan';

const app = express();
const PORT = process.env.PORT || 8787;

app.use(cors());
app.use(express.json());
app.use(morgan('tiny'));

// Serve the static marketing site at /
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
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

// Simple metrics endpoints
let downloadCount = 0;
app.post('/download', (_req, res) => {
  downloadCount += 1;
  res.json({ ok: true, downloads: downloadCount });
});

// Email capture (write to a CSV file locally)
import { appendFile } from 'node:fs';
import { existsSync, mkdirSync } from 'node:fs';
const dataDir = join(process.cwd(), 'data');
if (!existsSync(dataDir)) mkdirSync(dataDir, { recursive: true });
const csvPath = join(dataDir, 'signups.csv');

app.post('/api/subscribe', (req, res) => {
  const { email } = req.body || {};
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return res.status(400).json({ ok: false, error: 'invalid_email' });
  }
  const row = `${new Date().toISOString()},${email}\n`;
  appendFile(csvPath, row, (err) => {
    if (err) return res.status(500).json({ ok: false });
    res.json({ ok: true });
  });
});

app.listen(PORT, () => {
  console.log(`FocusdBot server listening on http://localhost:${PORT}`);
});
