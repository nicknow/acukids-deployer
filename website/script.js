const menuButton = document.querySelector('.menu-button');
const navigation = document.querySelector('#site-nav');

menuButton?.addEventListener('click', () => {
  const open = menuButton.getAttribute('aria-expanded') === 'true';
  menuButton.setAttribute('aria-expanded', String(!open));
  menuButton.querySelector('.sr-only').textContent = open ? 'Open navigation' : 'Close navigation';
  navigation.classList.toggle('open', !open);
});

navigation?.addEventListener('click', (event) => {
  if (event.target.closest('a') && menuButton) {
    navigation.classList.remove('open');
    menuButton.setAttribute('aria-expanded', 'false');
    menuButton.querySelector('.sr-only').textContent = 'Open navigation';
  }
});

document.querySelector('[data-copy]')?.addEventListener('click', async (event) => {
  const button = event.currentTarget;
  const command = document.getElementById(button.dataset.copy)?.textContent.trim();
  const status = document.getElementById('copy-status');
  try {
    await navigator.clipboard.writeText(command);
    button.textContent = '✓ Copied!';
    status.textContent = 'Command copied to your clipboard.';
  } catch {
    status.textContent = 'Select the command above and copy it manually.';
  }
  window.setTimeout(() => {
    button.innerHTML = '<span aria-hidden="true">▣</span> Copy command';
    status.textContent = '';
  }, 3000);
});
