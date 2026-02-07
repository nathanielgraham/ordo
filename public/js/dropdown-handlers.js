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
import {
  showToast,
} from "./ui-handlers.js";
import { findClusterById, findServerById } from "./utils.js";

// Close all dropdowns (with debug logging)
function closeAllDropdowns() {
  console.log("[DEBUG] closeAllDropdowns called");

  // Hide all open menus directly (more reliable than class check)
  document.querySelectorAll(".dropdown-menu").forEach((menu) => {
    if (menu.style.display === "block") {
      console.log("[DEBUG] Forcing hide visible menu:", menu);
      menu.style.display = "none";
    }
  });

  // Still remove .active for consistency
  document.querySelectorAll(".dropdown.active").forEach((dropdown) => {
    dropdown.classList.remove("active", "is-up");
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

// Global outside-click handler (detects clicks outside dropdowns/modals)
function handleGlobalClick(e) {
  // Log every global click (comment out after debugging)
  console.log(
    "[DEBUG] Global click fired – target:",
    e.target.tagName,
    e.target.className,
  );

  // 1. Modal backdrop or close button
  const closeTrigger = e.target.closest(".modal-backdrop, .close-btn");
  if (closeTrigger) {
    const modal = closeTrigger.closest(".app-modal");
    if (modal) {
      console.log(
        "[DEBUG] Modal close trigger clicked – closing modal:",
        modal.id,
      );
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

function handleTreeActionClick(e, actionItem, row, action) {
  const isCluster = row.classList.contains("ordo-cluster-row");
  const type = isCluster ? "cluster" : "job";
  const id = Number(row.dataset.id);
  const name =
    row
      .querySelector("td:first-child")
      ?.textContent.trim()
      .replace(/\/$/, "") || "";

  console.log(
    "[DEBUG] Tree action:",
    action,
    "type:",
    type,
    "id:",
    id,
    "name:",
    name,
  );

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
        () => {
          sendCommand("kill", id, type);
          showToast(`Killing ${type}...`, "warning");
        },
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
        () => {
          sendCommand("delete", id, type);
          showToast(
            `${type.charAt(0).toUpperCase() + type.slice(1)} deleted`,
            "success",
          );
        },
        () => showToast("Deletion cancelled", "info"),
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

// Dedicated handler for Servers tab actions
function handleServerActionClick(e, actionItem, row, action) {
  e.preventDefault();
  const serverId = Number(actionItem.dataset.id);
  if (isNaN(serverId) || serverId <= 0) {
    return showToast("Invalid server ID", "danger");
  }

  const server = findServerById(serverId);
  if (!server && action !== "delete-server") { // delete may not need full object
    return showToast("Server not found in local data", "warning");
  }

  console.log("[DEBUG] Server action:", action, "serverId:", serverId, "name:", server?.name);

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

    // Future actions (expand later)
    case "restart-server":
      sendWS({ command: "restart_monitor", id: serverId }); // placeholder command
      showToast("Restarting monitor...", "info");
      break;

    case "view-details":
      // Future: open details modal or expand row
      showToast("Server details view coming soon", "info");
      break;

    default:
      console.warn("[DEBUG] Unhandled server action:", action);
      showToast("Action not implemented", "warning");
  }
}




function handleCalendarsActionClick(e, actionItem, row, action) {
  // Extract IDs once at the top — safe and consistent
  const calendarId = Number(row.dataset.calId);
  //const calendarId = Number(actionItem.dataset.calId);
  const cronId = Number(actionItem.dataset.cronId); // ← declare HERE (from clicked <a>)
  const name = row.querySelector("td:first-child")?.textContent.trim() || "";

  console.log(
    "[DEBUG] Calendars action:",
    action,
    "calendarId:",
    calendarId,
    "cronId:",
    cronId,
    "name:",
    name,
  );

  // Optional early guard for any calendar/cron action
  if (action.startsWith("calendar-") || action.startsWith("cron-")) {
    if (isNaN(calendarId) || calendarId <= 0) {
      showToast("Invalid calendar ID", "danger");
      return;
    }
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
        () => showToast("Deletion cancelled", "info"),
      );
      break;

    case "view-crons":
      console.log("[DEBUG] View crons clicked – calendarId:", calendarId);
      if (isNaN(calendarId) || calendarId <= 0) {
        showToast("Invalid calendar ID", "danger");
        return;
      }
      openCronsModal(calendarId);
      break;

    case "add-cron":
      openCronModal("create", calendarId);
      break;

    default:
      console.warn("Unhandled calendar action:", action);
  }
}

//function handleCronsModalActionClick(e) {
//}

function handleActionClick(e) {
  const actionItem = e.target.closest(".dropdown-item[data-action]");
  if (!actionItem) return;
  e.preventDefault();

  const dropdown = actionItem.closest(".dropdown");
  if (dropdown) dropdown.classList.remove("active", "is-up");

  const action = actionItem.dataset.action;
  const row = actionItem.closest("tr");
  if (!row) return;

  let handler = null;

  if (row.closest("#tree-body")) {
    handler = handleTreeActionClick;
  } else if (
    row.closest("#calendars-table") ||
    row.closest("#calendars-body") ||
    row.closest("#calendars-content")
  ) {
    handler = handleCalendarsActionClick;
  } else if (
    row.closest("#servers-table") ||
    row.closest("#servers-body") ||
    row.closest("#servers-content")
  ) {
    handler = handleServerActionClick;
  }

  if (handler) {
    handler(e, actionItem, row, action);
  } else {
    console.warn("[DEBUG] No handler found for table – action:", action);
  }
}

// Escape key handler
function handleEscapeKey(e) {
  if (e.key === "Escape") {
    console.log("[DEBUG] Escape pressed – closing all");
    closeAllModals();
    closeAllDropdowns();
  }
}

// Dropdown flip logic (positioning up/down based on screen space)
export function setupDropdownFlip() {
  document.querySelectorAll(".dropdown").forEach((dropdown) => {
    const trigger = dropdown.querySelector(".dropdown-trigger button");
    if (!trigger) return;

    const flipHandler = () => {
      if (!dropdown.classList.contains("active")) {
        dropdown.classList.remove("is-up");
        return;
      }
      const rect = trigger.getBoundingClientRect();
      const spaceBelow = window.innerHeight - rect.bottom;
      const menu = dropdown.querySelector(".dropdown-menu");
      const menuHeight = menu?.offsetHeight || 200;

      if (spaceBelow < menuHeight + 30) {
        // more buffer before flipping up
        dropdown.classList.add("is-up");
      } else {
        dropdown.classList.remove("is-up");
      }
    };

    trigger.removeEventListener("click", flipHandler);
    trigger.addEventListener("click", flipHandler);
  });

  const onResize = () => {
    document.querySelectorAll(".dropdown.active").forEach((dropdown) => {
      const trigger = dropdown.querySelector(".dropdown-trigger button");
      if (trigger) {
        const rect = trigger.getBoundingClientRect();
        const spaceBelow = window.innerHeight - rect.bottom;
        const menu = dropdown.querySelector(".dropdown-menu");
        const menuHeight = menu?.offsetHeight || 200;
        if (spaceBelow < menuHeight + 30) {
          dropdown.classList.add("is-up");
        } else {
          dropdown.classList.remove("is-up");
        }
      }
    });
  };

  window.removeEventListener("resize", onResize);
  window.addEventListener("resize", onResize);
}

// Setup all global listeners (call once from app.js)
export function attachGlobalListeners() {
  // Prevent duplicate attachments
  if (document.body.dataset.globalListenersAttached === "true") {
    console.log("Global listeners already attached – skipping");
    return;
  }
  document.body.dataset.globalListenersAttached = "true";

  // Global outside-click handler (capture phase)
  document.addEventListener("click", handleGlobalClick, { capture: true });

  // Delegated action clicks (bubble phase)
  document.addEventListener("click", handleActionClick);

  // Escape key
  document.addEventListener("keydown", handleEscapeKey);

  // dropdown-handlers.js – add this inside attachGlobalListeners() or as a separate listener
  document.addEventListener("click", (e) => {
    const trigger = e.target.closest(".dropdown-trigger button");
    if (!trigger) return;

    const dropdown = trigger.closest(".dropdown");
    if (!dropdown) return;

    const menu = dropdown.querySelector(".dropdown-menu");
    if (!menu) return;

    const willOpen = !dropdown.classList.contains("active");

    console.log(
      "[DEBUG] Global dropdown trigger clicked – willOpen:",
      willOpen,
    );

    // Close all other dropdowns
    document.querySelectorAll(".dropdown.active").forEach((d) => {
      if (d !== dropdown) {
        d.classList.remove("active", "is-up");
        const m = d.querySelector(".dropdown-menu");
        if (m) m.style.display = "none";
      }
    });

    // Toggle the current dropdown
    dropdown.classList.toggle("active");

    if (dropdown.classList.contains("active")) {
      menu.style.display = "block";
      menu.offsetHeight; // reflow for transition

      // Flip positioning
      const rect = trigger.getBoundingClientRect();
      const spaceBelow = window.innerHeight - rect.bottom;
      const menuHeight = menu.offsetHeight || 200;
      if (spaceBelow < menuHeight + 30) {
        dropdown.classList.add("is-up");
      } else {
        dropdown.classList.remove("is-up");
      }
    } else {
      menu.style.display = "none";
    }
  });

  // Initial dropdown flip setup
  setupDropdownFlip();

  document
    .querySelectorAll(".close-btn[data-dismiss], .btn[data-dismiss]")
    .forEach((btn) => {
      btn.addEventListener("click", () => {
        const modalId = btn.dataset.dismiss;
        const modal = document.getElementById(modalId);
        if (modal) {
          modal.classList.remove("active");
          closeAllDropdowns(); // optional cleanup
        }
      });
    });

  console.log("Global listeners attached successfully");
}
