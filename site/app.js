const yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Configure download link
const ZIP_URL = 'dist/FocusdBot-Simple-1.0.3.dmg';
const API_BASE = window.API_BASE || '';
const setDownload = (el) => {
  if (!el) return;
  el.href = ZIP_URL;
  // Hide download links for non-macOS user agents as a hard guard
  const ua = navigator.userAgent || '';
  const isMac = /Macintosh|Mac OS X|Macintosh;/.test(ua);
  if (!isMac) {
    el.style.display = 'none';
    return;
  }
  el.addEventListener('click', () => {
    const url = API_BASE ? `${API_BASE}/download` : '/download';
    fetch(url, { method: 'POST' }).catch(() => {});
  });
};
setDownload(document.getElementById('downloadBtn'));
setDownload(document.getElementById('navDownload'));

// Email signup
const form = document.getElementById('signupForm');
const msg = document.getElementById('signupMsg');
if (form) {
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('email').value.trim();
    if (!email) return;
    try {
      const endpoint = API_BASE ? `${API_BASE}/api/subscribe` : '/api/subscribe';
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      });
      if (!res.ok) throw new Error();
      msg.textContent = 'Thanks! We\'ll keep you posted.';
      form.reset();
    } catch {
      msg.textContent = 'Could not subscribe right now. Try again later.';
    }
  });
}
