// tree-table.js – jobs/clusters tree rendering + user interaction

import { appState } from "./state.js";
import { updateCollapsedClusters } from "./state.js"; // persistence helpers

import {
  formatTplus,
  formatTminus,
  formatDuration,
  findClusterById,
  findJobById,
  getFullPath,
  stateClass,
} from "./utils.js";

// Import modal/graph openers (create these when ready)
import { openEntityModal, openAttachCalendarModal } from "./modals.js";
import { openDependencyGraph } from "./graph.js"; // or keep in this file temporarily

import { showToast } from "./ui-handlers.js";

// General WS command sender (can move to websocket.js later if it grows)
export function sendCommand(action, id, type) {
  let command;
  switch (action) {
    case "run":
      command = `start_${type}`;
      break;
    case "kill":
      command = `kill_${type}`;
      break;
    case "hold":
      command = `hold_${type}`;
      break;
    case "release":
      command = `release_${type}`;
      break;
    case "ice":
      command = `ice_${type}`;
      break;
    case "melt":
      command = `melt_${type}`;
      break;
    case "complete":
      command = `complete_${type}`;
      break;
    case "reset":
      command = `reset_${type}`;
      break;
    case "delete":
      command = `delete_${type}`;
      break;
    default:
      return;
  }

  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify({ command, id }));
  } else {
    showToast("Not connected", "danger");
  }
}

