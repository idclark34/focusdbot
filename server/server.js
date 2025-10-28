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

// In-memory counter/cache (reset on restart)
let downloadCount = 0;
const geoCache = new Map(); // key: ipHash, val: country code

async function lookupCountry(ip) {
  // local/dev addresses
  if (!ip || ip.startsWith('127.') || ip === '::1') return 'LO';
  try {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 1200);
    // Minimal endpoint that returns 2-letter code; anonymous tier is rate-limited
    const resp = await fetch(`https://ipapi.co/${encodeURIComponent(ip)}/country/`, { signal: controller.signal });
    clearTimeout(t);
    if (!resp.ok) return 'ZZ';
    const text = (await resp.text()).trim().toUpperCase();
    return /^[A-Z]{2}$/.test(text) ? text : 'ZZ';
  } catch {
    return 'ZZ';
  }
}

app.post('/download', async (req, res) => {
  downloadCount += 1;
  const ts = new Date().toISOString();
  const ua = (req.headers['user-agent'] || '').replaceAll('\n', ' ');
  const ip = (req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').toString().split(',')[0].trim();
  const ipHash = crypto.createHash('sha256').update(ip + '|' + HASH_SALT).digest('hex').slice(0, 16);
  const file = 'FocusdBot-Simple.dmg';

  let country = geoCache.get(ipHash);
  if (!country) {
    country = await lookupCountry(ip);
    geoCache.set(ipHash, country);
  }

  // CSV columns: timestamp,file,ip_hash,country,"user_agent"
  const row = `${ts},${file},${ipHash},${country},"${ua}"
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

function countryFromDownloadRow(line) {
  // Accept both old and new formats:
  // old: ts,file,ip_hash,"ua"
  // new: ts,file,ip_hash,country,"ua"
  // We ignore the UA field entirely (quoted and may contain commas)
  // Fast parse by finding first 3-4 commas.
  let comma = -1;
  const commas = [];
  for (let i = 0; i < line.length && commas.length < 4; i++) {
    if (line[i] === ',') commas.push(i);
  }
  if (commas.length < 3) return 'ZZ';
  if (commas.length >= 4) {
    // new format: country between 3rd and 4th comma
    const c = line.slice(commas[2] + 1, commas[3]).trim();
    return /^[A-Z]{2}$/.test(c) ? c : 'ZZ';
  }
  return 'ZZ'; // old rows have no country
}

// Metrics view: totals for downloads and signups (+ country histogram)
app.get('/metrics', (_req, res) => {
  let persistedDownloads = 0;
  let persistedSignups = 0;
  const byCountry = {};
  try {
    if (existsSync(downloadsCsvPath)) {
      const text = readFileSync(downloadsCsvPath, 'utf8').trim();
      if (text) {
        const lines = text.split('\n');
        persistedDownloads = lines.length;
        for (const ln of lines) {
          const cc = countryFromDownloadRow(ln) || 'ZZ';
          byCountry[cc] = (byCountry[cc] || 0) + 1;
        }
      }
    }
  } catch {}
  try {
    if (existsSync(csvPath)) {
      const text = readFileSync(csvPath, 'utf8').trim();
      persistedSignups = text ? text.split('\n').length : 0;
    }
  } catch {}
  res.json({
    downloads: {
      runtime: downloadCount,
      total: persistedDownloads,
      byCountry
    },
    signups: {
      total: persistedSignups
    }
  });
});

app.listen(PORT, () => {
  console.log(`FocusdBot server listening on http://localhost:${PORT}`);
});
