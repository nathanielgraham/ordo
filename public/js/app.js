// app.js – minimal entry point & orchestration
import { appState, updateCollapsedClusters, validateCollapsedStorage } from "./state.js";
import { attachTabListeners, activateDefaultTab } from "./tabs.js";
import { checkLoginAndConnect } from "./websocket.js";
import { attachTreeTableListeners, startTreeTimings } from "./tree-table.js";

function closeAllDropdowns() {
  document.querySelectorAll("#tree-body .dropdown.active").forEach((d) => {
    d.classList.remove("active", "is-up");
  });
}

document.addEventListener("DOMContentLoaded", () => {
  console.log("DOM ready");

  validateCollapsedStorage();

  // 1. Attach feature listeners
  attachTabListeners();
  attachTreeTableListeners();
  startTreeTimings(); // start timer when tree loads

  // 2. Global close listeners
  document.addEventListener("click", (e) => {
    // Close modals
    const closeTrigger = e.target.closest(".modal-backdrop, .close-btn");
    if (closeTrigger) {
      const modal = closeTrigger.closest(".app-modal");
      if (modal) {
        console.log("Closing modal:", modal.id);
        modal.classList.remove("active");
        // Graph modal cleanup
        if (modal.id === "graph-modal" && window.cy) {
          window.cy.destroy();
          window.cy = null;
        }
      }
    }

    // Close dropdowns if click is outside ANY dropdown
    const clickedInsideDropdown = !!e.target.closest(".dropdown");
    if (!clickedInsideDropdown) {
      console.log("Click outside dropdown → closing all");
      closeAllDropdowns();
    }

    // Close dropdown on menu item click
    const clickedItem = e.target.closest(".dropdown-item");
    if (clickedItem) {
      const dropdown = clickedItem.closest(".dropdown");
      if (dropdown) {
        console.log("Menu item clicked → closing dropdown");
        dropdown.classList.remove("active");
        dropdown.classList.remove("is-up");
      }
    }
  });

  // Esc key closes modals and dropdowns
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document
        .querySelectorAll(".app-modal.active")
        .forEach((m) => m.classList.remove("active"));
      closeAllDropdowns();
    }
  });

  // 3. Startup
  checkLoginAndConnect();
  activateDefaultTab();

  // 4. Simple global live clock
  setInterval(() => {
    document.getElementById("current-time").textContent =
      new Date().toLocaleString();
  }, 1000);
});
