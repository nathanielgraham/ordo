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

let cleanupAutoUpdate = null;

// ==================== OPEN / CLOSE ====================

document.addEventListener("click", (e) => {
  const trigger = e.target.closest(".dropdown-trigger button");
  if (!trigger) return;

  e.stopPropagation();

  const dropdown = trigger.closest(".dropdown");
  if (!dropdown) return;

  const isActive = dropdown.classList.contains("active");

  closeAllDropdowns();

  if (!isActive) {
    dropdown.classList.add("active");
    positionMenu(dropdown);
  }
});

// Global outside click close
document.addEventListener("click", (e) => {
  if (e.target.closest(".dropdown-trigger button")) return;
  if (e.target.closest(".dropdown-menu")) return;

  closeAllDropdowns();
});

// Escape key — closes ALL dropdowns AND ALL modals
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    // Close all dropdowns
    closeAllDropdowns();

    // Close all active modals
    document.querySelectorAll(".app-modal.active").forEach((modal) => {
      modal.classList.remove("active");

      // Special cleanup
      if (modal.id === "log-history-modal") {
        const logBody = modal.querySelector(".modal-body");
        if (logBody) logBody.innerHTML = "";
      }

      if (modal.id === "graph-modal" && window.cy) {
        window.cy.destroy();
        window.cy = null;
      }
    });
  }
});


// ==================== POSITIONING LOGIC ====================
// ==================== POSITIONING LOGIC ====================
function positionMenu(dropdown) {
  const trigger = dropdown.querySelector("button");
  const menu = dropdown.querySelector(".dropdown-menu");
  if (!trigger || !menu) return;

  const rect = trigger.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  const spaceAbove = rect.top;
  const spaceBelow = viewportHeight - rect.bottom;

  // Vertical positioning (prefer bottom)
  const showBelow = spaceBelow > spaceAbove * 0.9;

  // === Dynamic Width (in rem) ===
  menu.style.visibility = "hidden";
  menu.style.display = "block";
  const naturalWidth = menu.scrollWidth;
  menu.style.visibility = "visible";

  // Convert to rem (assuming 1rem = 16px base)
  const finalWidthPx = Math.max(180, Math.min(naturalWidth, 230));
  const finalWidthRem = (finalWidthPx / 16).toFixed(2);

  // === Horizontal positioning ===
  let leftPos = rect.left;
  //const rightMarginRem = 1.25; // 20px

  if (leftPos + finalWidthPx > viewportWidth - 5) {
    leftPos = viewportWidth - finalWidthPx - 5;
  }

  // Apply positioning using rem where possible
  menu.style.position = "fixed";
  menu.style.left = `${leftPos}px`;           // left needs px for precision
  menu.style.width = `${finalWidthRem}rem`;
  menu.style.overflowY = "auto";
  menu.style.zIndex = "10000";

  if (showBelow) {
    menu.style.top = `${rect.bottom + 6}px`;   // small gap in px for precision
    menu.style.bottom = "auto";
    menu.style.maxHeight = `${Math.min(spaceBelow * 0.88, viewportHeight * 0.72)}px`;
  } else {
    menu.style.bottom = `${viewportHeight - rect.top + 6}px`;
    menu.style.top = "auto";
    menu.style.maxHeight = `${Math.min(spaceAbove * 0.88, viewportHeight * 0.72)}px`;
  }

  dropdown.classList.add("active");
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

// ==================== ACTION HANDLERS ====================

function handleTreeActionClick(e, actionItem, row, action) {
  const isCluster = row.classList.contains("ordo-cluster-row");
  const type = isCluster ? "cluster" : "job";
  const id = Number(row.dataset.id);
  const name =
    row
      .querySelector("td:first-child")
      ?.textContent.trim()
      .replace(/\/$/, "") || "";

  switch (action) {
    case "attach-calendar":
      const node = findClusterById(appState.monitorData.tree, id);
      if (!node) return showToast("Cluster not found", "error");
      openAttachCalendarModal(
        id,
        name,
        node.cal_name || "",
        node.cal_id || null,
      );
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
        () => sendCommand("kill", id, type),
        () => showToast("Kill cancelled", "info"),
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
        () => sendCommand("delete", id, type),
        () => showToast("Deletion cancelled", "info"),
      );
      break;

    case "view-log":
      if (isCluster) {
        console.warn("View Log called on a cluster — not supported");
        break;
      }

      const jobId = id;
      if (!jobId) {
        showToast("No job ID found", "danger");
        break;
      }

      const modal = document.getElementById("log-modal");
      if (modal) {
        modal.dataset.jobId = jobId;
        modal.classList.add("active");
      }

      if (appState.ws?.readyState === WebSocket.OPEN) {
          const rl = JSON.stringify({
            command: "read_log",
            id: jobId,
          });
        console.log("READLOG", rl);
        appState.ws.send(
	  rl
        );
      } else {
        showToast("Not connected to server", "danger");
      }
      break;

    default:
      console.warn("Unhandled tree action:", action);
  }
  closeAllDropdowns();
}

function handleServerActionClick(e, actionItem, row, action) {
  e.preventDefault();
  const serverId = Number(actionItem.dataset.id);
  if (isNaN(serverId) || serverId <= 0)
    return showToast("Invalid server ID", "danger");
  const server = findServerById(serverId);
  switch (action) {
    case "edit-server":
      openServerModal("edit", server);
      break;
    case "delete-server":
      openConfirmModal(
        "Confirm Delete Server",
        `Are you sure you want to delete server "${server?.name || "this server"}"?`,
        () => sendWS({ command: "delete_monitor", id: serverId }),
        () => showToast("Delete cancelled", "info"),
      );
      break;
    default:
      console.warn("Unhandled server action:", action);
  }
  closeAllDropdowns();
}

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

// Delegated action handler
export function handleActionClick(e) {
  const actionItem = e.target.closest(".dropdown-item[data-action]");
  if (!actionItem) return;
  e.preventDefault();
  const action = actionItem.dataset.action;
  const row = actionItem.closest("tr");
  if (!row) return;

  let handler = null;
  if (row.closest("#tree-body")) handler = handleTreeActionClick;
  else if (row.closest("#calendars-table, #calendars-body, #calendars-content"))
    handler = handleCalendarsActionClick;
  else if (row.closest("#servers-table, #servers-body, #servers-content"))
    handler = handleServerActionClick;

  if (handler) handler(e, actionItem, row, action);
}

export function attachGlobalListeners() {
  if (document.body.dataset.globalListenersAttached === "true") return;
  document.body.dataset.globalListenersAttached = "true";

  document.addEventListener("click", handleActionClick);
}