// Attach all tree table event listeners (call from app.js when monitor tab activates)
export function attachTreeTableListeners() {
  const treeBody = document.getElementById("tree-body");
  if (!treeBody) return;

  treeBody.addEventListener("click", (e) => {
    // Collapse/expand toggle
    const toggle = e.target.closest(".ordo-toggle");
    if (toggle) {
      const row = toggle.closest("tr");
      const clusterId = row.dataset.id;
      const isCollapsed = row.classList.toggle("collapsed");
      console.log("Toggle clicked for cluster", clusterId);

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

    // Dropdown trigger (open/close)
    const trigger = e.target.closest(".dropdown-trigger button");
    if (trigger) {
      e.stopPropagation(); // prevent page click from closing

      const dropdown = trigger.closest(".dropdown");
      const menu = dropdown.querySelector(".dropdown-menu");
      const willOpen = !dropdown.classList.contains("active");

      // Close all other dropdowns
      document.querySelectorAll(".dropdown.active").forEach((d) => {
        if (d !== dropdown) {
          d.classList.remove("active", "is-up");
        }
      });

      dropdown.classList.toggle("active", willOpen);

      if (willOpen) {
        menu.style.display = "block";
        menu.offsetHeight; // force reflow

        const triggerRect = trigger.getBoundingClientRect();
        const menuRect = menu.getBoundingClientRect();
        const viewportHeight = window.innerHeight;
        const navbarHeight = 60;
        const margin = 40;

        const spaceBelow = viewportHeight - triggerRect.bottom;
        const spaceAbove = triggerRect.top - navbarHeight;
        const menuHeight = menuRect.height;

        const useUp = spaceAbove > spaceBelow;
        dropdown.classList.toggle("is-up", useUp);

        const chosenSpace = useUp ? spaceAbove : spaceBelow;
        menu.style.maxHeight = Math.max(200, chosenSpace - margin) + "px";
        menu.style.display = "";
      }

      return; // stop further processing
    }

    // Dropdown actions
    const item = e.target.closest(".dropdown-item");
    if (item) {
      const text = item.textContent.trim().toLowerCase();
      const row = item.closest("tr");
      const id = row.dataset.id;
      const name = row
        .querySelector("td:first-child")
        .textContent.trim()
        .replace(/[▶▼ ]/g, "")
        .trim();

      const isCluster = row.classList.contains("ordo-cluster-row");
      const type = isCluster ? "cluster" : "job";

      const clusterId = Number(row.dataset.id);
      const clusterName = row
        .querySelector("td:first-child")
        .textContent.trim()
        .replace(/\/$/, "");

      if (text === "edit") {
        console.log(JSON.stringify(appState.monitorData, null, 2));

        const node = isCluster
          ? findClusterById(appState.monitorData.tree, id)
          : findJobById(appState.monitorData.tree, id);
        if (node) openEntityModal("edit", isCluster ? "cluster" : "job", node);
        return;
      }

      if (text === "view graph") {
        openDependencyGraph(clusterId, clusterName);
        return;
      }

      if (text === "new cluster" || text === "new job") {
        const parentId = Number(row.dataset.id);
        const parentName = row
          .querySelector("td:first-child")
          .textContent.trim()
          .replace(/\/$/, "");
        const type = text === "new job" ? "job" : "cluster";
        openEntityModal("create", type, null, parentId, parentName);
        return;
      }

      if (text === "attach calendar") {
        const node = findClusterById(appState.monitorData.tree, clusterId);
        openAttachCalendarModal(
          clusterId,
          clusterName,
          node.cal_name || "",
          node.cal_id || null,
        );
        return;
      }

      if (["kill", "delete"].includes(text)) {
        document.getElementById("confirm-message").textContent =
          `Are you sure you want to ${text} ${type} "${name}"?`;
        document.getElementById("confirm-modal").classList.add("active");

        const yesBtn = document.getElementById("confirm-yes");
        const noBtn = document.getElementById("confirm-no");
        const closeBtn = document.getElementById("close-confirm");

        const handleConfirm = () => {
          sendCommand(text, id, type);
          document.getElementById("confirm-modal").classList.remove("active");
          yesBtn.removeEventListener("click", handleConfirm);
        };

        yesBtn.addEventListener("click", handleConfirm);
        noBtn.addEventListener("click", () =>
          document.getElementById("confirm-modal").classList.remove("active"),
        );
        closeBtn.addEventListener("click", () =>
          document.getElementById("confirm-modal").classList.remove("active"),
        );
        return;
      }

      /*
      if (text === "view log" && !isCluster) {
        if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
          appState.ws.send(JSON.stringify({ command: "read_log", id }));
        }
        const logModal = document.getElementById("log-modal");
        logModal.classList.add("active");
        document.querySelector("#log-modal .modal-title").textContent =
          "Latest Job Log";
         
        // More robust ID retrieval
        let jobId = null;
        let currentRow = item.closest("tr");
        if (currentRow && currentRow.dataset.id) {
          jobId = currentRow.dataset.id;
        } else {
          console.warn("Could not find job ID from row");
        }
       
        logModal.dataset.jobId = jobId;
        // Attach history listeners
        attachLogHistoryListeners();
         
        return;
      }

      if (text === "view log" && !isCluster) {
        if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
          appState.ws.send(JSON.stringify({ command: "read_log", id }));
        }

        const logModal = document.getElementById("log-modal");
        logModal.classList.add("active");

        // Get job name from the row (same cell as nameHtml)
        const nameCell = currentRow.querySelector("td:first-child");
        let jobName = "Unnamed Job";
        if (nameCell) {
          // Clean up name: remove toggle arrow, icon, and trailing / if any
          jobName = nameCell.textContent
            .replace(/[▶▼ ]/g, "") // remove toggle arrows/spaces
            .replace(/<[^>]*>/g, "") // remove any HTML (icons)
            .trim()
            .replace(/\/$/, ""); // remove trailing /
        }

        // Set dynamic title
        document.querySelector("#log-modal .modal-title").textContent =
          `Latest Job Log: ${jobName} (ID: ${id})`;

        // More robust ID retrieval (already good, keeping it)
        let jobId = null;
        let currentRow = item.closest("tr");
        if (currentRow && currentRow.dataset.id) {
          jobId = currentRow.dataset.id;
        } else {
          console.warn("Could not find job ID from row");
          showToast("Job ID not found", "warning");
        }

        logModal.dataset.jobId = jobId;

        // Attach history listeners
        attachLogHistoryListeners();

        return;
      }

      if (text === "view log" && !isCluster) {
        if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
          appState.ws.send(JSON.stringify({ command: "read_log", id }));
        }

        const logModal = document.getElementById("log-modal");
        logModal.classList.add("active");

        // Robust jobId retrieval with debug
        let jobId = null;
        const currentRow = item.closest("tr");
        jobId = currentRow.dataset.id;

        logModal.dataset.jobId = jobId || "unknown";

        // Attach history listeners (local function in tree-table.js)
        attachLogHistoryListeners();

        return;
      }

*/

      if (text === "view log" && !isCluster) {
        const row = item.closest("tr");
        const jobId = row.dataset.id;

        const modal = document.getElementById("log-modal");
        modal.dataset.jobId = jobId;

        // Immediate placeholder using job ID (name will come from reply)
        document.getElementById("log-modal-title").textContent =
          `Job ID: ${jobId} — Loading log...`;
        document.getElementById("log-modal-subtitle").textContent = "";

        if (appState.ws?.readyState === WebSocket.OPEN) {
          appState.ws.send(JSON.stringify({ command: "read_log", id: jobId }));
        }

        modal.classList.add("active");
      }

      sendCommand(text, id, type);
    }
  });
}

// Tree rendering

export function renderJobsTable() {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;

  tbody.innerHTML = "";
  buildRows(appState.monitorData.tree, tbody);

  // Apply collapsed state
  document.querySelectorAll(".ordo-cluster-row.collapsed").forEach((row) => {
    toggleSubtree(row.dataset.id, true);
  });

  updateTreeTimings();
  startTreeTimings();
}

// Build table rows recursively
export function buildRows(items, tbody, depth = 0, parentId = null) {
  const collapsedSet = appState.collapsedClusters;

  items.forEach((item) => {
    const isCluster = item.is_cluster;
    const hasChildren = isCluster && item.children?.length > 0;
    const state = item.jobstate?.toLowerCase() || "";
    const isRoot = item.name === "root" && item.parent_id == null;

    // Action button disabling logic
    const runDisabled = ["running", "immutable", "ice", "hold"].includes(state)
      ? "disabled"
      : "";
    const killDisabled = state === "running" ? "" : "disabled";
    const holdDisabled = ["hold", "immutable", "ice"].includes(state)
      ? "disabled"
      : "";
    const releaseDisabled = state === "hold" ? "" : "disabled";
    const iceDisabled = ["ice", "immutable"].includes(state) ? "disabled" : "";
    const meltDisabled = state === "ice" ? "" : "disabled";
    const completeDisabled = "";
    const resetDisabled = isCluster ? "" : "disabled";
    const viewLogDisabled = isCluster ? "disabled" : "";
    const newJobDisabled = isCluster && !isRoot ? "" : "disabled";
    const newClusterDisabled = isCluster ? "" : "disabled";

    const row = document.createElement("tr");
    row.className = isCluster ? "ordo-cluster-row" : "ordo-job-row";
    row.dataset.id = item.id;
    row.dataset.depth = depth;
    row.dataset.parent = parentId || "";
    row.dataset.hidden = "false";
    row.style.setProperty("--depth", depth);
    row.setAttribute("role", "row");
    row.setAttribute("aria-level", (depth + 1).toString());

    if (isCluster) {
      const isCollapsed = collapsedSet.has(String(item.id));
      if (isCollapsed) row.classList.add("collapsed");
      row.setAttribute("aria-expanded", (!isCollapsed).toString());
    }

    const toggleHtml = hasChildren ? `<span class="ordo-toggle"></span>` : "";
    const icon = isCluster
      ? '<i class="fas fa-folder mr-2 has-text-info"></i>'
      : '<i class="fas fa-cog mr-2 has-text-grey"></i>';
    const nameHtml = `${toggleHtml}${icon}${isCluster ? item.name + "/" : item.name}`;

    // Inside the row creation loop (for each item)

    // Dependencies badge + tooltip
    let depsCount = 0;
    let depsTooltipLines = [];

    // Use item.is_cluster directly (force boolean)
    const isThisCluster = !!item.is_cluster; // true for clusters, false for jobs
    console.log("Tooltip for", item.name, "isCluster:", isThisCluster);

    // Needs (blocking)
    if (item.needs_ids?.length) {
      depsCount += item.needs_ids.length;
      const lines = item.needs_ids.map(
        (id) =>
          `• ${resolveDepName(id, appState.monitorData.tree, isThisCluster)}`,
      );
      depsTooltipLines.push(`Needs (blocking):\n${lines.join("\n")}`);
    }

    // Needs Any (flexible)
    if (item.needs_any_ids?.length) {
      depsCount += item.needs_any_ids.length;
      const lines = item.needs_any_ids.map(
        (id) =>
          `• ${resolveDepName(id, appState.monitorData.tree, isThisCluster)}`,
      );
      depsTooltipLines.push(`Needs Any (flexible):\n${lines.join("\n")}`);
    }

    // On Fail - always cluster (force true)
    if (item.on_fail_id) {
      depsCount += 1;
      const node = findClusterById(appState.monitorData.tree, item.on_fail_id);
      const path = node ? getFullPath(node) : `ID:${item.on_fail_id} (missing)`;
      depsTooltipLines.push(`On Fail:\n• ${path}`);
    }

    const depsDisplay = depsCount > 0 ? depsCount : "—";
    const depsTitle = depsTooltipLines.length
      ? depsTooltipLines.join("\n\n")
      : "";

    // Stats badge + tooltip
    let statsDisplay = "—";
    let statsTooltipLines = [];

    // Only compute stats for jobs (not clusters)
    if (!item.is_cluster) {
      // CPU badge - only show if pctcpu was actually collected
      if (item.pctcpu !== null && item.pctcpu !== undefined) {
        const cpu = item.pctcpu;
        let cpuClass = "cpu-low";
        if (cpu > 80) cpuClass = "cpu-high";
        else if (cpu > 50) cpuClass = "cpu-medium";

        statsDisplay = `<span class="stats-badge ${cpuClass}">${cpu.toFixed(1)}%</span>`;
        statsTooltipLines.push(`• CPU: ${cpu.toFixed(1)}%`);
      }

      // Memory % line - only show if collected
      if (item.pctmem !== null && item.pctmem !== undefined) {
        statsTooltipLines.push(`• Memory: ${item.pctmem.toFixed(1)}%`);
      }

      // RSS line - only show if collected
      if (item.rss !== null && item.rss !== undefined) {
        const rssMB = Math.round(item.rss / 1024 / 1024);
        statsTooltipLines.push(`• RSS: ${rssMB} MB`);
      }

      // Always add PID if present
      if (item.pid !== null && item.pid !== undefined) {
        statsTooltipLines.push(`Process (PID ${item.pid}):`);
      }

      // Parent PID and command (if present)
      if (item.ppid !== null && item.ppid !== undefined) {
        statsTooltipLines.push(`• Parent PID: ${item.ppid}`);
      }
      if (item.fname) {
        statsTooltipLines.push(`• Command: ${item.fname}`);
      }

      // In the hint block
      if (
        item.jobstate === "running" &&
        item.pid !== null &&
        item.pid !== undefined &&
        item.pctcpu == null &&
        item.pctmem == null &&
        item.rss == null
      ) {
        statsTooltipLines.push(""); // empty line for spacing
        statsTooltipLines.push(
          "Full stats not collected – run update_stats.pl",
        );
      }
    }

    const statsTitle = statsTooltipLines.length
      ? statsTooltipLines.join("\n")
      : "";

    if (statsTitle && statsDisplay.includes("tag")) {
      const tempDiv = document.createElement("div");
      tempDiv.innerHTML = statsDisplay;
      const tag = tempDiv.querySelector(".tag");
      if (tag) tag.setAttribute("title", statsTitle);
      statsDisplay = tempDiv.innerHTML;
    }

    // Actions dropdown

    // Helper: create a menu item with disabled state
    function menuItem(text, disabled = false, action = null) {
      const cls = disabled ? "dropdown-item disabled" : "dropdown-item";
      const attrs = disabled ? 'aria-disabled="true" tabindex="-1"' : "";
      const dataAction = action ? `data-action="${action}"` : "";
      return `<a href="javascript:void(0)" class="${cls}" ${attrs} ${dataAction}>${text}</a>`;
    }

    // Helper: divider
    const divider = '<hr class="dropdown-divider">';

    // Build actions dropdown
    let actionsHtml = "";

    if (isRoot) {
      actionsHtml = `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="button is-small is-light" aria-haspopup="menu" aria-controls="root-menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" id="root-menu" role="menu">
        <div class="dropdown-content">
          ${menuItem("New Cluster", false, "new-cluster")}
        </div>
      </div>
    </div>
  `;
    } else if (isCluster) {
      actionsHtml = `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="button is-small is-light" aria-haspopup="menu" aria-controls="cluster-menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" id="cluster-menu" role="menu">
        <div class="dropdown-content">
          ${menuItem("Edit", false, "edit-cluster")}
          ${menuItem("View Graph", false, "view-graph")}
          ${divider}
          ${menuItem("New Cluster", newClusterDisabled, "new-cluster")}
          ${menuItem("New Job", newJobDisabled, "new-job")}
          ${menuItem("Attach Calendar", false, "attach-calendar")}
          ${divider}
          ${menuItem("Run", runDisabled, "run")}
          ${menuItem("Kill", killDisabled, "kill")}
          ${menuItem("Hold", holdDisabled, "hold")}
          ${menuItem("Release", releaseDisabled, "release")}
          ${menuItem("Ice", iceDisabled, "ice")}
          ${menuItem("Melt", meltDisabled, "melt")}
          ${menuItem("Complete", completeDisabled, "complete")}
          ${divider}
          ${menuItem("Reset", resetDisabled, "reset")}
          ${divider}
          ${menuItem("Delete", false, "delete", "is-danger")}
          ${divider}
          ${menuItem("View Log", viewLogDisabled, "view-log")}
        </div>
      </div>
    </div>
  `;
    } else {
      // Job row
      actionsHtml = `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="button is-small is-light" aria-haspopup="menu" aria-controls="job-menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" id="job-menu" role="menu">
        <div class="dropdown-content">
          ${menuItem("Edit", false, "edit-job")}
          ${divider}
          ${menuItem("Run", runDisabled, "run")}
          ${menuItem("Kill", killDisabled, "kill")}
          ${menuItem("Hold", holdDisabled, "hold")}
          ${menuItem("Release", releaseDisabled, "release")}
          ${menuItem("Ice", iceDisabled, "ice")}
          ${menuItem("Melt", meltDisabled, "melt")}
          ${menuItem("Complete", completeDisabled, "complete")}
          ${divider}
          ${menuItem("Delete", false, "delete", "is-danger")}
          ${divider}
          ${menuItem("View Log", viewLogDisabled, "view-log")}
        </div>
      </div>
    </div>
  `;
    }

    // In buildRows, inside the state <td>
    // <td><span class="ordo-state ${stateClass(item.jobstate)}">${item.jobstate || "—"}</span></td>
    const stateLower = (item.jobstate || "").toLowerCase().trim();
    const stateClass = `state-badge ${stateLower || "unknown"}`;

    row.innerHTML = `
  <td>${nameHtml}</td>

  <td>
    <span class="${stateClass}">
      ${item.jobstate || "—"}
    </span>
  </td>
  <td>${item.server_name || "—"}</td>
  <td class="deps-td ${depsCount > 0 ? "has-tooltip" : ""}" title="${depsTitle}">${depsDisplay}</td>
  <td class="stats-td ${statsTitle && statsTitle !== "—" ? "has-tooltip" : ""}" title="${statsTitle}">${statsDisplay}</td>
  <td>${formatTplus(item.started) || "—"}</td>
  <td>${formatDuration(item.started, item.ended) || "—"}</td>
  <td>${formatTminus(item.next_start) || "—"}</td>
  <td>${item.cal_name || "—"}</td>
  <td>${actionsHtml}</td>
`;

    tbody.appendChild(row);

    if (hasChildren) {
      buildRows(item.children, tbody, depth + 1, item.id);
    }
  });
  setupDropdownFlip();
}

// Call this ONCE after initial table build (e.g., at end of buildRows)
// Or after any full table rebuild
function setupDropdownFlip() {
  // Remove any existing listeners first (prevents duplicates)
  document.querySelectorAll(".table .dropdown").forEach((dropdown) => {
    // Optional: remove previous listeners if you stored them
    // But simplest: use named function or data attribute to avoid dupes
  });

  const dropdowns = document.querySelectorAll(".table .dropdown");

  dropdowns.forEach((dropdown) => {
    const trigger = dropdown.querySelector(".dropdown-trigger button");
    if (!trigger) return;

    const flipHandler = () => {
      if (!dropdown.classList.contains("active")) {
        // Reset when closing
        dropdown.classList.remove("is-up");
        return;
      }

      // Get trigger position
      const rect = trigger.getBoundingClientRect();
      const spaceBelow = window.innerHeight - rect.bottom;
      const menu = dropdown.querySelector(".dropdown-menu");
      const menuHeight = menu?.offsetHeight || 200; // fallback

      if (spaceBelow < menuHeight + 30) {
        dropdown.classList.add("is-up");
      } else {
        dropdown.classList.remove("is-up");
      }
    };

    // Add listener (use once to avoid dupes if function called multiple times)
    trigger.removeEventListener("click", flipHandler); // cleanup first
    trigger.addEventListener("click", flipHandler);
  });

  // Optional: Handle window resize/scroll while menu is open
  const updateFlipOnResize = () => {
    document.querySelectorAll(".table .dropdown.active").forEach((dropdown) => {
      // Re-run flip logic for open dropdowns
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

  window.removeEventListener("resize", updateFlipOnResize);
  window.addEventListener("resize", updateFlipOnResize);
}

// Collapse/expand subtree
export function toggleSubtree(parentId, hide) {
  const directChildren = document.querySelectorAll(
    `tr[data-parent="${parentId}"]`,
  );
  directChildren.forEach((childRow) => {
    childRow.dataset.hidden = hide ? "true" : "false";
    if (childRow.classList.contains("ordo-cluster-row")) {
      toggleSubtree(childRow.dataset.id, hide);
    }
  });
}

// Force expand all descendants
export function forceExpandDescendants(startId) {
  const children = document.querySelectorAll(`tr[data-parent="${startId}"]`);
  children.forEach((childRow) => {
    if (childRow.classList.contains("ordo-cluster-row")) {
      childRow.classList.remove("collapsed");
      forceExpandDescendants(childRow.dataset.id);
    }
  });
}

// Live timing updates for tree rows
export function updateTreeTimings() {
  document.querySelectorAll("#tree-body tr[data-id]").forEach((row) => {
    const id = row.dataset.id;
    const isClusterRow = row.classList.contains("ordo-cluster-row");
    const item = isClusterRow
      ? findClusterById(appState.monitorData.tree, id)
      : findJobById(appState.monitorData.tree, id);
    if (!item) return;

    const cells = row.cells;
    if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
    if (cells[6])
      cells[6].textContent = formatDuration(item.started, item.ended) || "—";
    if (cells[7]) cells[7].textContent = formatTminus(item.next_start) || "—";
  });
}

// Timer control (start/stop when monitor tab is active)
let timingInterval = null;

export function startTreeTimings() {
  if (timingInterval) return;
  timingInterval = setInterval(updateTreeTimings, 1000);
  updateTreeTimings(); // immediate first call
}

export function stopTreeTimings() {
  if (timingInterval) {
    clearInterval(timingInterval);
    timingInterval = null;
  }
}

function resolveDepName(id, tree, isCluster = false) {
  id = Number(id);

  console.log(
    `%c[DEP RESOLVE] ID: ${id} | isCluster: ${isCluster} | Expected type: ${isCluster ? "CLUSTER" : "JOB"}`,
    "color: #00ffff; font-weight: bold;",
  );

  let node = null;

  if (isCluster) {
    console.log(`[DEP RESOLVE] Using findClusterById for cluster dep ${id}`);
    node = findClusterById(tree, id);
  } else {
    console.log(`[DEP RESOLVE] Using findJobById for job dep ${id}`);
    node = findJobById(tree, id);
  }

  if (node) {
    console.log(
      `[DEP RESOLVE] Found: ${node.is_cluster ? "CLUSTER" : "JOB"} | ID: ${node.id} | Name: ${node.name}`,
    );
  } else {
    console.warn(
      `[DEP RESOLVE] NOT FOUND: ID ${id} as ${isCluster ? "cluster" : "job"}`,
    );
  }

  return node ? getFullPath(node) : `ID:${id} (missing or type mismatch)`;
}

function attachLogHistoryListeners() {
  const viewHistoryBtn = document.getElementById("view-history");
  const closeHistoryBtn = document.getElementById("close-log-history");

  if (viewHistoryBtn && !viewHistoryBtn.dataset.listenerAdded) {
    viewHistoryBtn.addEventListener("click", () => {
      console.log("View History clicked!"); // remove after testing
      const jobId = document.getElementById("log-modal").dataset.jobId;
      if (jobId && appState.ws && appState.ws.readyState === WebSocket.OPEN) {
        appState.ws.send(JSON.stringify({ command: "find_log", id: jobId }));
        document.getElementById("log-history-modal").classList.add("active");
      } else {
        showToast("Not connected or no job ID", "danger");
      }
    });
    viewHistoryBtn.dataset.listenerAdded = "true";
  }

  if (closeHistoryBtn && !closeHistoryBtn.dataset.listenerAdded) {
    closeHistoryBtn.addEventListener("click", () => {
      document.getElementById("log-history-modal").classList.remove("active");
    });
    closeHistoryBtn.dataset.listenerAdded = "true";
  }
}

// In tree-table.js (top level or init function)
const logoutLink = document.querySelector('#private-end a[href="/logout"]');
if (logoutLink) {
  logoutLink.addEventListener("click", () => {
    localStorage.removeItem("ordo_collapsed_clusters");
    appState.collapsedClusters.clear();
  });
}
