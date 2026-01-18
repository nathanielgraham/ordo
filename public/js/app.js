// app.js – minimal entry point & orchestration

import { appState, updateCollapsedClusters } from "./state.js";
import { attachTabListeners, activateDefaultTab } from "./tabs.js";
import { connectWS } from "./websocket.js";
import { attachTreeTableListeners, startTreeTimings } from "./tree-table.js";

function closeAllDropdowns() {
  document.querySelectorAll("#tree-body .dropdown.is-active").forEach((d) => {
    d.classList.remove("is-active", "is-up");
  });
}

function checkLoginAndConnect() {
  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];
  if (token) {
    document.body.classList.add("is-logged-in");
    console.log("DEBUG: Logged IN");
    connectWS(token);
  } else {
    document.body.classList.remove("is-logged-in");
    console.log("DEBUG: Logged OUT");
  }
  activateDefaultTab();
}

document.addEventListener("DOMContentLoaded", () => {
  console.log("DOM ready");

  // 1. Attach feature listeners (add more as you extract files)
  attachTabListeners();
  attachTreeTableListeners();
  startTreeTimings(); // start timer when tree loads

  // attachTreeTableListeners();  // ← add later
  // attachModalListeners();      // ← add later

  /*
  // 2. Global close listeners (keep here – app-wide)
  document.addEventListener("click", (e) => {
    if (e.target.closest(".modal .delete, .modal-background")) {
      e.target.closest(".modal").classList.remove("is-active");
    }
    if (!e.target.closest(".dropdown")) {
      closeAllDropdowns();
    }
  });

*/

  document.addEventListener("click", (e) => {
    // 1. Handle modal close (background or X button)
    const closeTrigger = e.target.closest(".modal .delete, .modal-background");
    if (closeTrigger) {
      const modal = closeTrigger.closest(".modal");
      if (modal) {
        console.log("Closing modal:", modal.id); // debug
        modal.classList.remove("is-active");

        // Graph modal cleanup
        if (modal.id === "graph-modal" && window.cy) {
          window.cy.destroy();
          window.cy = null;
        }
      }
      // Optional: stop propagation if needed
      // e.stopPropagation();
      // return; // uncomment if you want to prevent dropdown close after modal close
    }

    // 2. Close all dropdowns if click is outside ANY dropdown
    const clickedInsideDropdown = !!e.target.closest(".dropdown");
    if (!clickedInsideDropdown) {
      console.log("Click outside dropdown → closing all"); // debug
      closeAllDropdowns();
    }

    // 3. Close the parent dropdown if a menu item was clicked
    const clickedItem = e.target.closest(".dropdown-item");
    if (clickedItem) {
      const dropdown = clickedItem.closest(".dropdown");
      if (dropdown) {
        console.log("Menu item clicked → closing dropdown"); // debug
        dropdown.classList.remove("is-active");
        dropdown.classList.remove("is-up"); // reset flip
      }
    }
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document
        .querySelectorAll(".modal.is-active")
        .forEach((m) => m.classList.remove("is-active"));
      closeAllDropdowns();
    }
  });

  // 3. Startup
  checkLoginAndConnect();

  // 4. Simple global live clock (keep minimal here)
  setInterval(() => {
    document.getElementById("current-time").textContent =
      new Date().toLocaleString();
  }, 1000);
});
