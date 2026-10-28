document.addEventListener('submit', (event) => {
  const message = event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
});

document.addEventListener('DOMContentLoaded', () => {
  if (document.querySelector('[data-auto-refresh]')) {
    window.setInterval(() => {
      if (!document.querySelector('dialog[open]')) window.location.reload();
    }, 600000);
  }
});

// Anchor the preview to server time so it also works with a different browser timezone.
const deadlineClockStartedAt = performance.now();
const updateDeadlineHint = (event) => {
  const field = event.target.closest('[data-deadline-field]');
  if (!field) return;

  const time = event.target.value;
  let hint = '時刻を指定してください。';
  if (/^\d{2}:\d{2}$/.test(time)) {
    const elapsed = performance.now() - deadlineClockStartedAt;
    const japanTime = new Date(Number(field.dataset.now) + elapsed + 9 * 60 * 60 * 1000);
    const currentTime = japanTime.toISOString().slice(11, 16);
    const day = time < currentTime ? '翌日' : '本日';
    hint = time === currentTime ? '現在と同じ時刻は指定できません。' : `${day}`;
  }
  field.querySelector('[data-deadline-day]').textContent = hint;
};

document.addEventListener('input', updateDeadlineHint);
document.addEventListener('change', updateDeadlineHint);

const deadlineSubmissions = new WeakSet();
const approvedDeadlineForms = new WeakSet();
document.addEventListener('submit', async (event) => {
  const form = event.target;
  const field = form.querySelector('[data-deadline-field] input');
  const dialog = document.querySelector('#deadline-confirmation');
  if (!field || !dialog || approvedDeadlineForms.delete(form)) return;
  event.preventDefault();
  if (deadlineSubmissions.has(form) || dialog.open) return;
  deadlineSubmissions.add(form);
  const value = field.value;
  const submitter = event.submitter;
  const submit = () => {
    approvedDeadlineForms.add(form);
    form.requestSubmit(submitter);
  };
  try {
    const response = await fetch(dialog.dataset.previewUrl, {
      method: 'POST',
      headers: { 'Accept': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '' },
      body: new URLSearchParams({ expires_at: value })
    });
    if (!response.ok) { submit(); return; }
    const preview = await response.json();
    if (field.value !== value) return;
    if (!preview.confirmation_required) { submit(); return; }
    const item = form.closest('tr').querySelector('.fw-semibold').textContent;
    dialog.querySelector('[data-confirmation-message]').textContent = `${item}の利用期限は、${preview.label}です。この日時まで利用します。よろしいですか？`;
    dialog.returnValue = 'cancel';
    const confirmed = new Promise(resolve => dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true }));
    dialog.showModal();
    if (await confirmed) {
      let confirmation = form.querySelector('input[name="confirmed_expires_at"]');
      if (!confirmation) {
        confirmation = document.createElement('input');
        confirmation.type = 'hidden';
        confirmation.name = 'confirmed_expires_at';
        form.append(confirmation);
      }
      confirmation.value = preview.expires_at;
      submit();
    }
  } catch {
    // Keep server-side confirmation available if the preview request fails.
    submit();
  } finally {
    deadlineSubmissions.delete(form);
  }
});
