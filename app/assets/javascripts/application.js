document.addEventListener('submit', (event) => {
  const message = event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
});

document.addEventListener('DOMContentLoaded', () => {
  if (document.querySelector('[data-auto-refresh]')) {
    window.setInterval(() => window.location.reload(), 600000);
  }
});
