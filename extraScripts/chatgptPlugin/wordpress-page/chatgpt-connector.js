(() => {
  'use strict';

  document.querySelectorAll('.hx-chatgpt-copy[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const text = button.getAttribute('data-copy') || '';
      const status = button.parentElement?.nextElementSibling;
      try {
        if (navigator.clipboard && window.isSecureContext) {
          await navigator.clipboard.writeText(text);
        } else {
          const input = document.createElement('textarea');
          input.value = text;
          input.setAttribute('readonly', '');
          input.style.position = 'fixed';
          input.style.opacity = '0';
          document.body.appendChild(input);
          input.select();
          const copied = document.execCommand('copy');
          input.remove();
          if (!copied) throw new Error('copy failed');
        }
        button.textContent = 'کپی شد';
        if (status) status.textContent = 'نشانی سرور کپی شد.';
      } catch (_) {
        button.textContent = 'انتخاب کنید';
        if (status) status.textContent = 'نشانی را انتخاب و کپی کنید.';
      }
      window.setTimeout(() => {
        button.textContent = 'کپی';
        if (status) status.textContent = '';
      }, 2200);
    });
  });
})();
