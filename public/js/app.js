// app.js – minimal entry point & orchestration
import { validateCollapsedStorage } from "./state.js";
import { attachTabListeners, activateDefaultTab } from "./tabs.js";
import { checkLoginAndConnect } from "./websocket.js";
import { attachTreeListeners } from "./tree/tree-listeners.js"; // ← correct
import { startLiveTimings } from "./tree/tree-table.js"; // keep if timings here
import { attachGlobalListeners } from "./dropdown-handlers.js";

document.addEventListener("DOMContentLoaded", () => {
  console.log("DOM ready");

  validateCollapsedStorage();

  attachTabListeners();
  attachTreeListeners(); // tree-specific clicks
  startLiveTimings();

  attachGlobalListeners(); // global dropdown/modal/esc/outside

  checkLoginAndConnect();
  activateDefaultTab();

  setInterval(() => {
    const timeEl = document.getElementById("current-time");
    if (timeEl) {
      timeEl.textContent = new Date().toLocaleString();
    }
  }, 1000);
});
