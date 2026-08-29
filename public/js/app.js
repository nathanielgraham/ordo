// app.js – Main entry point & orchestration
import "./job-templates.js";
import { appState, validateCollapsedStorage } from "./state.js";
import { initTabSystem, activateTab } from "./tabs.js";
import { checkLoginAndConnect } from "./websocket.js";
import { attachTreeListeners } from "./tree/tree-listeners.js";
import { attachGlobalListeners } from "./dropdown-handlers.js";
import { initModals, attachCalendarsTreeListeners } from "./ui-handlers.js";

// ==================== DEVELOPMENT AUTO-LOGIN (DIRECT COOKIE) ====================
const ENABLE_DEV_AUTO_LOGIN = false;

if (ENABLE_DEV_AUTO_LOGIN) {
  const devToken = "15c8bfdbe8634255f8257ef73a8f0bf7daae1d8c";
  
  // Set the cookie
  document.cookie = `ordo_token=${devToken}; path=/; max-age=86400; SameSite=Strict`;
  
  console.log("%c[DEV] Auto-login cookie set with token: " + devToken, 
              "color: #0f0; font-weight: bold");
  
}

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
  initInviteModal();
  // window.addEventListener("hashchange", () => activateTab());
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

// ==================== LOGIN MODAL ====================
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
    if (!document.getElementById('agree-terms')?.checked) {
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
      console.error('Login error:', err);
      errorText.textContent = 'Network error. Please try again.';
      errorContainer.style.display = 'block';
    } finally {
      btn.disabled = false;
      btn.textContent = originalText;
    }
  });
}

// ==================== INVITE MODAL ====================
export function initInviteModal() {
  const modal = document.getElementById('invite-modal');
  if (!modal) return;

  const form = document.getElementById('invite-form');
  const formContainer = document.getElementById('invite-form-container');
  const successContainer = document.getElementById('invite-success');
  const errorContainer = document.getElementById('invite-error');
  const emailInput = document.getElementById('invite-email');

  function resetInviteModal() {
    formContainer.style.display = 'block';
    successContainer.style.display = 'none';
    errorContainer.style.display = 'none';
    if (emailInput) emailInput.value = '';
  }

  form?.addEventListener('submit', async function(e) {
    e.preventDefault();

    const btn = document.getElementById('send-invite-btn');
    const originalText = btn.textContent;
    const inviteeEmail = emailInput.value.trim();

    if (!inviteeEmail) {
      document.getElementById('invite-error-text').textContent = 'Please enter an email address';
      errorContainer.style.display = 'block';
      return;
    }

    successContainer.style.display = 'none';
    errorContainer.style.display = 'none';

    btn.disabled = true;
    btn.textContent = 'Sending...';

    try {
      // Get token from appState (preferred) or cookie fallback
      const token = appState.accountData?.token || 
                    document.cookie.split('; ').find(row => row.startsWith('ordo_token='))?.split('=')[1];

      console.log("🔑 Invite attempt - Token present:", !!token);

      if (!token) {
        document.getElementById('invite-error-text').textContent = 'You must be logged in to send invites';
        errorContainer.style.display = 'block';
        return;
      }

      const response = await fetch('/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          command: "register_user",
          email: inviteeEmail,
          team_member: 1,
          token: token
        })
      });

      const result = await response.json();
      console.log("📥 Invite response:", result);

      if (result.success) {
        formContainer.style.display = 'none';
        successContainer.style.display = 'block';
        document.getElementById('invite-success-text').textContent = 
          `Invitation sent to ${inviteeEmail}`;
        //showToast("Invitation sent successfully", "success");
      } else {
        document.getElementById('invite-error-text').textContent = 
          result.message || 'Failed to send invitation';
        errorContainer.style.display = 'block';
      }
    } catch (err) {
      console.error('Invite error:', err);
      document.getElementById('invite-error-text').textContent = 
        'Network error. Please try again.';
      errorContainer.style.display = 'block';
    } finally {
      btn.disabled = false;
      btn.textContent = originalText;
    }
  });

  // Reset modal when opened
  new MutationObserver(() => {
    if (modal.classList.contains('active')) {
      resetInviteModal();
    }
  }).observe(modal, { 
    attributes: true, 
    attributeFilter: ['class'] 
  });
}
