// app.js – Main entry point & orchestration
import { validateCollapsedStorage } from "./state.js";
import { attachTabListeners, activateTab } from "./tabs.js";
import { checkLoginAndConnect } from "./websocket.js";
import { attachTreeListeners } from "./tree/tree-listeners.js";
import { attachGlobalListeners } from "./dropdown-handlers.js";
import { initModals, attachCalendarsTreeListeners } from "./ui-handlers.js";

// ==================== HASH NAVIGATION ====================
function activateFromHash() {
  activateTab();
}

// ==================== MAIN INITIALIZATION ====================
document.addEventListener("DOMContentLoaded", () => {
  console.log("DOM ready");

  validateCollapsedStorage();

  // Core setup
  attachCalendarsTreeListeners();
  attachTabListeners();
  attachTreeListeners();
  attachGlobalListeners();
  checkLoginAndConnect();
  initModals();

  // === HASH / TAB ACTIVATION ===
  activateFromHash();                    // immediate
  setTimeout(activateFromHash, 400);     // after initial render

  // Listen for manual URL changes
  window.addEventListener("hashchange", activateFromHash);

  // Scroll to top after navigation (fixes dashboard scroll issue)
  setTimeout(() => {
    window.scrollTo({ top: 0, behavior: 'instant' });
  }, 500);

  // Navbar scroll shadow effect
  window.addEventListener("scroll", () => {
    document.body.classList.toggle("scrolled", window.scrollY > 20);
  });
});
