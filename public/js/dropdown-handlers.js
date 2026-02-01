import { appState } from "./state.js";
import {
  openAttachCalendarModal,
  openClusterModal,
  openJobModal,
  openConfirmModal,
  openCalendarModal,
} from "./modals.js";
import { openDependencyGraph } from "./graph.js";
import { sendCommand } from "./websocket.js";
import { showToast, toggleCronsRow } from "./ui-handlers.js";
import { findClusterById } from "./utils.js";

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

// Delegated action handler (menu item clicks)
// Delegated action handler (menu item clicks)
function handleActionClick(e) {
  const actionItem = e.target.closest(".dropdown-item[data-action]");
  if (!actionItem) return;

  e.preventDefault();

  // Close dropdown immediately
  const dropdown = actionItem.closest(".dropdown");
  if (dropdown) {
    console.log("[DEBUG] Action clicked – closing dropdown:", dropdown);
    dropdown.classList.remove("active", "is-up");
  }

  const action = actionItem.dataset.action;
  const row = actionItem.closest("tr");
  if (!row) return;

  const isCluster = row.classList.contains("ordo-cluster-row");
  const type = isCluster ? "cluster" : "job";
  const id = Number(row.dataset.id);
  const calendarId = Number(row.dataset.calId); // consistent name

  const name =
    row
      .querySelector("td:first-child")
      ?.textContent.trim()
      .replace(/\/$/, "") || "";

  console.log("[DEBUG] Action:", action, "id:", id, "calendarId:", calendarId, "type:", type);

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
      );
      break;

    case "hold":
      sendCommand("hold", id, type);
      break;

    case "release":
      sendCommand("release", id, type);
      break;

    case "ice":
      sendCommand("ice", id, type);
      break;

    case "melt":
      sendCommand("melt", id, type);
      break;

    case "complete":
      sendCommand("complete", id, type);
      break;

    case "reset":
      sendCommand("reset", id, type);
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
        () => {
          showToast("Deletion cancelled", "info");
        },
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

    case "edit-calendar":
      if (isNaN(calendarId) || calendarId <= 0) {
        showToast("Invalid calendar ID", "danger");
        return;
      }
      console.log("[DEBUG] Edit calendar clicked – calendarId:", calendarId);
      openCalendarModal("edit", calendarId);
      break;

    case "view-crons":
      if (isNaN(calendarId) || calendarId <= 0) {
        showToast("Invalid calendar ID", "danger");
        return;
      }
      console.log("[DEBUG] View crons clicked – calendarId:", calendarId);
      toggleCronsRow(calendarId);
      break;

    case "delete-calendar":
      if (isNaN(calendarId) || calendarId <= 0) {
        showToast("Invalid calendar ID", "danger");
        return;
      }
      console.log("[DEBUG] Delete calendar clicked – calendarId:", calendarId);
      openConfirmModal(
        "Confirm Delete Calendar",
        `Are you sure you want to delete calendar "${name}"?`,
        () => {
          sendWS({ command: "delete_cal", id: calendarId });
          showToast("Calendar deleted", "success");
        },
        () => {
          showToast("Deletion cancelled", "info");
        },
      );
      break;

    default:
      console.warn("Unhandled action:", action);
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
    const menu = dropdown.querySelector(".dropdown-menu");
    const willOpen = !dropdown.classList.contains("active");

    console.log(
      "[DEBUG] Global dropdown trigger clicked – willOpen:",
      willOpen,
    );

    // Close other dropdowns
    document.querySelectorAll(".dropdown.active").forEach((d) => {
      if (d !== dropdown) {
        d.classList.remove("active", "is-up");
        const m = d.querySelector(".dropdown-menu");
        if (m) m.style.display = "none";
      }
    });

    // Toggle current dropdown
    dropdown.classList.toggle("active", willOpen);
    if (willOpen) {
      menu.style.display = "block";
      menu.offsetHeight; // reflow
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

export function updateCalendars(data) {
  hideLoading("calendars-loading");
  document.getElementById("calendars-content").style.display = "block";

  if (data.success) {
    appState.calendarsData = data.cals || [];
    renderCalendarsTable();
  } else {
    showToast("Failed to load calendars", "danger");
  }
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;
  tbody.innerHTML = "";

  appState.calendarsData.forEach(cal => {
    const cronsCount = cal.crons?.length || 0;
    const clustersCount = cal.cluster_ids?.length || 0;

    // Main calendar row
    const row = document.createElement("tr");
    row.className = "calendar-row";
    row.dataset.calId = cal.id;
    row.innerHTML = `
      <td>${cal.name || "—"}</td>
      <td>${cal.tz || "—"}</td>
      <td>${cal.description || "—"}</td>
      <td>${cronsCount}</td>
      <td>${clustersCount}</td>
      <td>
        <div class="dropdown is-right">
          <div class="dropdown-trigger">
            <button class="button is-small is-light" aria-haspopup="menu">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item" data-action="edit-calendar" data-id="${cal.id}">Edit</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item is-danger" data-action="delete-calendar" data-id="${cal.id}">Delete</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item" data-action="view-crons" data-id="${cal.id}">
                ${cronsCount > 0 ? "View Crons" : "Add Crons"}
              </a>
            </div>
          </div>
        </div>
      </td>
    `;
    tbody.appendChild(row);

    // Expandable crons row (hidden by default)
    const cronsRow = document.createElement("tr");
    cronsRow.className = "crons-row hidden";
    cronsRow.dataset.calId = cal.id;
    cronsRow.innerHTML = `
      <td colspan="6" class="p-0">
        <div class="crons-detail bg-gray-900 p-4 border-t border-gray-700">
          <h4 class="text-cyan-400 mb-3">Crons for ${cal.name}</h4>
          ${cronsCount > 0 ? `
            <table class="data-table mb-4">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Cron</th>
                  <th>English</th>
                  <th>Begin</th>
                  <th>Expire</th>
                  <th>Description</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                ${cal.crons.map(cron => `
                  <tr>
                    <td>${cron.id}</td>
                    <td>${cron.name}</td>
                    <td>${cron.english || "—"}</td>
                    <td>${cron.begin ? new Date(cron.begin * 1000).toLocaleString() : "Immediate"}</td>
                    <td>${cron.expire ? new Date(cron.expire * 1000).toLocaleString() : "Never"}</td>
                    <td>${cron.description || "—"}</td>
                    <td>
                      <button class="btn btn-sm btn-warning edit-cron" data-cron-id="${cron.id}" data-cal-id="${cal.id}">Edit</button>
                      <button class="btn btn-sm btn-danger delete-cron" data-cron-id="${cron.id}" data-cal-id="${cal.id}">Delete</button>
                    </td>
                  </tr>
                `).join("")}
              </tbody>
            </table>
          ` : '<p class="text-grey">No crons yet.</p>'}
          <button class="btn btn-sm btn-success add-cron" data-cal-id="${cal.id}">Add Cron</button>
        </div>
      </td>
    `;
    tbody.appendChild(cronsRow);
  });

  setupDropdownFlip();

  // Attach delegated toggle for "View Crons" (no need for .toggle-crons class)
  // This is handled in handleActionClick (see below)
}

