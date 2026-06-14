// app.js – Main entry point & orchestration
import { validateCollapsedStorage } from "./state.js";
import { initTabSystem, activateTab } from "./tabs.js";
import { checkLoginAndConnect } from "./websocket.js";
import { attachTreeListeners } from "./tree/tree-listeners.js";
import { attachGlobalListeners } from "./dropdown-handlers.js";
import { initModals, attachCalendarsTreeListeners } from "./ui-handlers.js";

// ==================== MAIN INITIALIZATION ====================
document.addEventListener("DOMContentLoaded", () => {
  console.log("DOM ready");

  validateCollapsedStorage();
  attachCalendarsTreeListeners();
  attachTreeListeners();
  attachGlobalListeners();
  checkLoginAndConnect();
  initModals();

  // Initial activation with small delay for DOM readiness
  initTabSystem();
  initPricingModalLink();
  initLoginModal();
  window.addEventListener("hashchange", () => activateTab());

});

// Direct listener for Private & Enterprise link
function initPricingModalLink() {
  const link = document.getElementById('view-private-options');
  if (!link) return;

  link.addEventListener('click', function(e) {
    // Optional: allow the navigation to happen
    const modal = document.getElementById('pricing-modal');
    if (modal) {
      modal.classList.remove('active');
    }
  });
}

export function initLoginModal() {
  const form = document.getElementById('login-form');
  if (!form) return;

  form.addEventListener('submit', async function(e) {
    e.preventDefault();

    const btn = document.getElementById('send-magic-link-btn');
    const originalText = btn.textContent;

    const formContainer = document.getElementById('login-form-container');
    const successContainer = document.getElementById('login-success');
    const errorContainer = document.getElementById('login-error');
    const errorText = document.getElementById('login-error-text');

    // Reset states
    successContainer.style.display = 'none';
    errorContainer.style.display = 'none';

    // Checkbox enforcement
    if (!document.getElementById('agree-terms').checked) {
      errorText.textContent = 'You must agree to the Terms of Service and Privacy Policy';
      errorContainer.style.display = 'block';
      return;
    }

    btn.disabled = true;
    btn.textContent = 'Sending...';

    try {
      const response = await fetch('/login', {
        method: 'POST',
        body: new FormData(this)
      });

      const result = await response.json();

      if (result.success) {
        formContainer.style.display = 'none';
        successContainer.style.display = 'block';
      } else {
        errorText.textContent = result.message || 'Failed to send magic link';
        errorContainer.style.display = 'block';
      }
    } catch (err) {
      console.error(err);
      errorText.textContent = 'Network error. Please try again.';
      errorContainer.style.display = 'block';
    } finally {
      btn.disabled = false;
      btn.textContent = originalText;
    }
  });
}
