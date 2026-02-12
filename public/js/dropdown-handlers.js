import { appState } from "./state.js";
import {
  openAttachCalendarModal,
  openClusterModal,
  openJobModal,
  openConfirmModal,
  openCalendarModal,
  openCronsModal,
  openCronModal,
  openServerModal,
} from "./modals.js";
import { openDependencyGraph } from "./graph.js";
import { sendCommand, sendWS } from "./websocket.js";
import { showToast } from "./ui-handlers.js";
import { findClusterById, findServerById } from "./utils.js";

// Close all dropdowns
function closeAllDropdowns() {
  document.querySelectorAll(".dropdown-menu").forEach((menu) => {
    menu.style.display = "none";
  });
  document.querySelectorAll(".dropdown.active").forEach((dropdown) => {
    dropdown.classList.remove("active", "is-up", "is-forced-down");
  });
}

// Close all modals
function closeAllModals() {
  document.querySelectorAll(".app-modal.active").forEach((modal) => {
    modal.classList.remove("active");
    if (modal.id === "graph-modal" && window.cy) {
      window.cy.destroy();
      window.cy = null;
    }
  });
}

// Global outside-click handler
function handleGlobalClick(e) {
  const trigger = e.target.closest(".dropdown-trigger button");
  if (trigger) return;

  const closeTrigger = e.target.closest(".modal-backdrop, .close-btn");
  if (closeTrigger) {
    const modal = closeTrigger.closest(".app-modal");
    if (modal) {
      modal.classList.remove("active");
      if (modal.id === "graph-modal" && window.cy) {
        window.cy.destroy();
        window.cy = null;
      }
    }
    return;
  }

  closeAllDropdowns();
}

// Tree actions
function handleTreeActionClick(e, actionItem, row, action) {
  const isCluster = row.classList.contains("ordo-cluster-row");
  const type = isCluster ? "cluster" : "job";
  const id = Number(row.dataset.id);
  const name = row.querySelector("td:first-child")?.textContent.trim().replace(/\/$/, "") || "";

  switch (action) {
    case "attach-calendar":
      const node = findClusterById(appState.monitorData.tree, id);
      if (!node) return showToast("Cluster not found", "error");
      openAttachCalendarModal(id, name, node.cal_name || "", node.cal_id || null);
      break;
    case "edit-cluster":
      openClusterModal("edit", id);
      break;
    case "edit-job":
      openJobModal("edit", id);
      break;
    case "view-graph":
      openDependencyGraph(id, name);
      break;
    case "new-cluster":
      openClusterModal("create", null, id, name);
      break;
    case "new-job":
      openJobModal("create", null, id, name);
      break;
    case "run":
      sendCommand("run", id, type);
      showToast(`Starting ${type}...`, "info");
      break;
    case "kill":
      openConfirmModal(
        "Confirm Kill",
        `Are you sure you want to kill ${name || "this " + type}?`,
        () => {
          sendCommand("kill", id, type);
          showToast(`Killing ${type}...`, "warning");
        },
        () => showToast("Kill cancelled", "info")
      );
      break;
    case "hold":
      sendCommand("hold", id, type);
      showToast(`Holding ${type}...`, "info");
      break;
    case "release":
      sendCommand("release", id, type);
      showToast(`Releasing ${type}...`, "info");
      break;
    case "ice":
      sendCommand("ice", id, type);
      showToast(`Icing ${type}...`, "info");
      break;
    case "melt":
      sendCommand("melt", id, type);
      showToast(`Melting ${type}...`, "info");
      break;
    case "complete":
      sendCommand("complete", id, type);
      showToast(`Completing ${type}...`, "info");
      break;
    case "reset":
      sendCommand("reset", id, type);
      showToast(`Resetting ${type}...`, "info");
      break;
    case "delete":
      openConfirmModal(
        "Confirm Deletion",
        `Are you sure you want to delete ${name || "this " + type}?`,
        () => {
          sendCommand("delete", id, type);
          showToast(`${type.charAt(0).toUpperCase() + type.slice(1)} deleted`, "success");
        },
        () => showToast("Deletion cancelled", "info")
      );
      break;
    case "view-log":
      if (!isCluster) {
        const jobId = id;
        const modal = document.getElementById("log-modal");
        modal.dataset.jobId = jobId;
        modal.classList.add("active");
        if (appState.ws?.readyState === WebSocket.OPEN) {
          appState.ws.send(JSON.stringify({ command: "read_log", id: jobId }));
        }
      }
      break;
    default:
      console.warn("Unhandled tree action:", action);
  }
}

// Server actions
function handleServerActionClick(e, actionItem, row, action) {
  e.preventDefault();
  const serverId = Number(actionItem.dataset.id);
  if (isNaN(serverId) || serverId <= 0) return showToast("Invalid server ID", "danger");

  const server = findServerById(serverId);

  switch (action) {
    case "edit-server":
      openServerModal("edit", server);
      break;
    case "delete-server":
      openConfirmModal(
        "Confirm Delete Server",
        `Are you sure you want to delete server "${server?.name || "this server"}"?`,
        () => {
          sendWS({ command: "delete_monitor", id: serverId });
          showToast("Deleting server...", "warning");
        },
        () => showToast("Delete cancelled", "info")
      );
      break;
    default:
      console.warn("Unhandled server action:", action);
      showToast("Action not implemented", "warning");
  }
}

