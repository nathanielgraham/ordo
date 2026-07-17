// public/js/dropdown-handlers.js
import { appState } from "./state.js";
import {
  openClusterModal,
  openJobModal,
  openConfirmModal,
  openCalendarModal,
  openCronModal,
  openServerModal,
} from "./modals.js";
import { openDependencyGraph } from "./graph.js";
import { sendCommand, sendWS } from "./websocket.js";
import { showToast } from "./ui-handlers.js";
import { findServerById } from "./utils.js";

let cleanupAutoUpdate = null;

// ==================== DROPDOWN OPEN/CLOSE ====================
document.addEventListener("click", (e) => {
  const trigger = e.target.closest(".dropdown-trigger button");
  if (!trigger) return;
  e.stopPropagation();

  const dropdown = trigger.closest(".dropdown");
  if (!dropdown) return;

  const wasActive = dropdown.classList.contains("active");
  closeAllDropdowns();

  if (!wasActive) {
    dropdown.classList.add("active");
    positionMenu(dropdown);
  }
});

// Close on outside click
document.addEventListener("click", (e) => {
  if (!e.target.closest(".dropdown")) {
    closeAllDropdowns();
  }
});

// Escape key support
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    closeAllDropdowns();

    // Close modals too
    document.querySelectorAll(".app-modal.active").forEach((modal) => {
      modal.classList.remove("active");
      if (modal.id === "log-history-modal") {
        const body = modal.querySelector(".modal-body");
        if (body) body.innerHTML = "";
      }
      if (modal.id === "graph-modal" && window.cy) {
        window.cy.destroy();
        window.cy = null;
      }
    });
  }
});

// ==================== POSITIONING ====================
function positionMenu(dropdown) {
  const trigger = dropdown.querySelector("button");
  const menu = dropdown.querySelector(".dropdown-menu");
  if (!trigger || !menu) return;

  const rect = trigger.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  const showBelow = (vh - rect.bottom) > rect.top * 0.9;

  // Measure natural width
  menu.style.visibility = "hidden";
  menu.style.display = "block";
  const naturalWidth = menu.scrollWidth;
  menu.style.visibility = "visible";

  const widthPx = Math.max(180, Math.min(naturalWidth, 230));
  const widthRem = (widthPx / 16).toFixed(2);

  let left = rect.left;
  if (left + widthPx > vw - 8) left = vw - widthPx - 8;

  menu.style.position = "fixed";
  menu.style.left = `${left}px`;
  menu.style.width = `${widthRem}rem`;
  menu.style.zIndex = "10000";
  menu.style.overflowY = "auto";

  if (showBelow) {
    menu.style.top = `${rect.bottom + 6}px`;
    menu.style.bottom = "auto";
    menu.style.maxHeight = `${Math.min((vh - rect.bottom) * 0.88, vh * 0.72)}px`;
  } else {
    menu.style.bottom = `${vh - rect.top + 6}px`;
    menu.style.top = "auto";
    menu.style.maxHeight = `${Math.min(rect.top * 0.88, vh * 0.72)}px`;
  }
}

export function closeAllDropdowns() {
  document.querySelectorAll(".dropdown.active").forEach((d) => {
    d.classList.remove("active");
    const menu = d.querySelector(".dropdown-menu");
    if (menu) menu.style.display = "none";
    if (cleanupAutoUpdate) {
      cleanupAutoUpdate();
      cleanupAutoUpdate = null;
    }
  });
}

// ==================== TREE ACTIONS ====================
function handleTreeActionClick(e, actionItem, row, action) {
  const isCluster = row.classList.contains("ordo-cluster-row");
  const id = Number(row.dataset.id);
  const name = row.querySelector("td:first-child")?.textContent.trim().replace(/\/$/, "") || "";

  switch (action) {
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
      sendCommand("run", id, isCluster ? "cluster" : "job");
      break;

    case "kill":
      openConfirmModal(
        "Confirm Kill",
        `Kill ${name || "this item"}?`,
        () => sendCommand("kill", id, isCluster ? "cluster" : "job")
      );
      break;

    case "hold":
      sendCommand("hold", id, isCluster ? "cluster" : "job");
      showToast(`Holding ${isCluster ? "cluster" : "job"}...`, "info");
      break;

    case "release":
      sendCommand("release", id, isCluster ? "cluster" : "job");
      showToast(`Releasing ${isCluster ? "cluster" : "job"}...`, "info");
      break;

    case "ice":
    case "melt":
    case "complete":
    case "reset":
      sendCommand(action, id, isCluster ? "cluster" : "job");
      showToast(`${action.charAt(0).toUpperCase() + action.slice(1)}ing...`, "info");
      break;

    case "delete":
      openConfirmModal(
        "Confirm Delete",
        `Delete ${name || "this item"}?`,
        () => sendCommand("delete", id, isCluster ? "cluster" : "job")
      );
      break;

    case "view-log":
      if (!isCluster) sendWS({ command: "read_log", id });
      break;

    default:
      console.warn("Unhandled tree action:", action);
  }

  closeAllDropdowns();
}

