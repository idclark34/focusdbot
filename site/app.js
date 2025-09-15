const yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = new Date().getFullYear();

// Configure download link
const DMG_URL = 'https://github.com/idclark34/watchdog/releases/download/v1.0.0/FocusdBot-1.0.0.dmg';
const API_BASE = window.API_BASE || '';
const setDownload = (el) => {
  if (!el) return;
  el.href = DMG_URL;
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
