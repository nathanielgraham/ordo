// tabs.js – Clean tab system
import {
  loadDoc,
  refreshSettings,
  showPricingModal,
  renderDashboard,
  startDashboardLiveTimer,
  stopDashboardLiveTimer,
  showLoginModal
} from "./ui-handlers.js";
import { startLiveTimings, stopLiveTimings } from "./tree/tree-table.js";
import { checkLoginAndConnect } from "./websocket.js";

// ==================== CORE ACTIVATION ====================
export function activateTab(tabId = null) {
  let targetTab = tabId;
  const hash = window.location.hash.replace("#", "").trim();

  if (!targetTab) {
    targetTab = hash
      ? hash.split("/")[0]
      : document.body.classList.contains("is-logged-in")
        ? "dashboard"
        : "docs";
  }

  console.log(`[ACTIVATE TAB] → "${targetTab}" (hash: ${hash})`);

  // Visual nav + content switch
  document
    .querySelectorAll(".nav-tab")
    .forEach((l) => l.classList.toggle("active", l.dataset.tab === targetTab));

  // Special handling for live tabs
  if (["monitor", "servers", "calendars"].includes(targetTab)) {
    startLiveTimings();
  } else {
    stopLiveTimings();
  }

  // ==================== DASHBOARD ====================
  if (targetTab === "dashboard") {
    renderDashboard();           // This now safely starts the timer internally
  } else {
    stopDashboardLiveTimer();
  }

  // Settings
  if (targetTab === "settings") {
    const loading = document.getElementById("settings-loading");
    const content = document.getElementById("settings-content");
    if (loading) loading.style.display = "none";
    if (content) content.style.display = "block";

    const isLoggedIn = document.body.classList.contains("is-logged-in");
    if (isLoggedIn) {
      refreshSettings();
    }
  }

  // Docs
  else if (targetTab === "docs") {
    const slug = hash.split("/")[1];
    const file = slug
      ? slug.endsWith(".md")
        ? slug
        : `${slug}.md`
      : "overview.md";
    setTimeout(() => loadDoc(file), 100);
  }

  // Content switch
  document
    .querySelectorAll(".tab-content")
    .forEach((el) => el.classList.remove("active"));

  const content = document.getElementById(targetTab);
  if (content) content.classList.add("active");

  // Subtab support
  const parts = hash.split("/");
  const subTab = parts[1];
  if (targetTab === "settings" && subTab) {
    setTimeout(() => {
      const subtabEl = document.querySelector(`[data-tab="${subTab}"]`);
      if (subtabEl) {
        subtabEl.click();
        console.log(`[Subtab] Activated: ${subTab}`);
      }
    }, 100);
  }
}

// ==================== CLICK HANDLER ====================
/*
function handleTabClick(e) {
  e.preventDefault();
  const tabId = e.currentTarget.dataset.tab;

  if (tabId === "pricing") {
    showPricingModal();
    return;
  }

  // Update URL hash
  if (tabId === "docs") {
    window.location.hash = "docs";
  } else {
    window.location.hash = tabId;   // e.g. #settings
  }

  activateTab(tabId);
}
*/

// Deep link handler - runs on initial page load and hash changes
function handleDeepLink() {
  const hash = window.location.hash.replace('#', '').trim();
  if (!hash) return;

  const parts = hash.split('/');
  const mainTab = parts[0];

  console.log(`[Deep Link] main="${mainTab}"`);

  if (mainTab === 'docs') {
    // Docs are public
    activateTab('docs');
    return;
  }

  // Protected routes
  const isLoggedIn = document.body.classList.contains("is-logged-in");

  if (!isLoggedIn) {
    console.log(`[Deep Link] Protected route "${mainTab}" → showing login`);
    showLoginModal(mainTab);   // Pass the intended tab if your modal supports return_to
    return;
  }

  // Logged in + protected route
  processDeepLink(hash);
}

// Helper for logged-in deep links
function processDeepLink(hash) {
  const parts = hash.split('/');
  const mainTab = parts[0];
  const subTabOrSlug = parts[1];

  activateTab(mainTab);

  if (mainTab === 'settings' && subTabOrSlug) {
    setTimeout(() => {
      const subtabEl = document.querySelector(`.internal-tab[data-tab="${subTabOrSlug}"]`);
      if (subtabEl) subtabEl.click();
    }, 100);
  }

  // Stripe success
  const params = new URLSearchParams(window.location.search);
  if (params.has('success')) {
    showToast('Payment successful! Welcome to Pro 🎉', 'success');
    history.replaceState(null, null, window.location.pathname + '#' + hash);
  }
}

// ==================== INIT TAB SYSTEM ====================
export function initTabSystem() {
  // Main tabs
  document.querySelectorAll(".nav-tab[data-tab]").forEach(link => {
    link.addEventListener("click", handleTabClick);
  });

  // Internal subtabs
  document.querySelectorAll(".internal-tab[data-tab]").forEach(tab => {
    tab.addEventListener("click", handleSubtabClick);
  });

  // Docs TOC links
  document.querySelectorAll('#docs-toc a[data-file]').forEach(link => {
    link.addEventListener('click', function() {
      const file = this.dataset.file;
      if (file) {
        const slug = file.replace('.md', '');
        window.location.hash = `docs/${slug}`;
      }
    });
  });

  // Initial deep link support
  handleDeepLink();
  window.addEventListener('hashchange', () => activateTab());
}

// Main tab click
function handleTabClick(e) {
  e.preventDefault();
  const tabId = e.currentTarget.dataset.tab;

  if (tabId === "pricing") {
    showPricingModal();
    return;
  }

  // Update URL hash
  if (tabId === "docs") {
    window.location.hash = "docs"; // default to overview
  } else {
    window.location.hash = tabId;
  }

  activateTab(tabId);
}

// Subtab click (e.g. Billing inside Settings)
function handleSubtabClick(e) {
  const subtabId = e.currentTarget.dataset.tab;
  const currentMainTab = window.location.hash.replace("#", "").split("/")[0];

  if (currentMainTab === "settings") {
    window.location.hash = `settings/${subtabId}`;
  }
  // Let your existing subtab logic run
}

/*

export function initTabSystem() {
  document.querySelectorAll(".nav-tab[data-tab]").forEach(link => {
    link.addEventListener("click", handleTabClick);
  });

  // Initial activation
  setTimeout(activateTab, 150);
}

*/
