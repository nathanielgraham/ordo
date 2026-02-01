// tree/tree-listeners.js
import { appState, updateCollapsedClusters } from "../state.js";

export function attachTreeListeners() {
  const treeBody = document.getElementById("tree-body");
  if (!treeBody) return;

  treeBody.addEventListener("click", (e) => {
    // Toggle collapse/expand
    const toggle = e.target.closest(".ordo-toggle");
    if (toggle) {
      const row = toggle.closest("tr");
      const clusterId = row.dataset.id;
      const isCollapsed = row.classList.toggle("collapsed");

      if (isCollapsed) {
        appState.collapsedClusters.add(clusterId);
      } else {
        appState.collapsedClusters.delete(clusterId);
      }
      updateCollapsedClusters();
      toggleSubtree(clusterId, isCollapsed);
      row.setAttribute("aria-expanded", (!isCollapsed).toString());
      if (!isCollapsed) forceExpandDescendants(clusterId);
      return;
    }

    // Dropdown trigger (open/close only)

/*
    const trigger = e.target.closest(".dropdown-trigger button");
    if (trigger) {
      const dropdown = trigger.closest(".dropdown");
      const menu = dropdown.querySelector(".dropdown-menu");
      const willOpen = menu.style.display !== "block";

      console.log(
        "[DEBUG] Trigger clicked – willOpen:",
        willOpen,
        "current display:",
        menu.style.display,
      );

      // Close other menus
      document.querySelectorAll(".dropdown-menu").forEach((m) => {
        if (m !== menu) m.style.display = "none";
      });

      // Toggle visibility directly
      menu.style.display = willOpen ? "block" : "none";

      if (willOpen) {
        menu.offsetHeight; // reflow
        const rect = trigger.getBoundingClientRect();
        const spaceBelow = window.innerHeight - rect.bottom;
        const menuHeight = menu.offsetHeight || 200;
        if (spaceBelow < menuHeight + 30) {
          dropdown.classList.add("is-up");
        } else {
          dropdown.classList.remove("is-up");
        }
      }

      // Optional: still toggle .active for styling
      dropdown.classList.toggle("active", willOpen);

      return;
    }

*/
  });
}

// tree/tree-listeners.js (add these at the bottom)

export function toggleSubtree(parentId, hide) {
  const children = document.querySelectorAll(`tr[data-parent="${parentId}"]`);
  children.forEach((child) => {
    child.dataset.hidden = hide ? "true" : "false";
    child.style.display = hide ? "none" : "";
    if (child.classList.contains("ordo-cluster-row")) {
      toggleSubtree(child.dataset.id, hide);
    }
  });
}

export function forceExpandDescendants(startId) {
  const children = document.querySelectorAll(`tr[data-parent="${startId}"]`);
  children.forEach((childRow) => {
    if (childRow.classList.contains("ordo-cluster-row")) {
      childRow.classList.remove("collapsed");
      forceExpandDescendants(childRow.dataset.id);
    }
  });
}
