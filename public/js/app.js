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
