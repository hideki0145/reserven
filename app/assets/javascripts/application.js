document.addEventListener('submit', (event) => {
  const message = event.target.dataset.confirm;
  if (message && !window.confirm(message)) event.preventDefault();
});

document.addEventListener('DOMContentLoaded', () => {
  if (!document.querySelector('[data-auto-refresh]')) return;

  const fields = Array.from(document.querySelectorAll('[data-deadline-field] input, [data-usage-reason]'));
  const hasChanges = () => fields.some(field => field.value !== field.defaultValue);
  const notice = document.querySelector('[data-refresh-paused]');
  const activeNotice = document.querySelector('[data-refresh-active]');
  const updateNotice = () => {
    const paused = hasChanges();
    notice.classList.toggle('invisible', !paused);
    activeNotice.classList.toggle('invisible', paused);
  };
  document.addEventListener('input', updateNotice);
  document.addEventListener('change', updateNotice);
  updateNotice();

  window.setInterval(() => {
    const busy = fields.some(field => deadlineSubmissions.has(field.form));
    if (!hasChanges() && !busy && !document.querySelector('dialog[open]')) window.location.reload();
  }, 600000);

  document.querySelector('[data-refresh-status]').addEventListener('click', (event) => {
    event.preventDefault();
    if (!hasChanges() || window.confirm('入力中の時刻を破棄して、利用状況を更新します。よろしいですか？')) {
      window.location.reload();
    }
  });
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

// Keep navigation available without JavaScript; collapse only after initialization.
document.addEventListener('DOMContentLoaded', () => {
  const toggle = document.querySelector('[data-navigation-toggle]');
  if (!toggle) return;
  const navigation = toggle.closest('nav');
  const menu = document.getElementById(toggle.getAttribute('aria-controls'));
  toggle.hidden = false;
  navigation.classList.add('navigation-ready');
  toggle.addEventListener('click', () => {
    const open = menu.classList.toggle('is-open');
    toggle.setAttribute('aria-expanded', String(open));
  });
  navigation.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && menu.classList.contains('is-open')) {
      menu.classList.remove('is-open');
      toggle.setAttribute('aria-expanded', 'false');
      toggle.focus();
    }
  });
});

// Submit only after reviewing the order; hidden inputs follow their rows in the DOM.
document.addEventListener('DOMContentLoaded', () => {
  const list = document.querySelector('[data-ordering-list]');
  if (!list) return;
  const notice = document.querySelector('[data-order-announcement]');
  const update = (row) => {
    const rows = Array.from(list.children);
    rows.forEach((entry, index) => {
      entry.querySelector('[data-order-move="up"]').disabled = index === 0;
      entry.querySelector('[data-order-move="down"]').disabled = index === rows.length - 1;
    });
    if (row) notice.textContent = `${row.querySelector('.order-name').textContent.trim()}を${rows.indexOf(row) + 1}番目に移動しました。保存して反映してください。`;
  };
  list.addEventListener('click', (event) => {
    const button = event.target.closest('[data-order-move]');
    if (!button) return;
    const row = button.closest('[data-ordering-row]');
    const neighbor = button.dataset.orderMove === 'up' ? row.previousElementSibling : row.nextElementSibling;
    if (!neighbor) return;
    if (button.dataset.orderMove === 'up') neighbor.before(row);
    else neighbor.after(row);
    update(row);
  });
  let dragged = null;
  list.addEventListener('dragstart', (event) => {
    if (!event.target.closest('.order-handle')) { event.preventDefault(); return; }
    dragged = event.target.closest('[data-ordering-row]');
    event.dataTransfer.setData('text/plain', dragged.dataset.recordId);
    event.dataTransfer.effectAllowed = 'move';
    dragged.classList.add('is-dragging');
  });
  list.addEventListener('dragover', (event) => {
    if (!dragged) return;
    event.preventDefault();
    const target = event.target.closest('[data-ordering-row]');
    if (!target || target === dragged) return;
    const bounds = target.getBoundingClientRect();
    if (event.clientY < bounds.top + bounds.height / 2) target.before(dragged);
    else target.after(dragged);
    update(dragged);
  });
  list.addEventListener('drop', (event) => { if (dragged) event.preventDefault(); });
  list.addEventListener('dragend', () => {
    dragged?.classList.remove('is-dragging');
    dragged = null;
  });
  update();
});