// Calendar actions
function handleCalendarsActionClick(e, actionItem, row, action) {
  const calendarId = Number(row.dataset.calId);
  const name = row.querySelector("td:first-child")?.textContent.trim() || "";

  if (isNaN(calendarId) || calendarId <= 0) {
    showToast("Invalid calendar ID", "danger");
    return;
  }

  switch (action) {
    case "edit-calendar":
      openCalendarModal("edit", calendarId);
      break;
    case "delete-calendar":
      openConfirmModal(
        "Confirm Delete Calendar",
        `Are you sure you want to delete calendar "${name || "this calendar"}"?`,
        () => {
          sendWS({ command: "delete_cal", id: calendarId });
          showToast("Calendar deleted", "success");
        },
        () => showToast("Deletion cancelled", "info")
      );
      break;
    case "view-crons":
      openCronsModal(calendarId);
      break;
    case "add-cron":
      openCronModal("create", calendarId);
      break;
    default:
      console.warn("Unhandled calendar action:", action);
  }
}

// Delegated action handler
function handleActionClick(e) {
  const actionItem = e.target.closest(".dropdown-item[data-action]");
  if (!actionItem) return;

  e.preventDefault();
  const dropdown = actionItem.closest(".dropdown");
  if (dropdown) dropdown.classList.remove("active", "is-up", "is-forced-down");

  const action = actionItem.dataset.action;
  const row = actionItem.closest("tr");
  if (!row) return;

  let handler = null;
  if (row.closest("#tree-body")) handler = handleTreeActionClick;
  else if (row.closest("#calendars-table, #calendars-body, #calendars-content")) handler = handleCalendarsActionClick;
  else if (row.closest("#servers-table, #servers-body, #servers-content")) handler = handleServerActionClick;

  if (handler) handler(e, actionItem, row, action);
}

// Escape key
function handleEscapeKey(e) {
  if (e.key === "Escape") {
    closeAllModals();
    closeAllDropdowns();
  }
}

// Dropdown positioning: prefer down, flip up if no space, fallback scrollable
function positionMenu(dropdown) {
  const trigger = dropdown.querySelector(".dropdown-trigger button");
  const menu = dropdown.querySelector(".dropdown-menu");
  if (!trigger || !menu) return;

  // Reset classes and styles
  dropdown.classList.remove("is-up", "is-forced-down");
  menu.style.maxHeight = "";
  menu.style.overflowY = "";

  // Force layout for accurate height
  void menu.offsetHeight;

  const triggerRect = trigger.getBoundingClientRect();
  const spaceBelow = window.innerHeight - triggerRect.bottom;
  const spaceAbove = triggerRect.top;
  const menuHeight = menu.offsetHeight + 40; // buffer

  if (spaceBelow >= menuHeight) {
    // Enough space below — default down (CSS handles)
    return;
  } else if (spaceAbove >= menuHeight) {
    // Flip up
    dropdown.classList.add("is-up");
  } else {
    // No good space — side with more room + scrollable
    if (spaceBelow > spaceAbove) {
      dropdown.classList.add("is-forced-down");
    } else {
      dropdown.classList.add("is-up");
    }
    menu.style.maxHeight = "60vh";
    menu.style.overflowY = "auto";
  }
}

// Re-exported for compatibility with other modules
export function setupDropdownFlip() {
  // The flip logic is now handled in the trigger handler and scroll/resize listeners below
  // This function is kept for backward compatibility with imports in other files
}

// Global listeners
export function attachGlobalListeners() {
  if (document.body.dataset.globalListenersAttached === "true") return;
  document.body.dataset.globalListenersAttached = "true";

  document.addEventListener("click", handleGlobalClick, { capture: true });
  document.addEventListener("click", handleActionClick);
  document.addEventListener("keydown", handleEscapeKey);

  // Dropdown trigger handler
  document.addEventListener("click", (e) => {
    const trigger = e.target.closest(".dropdown-trigger button");
    if (!trigger) return;

    e.stopPropagation();
    const dropdown = trigger.closest(".dropdown");
    if (!dropdown) return;

    const menu = dropdown.querySelector(".dropdown-menu");
    if (!menu) return;

    const isActive = dropdown.classList.contains("active");

    // Close others
    document.querySelectorAll(".dropdown.active").forEach((d) => {
      if (d !== dropdown) {
        d.classList.remove("active", "is-up", "is-forced-down");
        const m = d.querySelector(".dropdown-menu");
        if (m) m.style.display = "none";
      }
    });

    if (isActive) {
      dropdown.classList.remove("active", "is-up", "is-forced-down");
      menu.style.display = "none";
    } else {
      dropdown.classList.add("active");
      menu.style.display = "block";
      positionMenu(dropdown);
    }
  });

  // Recalculate on scroll/resize
  window.addEventListener("scroll", () => {
    document.querySelectorAll(".dropdown.active").forEach(positionMenu);
  }, true);
  window.addEventListener("resize", () => {
    document.querySelectorAll(".dropdown.active").forEach(positionMenu);
  });

  // Modal close buttons
  document.querySelectorAll(".close-btn[data-dismiss], .btn[data-dismiss]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const modalId = btn.dataset.dismiss;
      const modal = document.getElementById(modalId);
      if (modal) {
        modal.classList.remove("active");
        closeAllDropdowns();
      }
    });
  });
}