// ==================== SERVER ACTIONS ====================
function handleServerActionClick(e, actionItem, row, action) {
  const serverId = Number(actionItem.dataset.id);
  if (!serverId) return showToast("Invalid server ID", "danger");

  const server = findServerById(serverId);

  switch (action) {
    case "edit-server":
      openServerModal("edit", server);
      break;
    case "delete-server":
      openConfirmModal(
        "Delete Server",
        `Delete "${server?.name || "this server"}"?`,
        () => sendWS({ command: "delete_monitor", id: serverId })
      );
      break;
    default:
      console.warn("Unhandled server action:", action);
  }
  closeAllDropdowns();
}

// ==================== CALENDAR ACTIONS ====================
function handleCalendarsActionClick(e, actionItem, row, action) {
  e.preventDefault();
  const isCalendarRow = row.classList.contains("ordo-calendar-row");
  const isCronRow = row.classList.contains("ordo-cron-row");
  let calId = actionItem.dataset.calId || actionItem.dataset.id;
  if (!calId && isCronRow) calId = row.dataset.parent;
  if (!calId && isCalendarRow) calId = row.dataset.id;
  let cronId = actionItem.dataset.cronId;
  calId = Number(calId);
  cronId = cronId ? Number(cronId) : null;
  if (isNaN(calId) || calId <= 0) {
    showToast("Invalid calendar ID", "danger");
    return;
  }
  const name = row.querySelector("td:first-child")?.textContent.trim() || "";
  switch (action) {
    case "edit-calendar":
      if (!isCalendarRow) return showToast("Invalid action for cron", "danger");
      openCalendarModal("edit", calId);
      break;
    case "delete-calendar":
      if (!isCalendarRow) return showToast("Invalid action for cron", "danger");
      openConfirmModal(
        "Confirm Delete Calendar",
        `Are you sure you want to delete calendar "${name}"?`,
        () => sendWS({ command: "delete_cal", id: calId }),
        () => showToast("Deletion cancelled", "info"),
      );
      break;
    case "add-cron":
      if (!isCalendarRow) return showToast("Invalid action for cron", "danger");
      openCronModal("create", calId);
      break;
    case "edit-cron":
      if (!isCronRow) return showToast("Invalid action for calendar", "danger");
      if (!cronId || isNaN(cronId))
        return showToast("Invalid cron ID", "danger");
      const cal = appState.calendarsData.find((c) => Number(c.id) === calId);
      const cron = cal?.crons?.find((cr) => Number(cr.id) === cronId);
      if (!cron) return showToast("Cron not found", "danger");
      openCronModal("edit", calId, cron);
      break;
    case "delete-cron":
      if (!isCronRow || !cronId || isNaN(cronId))
        return showToast("Invalid cron ID", "danger");
      openConfirmModal(
        "Confirm Delete Cron",
        `Are you sure you want to delete this cron expression?`,
        () => sendWS({ command: "delete_cron", id: cronId }),
        () => showToast("Deletion cancelled", "info"),
      );
      break;
    default:
      console.warn("Unhandled calendar action:", action);
  }
  closeAllDropdowns();
}

// ==================== MAIN DELEGATOR ====================
export function handleActionClick(e) {
  const actionItem = e.target.closest(".dropdown-item[data-action]");
  if (!actionItem) return;
  e.preventDefault();

  const row = actionItem.closest("tr");
  if (!row) return;

  const action = actionItem.dataset.action;

  if (row.closest("#tree-body")) {
    handleTreeActionClick(e, actionItem, row, action);
  } else if (row.closest("#servers-table, #servers-body")) {
    handleServerActionClick(e, actionItem, row, action);
  } else if (row.closest("#calendars-table, #calendars-body")) {
    handleCalendarsActionClick(e, actionItem, row, action);
  }
}

export function attachGlobalListeners() {
  if (document.body.dataset.globalListenersAttached === "true") return;
  document.body.dataset.globalListenersAttached = "true";
  document.addEventListener("click", handleActionClick);
}

