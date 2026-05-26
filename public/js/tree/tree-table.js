// tree/tree-table.js – Pure rendering logic only
import { appState, updateCollapsedClusters } from "../state.js";
import { toggleSubtree } from "./tree-listeners.js";
import {
  updateFreshnessCell,
  renderDashboard,
  updateDashboardLiveCards,
  updateNextScheduledClusters,
} from "../ui-handlers.js";
import {
  formatTplus,
  formatTminus,
  formatDuration,
  formatRelativeTime,
  findClusterByIdFast,
  findJobByIdFast,
  findClusterById,
  findJobById,
  getFullPath,
  resolveDepName,
} from "../utils.js";

// Sort tree nodes (jobs before clusters at same level)
function sortTreeNodes(nodes) {
  nodes.sort((a, b) => {
    if (!a.is_cluster && b.is_cluster) return -1;
    if (a.is_cluster && !b.is_cluster) return 1;
    return Number(a.id) - Number(b.id);
  });
  nodes.forEach((node) => {
    if (node.children && node.children.length > 0) {
      sortTreeNodes(node.children);
    }
  });
}

// Shared row content generator
function generateRowContent(
  item,
  depth = 0,
  parentId = null,
  index = 0,
  siblingCount = 1,
) {
  const isCluster = item.is_cluster;
  const hasChildren = isCluster && item.children?.length > 0;
  const stateLower = (item.jobstate || "").toLowerCase().trim();
  const isRoot = item.name === "root" && item.parent_id == null;
  const isLastInSiblings = index === siblingCount - 1;

  // Toggle & icon
  const toggleHtml = isCluster ? `<span class="ordo-toggle"></span>` : "";
  const icon = isCluster
    ? '<i class="fas fa-folder mr-2 has-text-info"></i>'
    : '<i class="fas fa-cog mr-2 has-text-grey"></i>';
  const nameHtml = `${toggleHtml}${icon}${isCluster ? item.name + "/" : item.name}`;

  // State badge
  const stateClass = `state-badge ${stateLower || "unknown"}`;

  // Dependencies
  let depsCount = 0;
  let depsTooltipLines = [];
  if (item.needs_ids?.length) {
    depsCount += item.needs_ids.length;
    const lines = item.needs_ids.map(
      (id) => `• ${resolveDepName(id, appState.monitorData.tree, isCluster)}`,
    );
    depsTooltipLines.push(`Needs (blocking):\n${lines.join("\n")}`);
  }
  if (item.needs_any_ids?.length) {
    depsCount += item.needs_any_ids.length;
    const lines = item.needs_any_ids.map(
      (id) => `• ${resolveDepName(id, appState.monitorData.tree, isCluster)}`,
    );
    depsTooltipLines.push(`Needs Any (flexible):\n${lines.join("\n")}`);
  }
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

  // Stats
  let statsDisplay = "—";
  let statsTooltipLines = [];
  if (!isCluster) {
    if (item.pctcpu !== null && item.pctcpu !== undefined) {
      const cpu = item.pctcpu;
      let cpuClass = "cpu-low";
      if (cpu > 80) cpuClass = "cpu-high";
      else if (cpu > 50) cpuClass = "cpu-medium";
      statsDisplay = `<span class="stats-badge ${cpuClass}">${cpu.toFixed(1)}%</span>`;
      statsTooltipLines.push(`• CPU: ${cpu.toFixed(1)}%`);
    }
    if (item.pctmem !== null && item.pctmem !== undefined) {
      statsTooltipLines.push(`• Memory: ${item.pctmem.toFixed(1)}%`);
    }
    if (item.rss !== null && item.rss !== undefined) {
      const rssMB = Math.round(item.rss / 1024 / 1024);
      statsTooltipLines.push(`• RSS: ${rssMB} MB`);
    }
    if (item.pid !== null && item.pid !== undefined) {
      statsTooltipLines.push(`Process (PID ${item.pid}):`);
    }
    if (item.ppid !== null && item.ppid !== undefined) {
      statsTooltipLines.push(`• Parent PID: ${item.ppid}`);
    }
    if (item.fname) {
      statsTooltipLines.push(`• Command: ${item.fname}`);
    }
    if (
      item.jobstate === "running" &&
      item.pid !== null &&
      item.pctcpu == null
    ) {
      statsTooltipLines.push("");
      statsTooltipLines.push("Full stats not collected – run update_stats.pl");
    }
  }
  const statsTitle = statsTooltipLines.length
    ? statsTooltipLines.join("\n")
    : "";

  // Actions HTML
  const menuItem = (text, disabled = false, action = null) => {
    const cls = disabled ? "dropdown-item disabled" : "dropdown-item";
    const attrs = disabled ? 'aria-disabled="true" tabindex="-1"' : "";
    const dataAction = action ? `data-action="${action}"` : "";
    return `<a href="javascript:void(0)" class="${cls}" ${attrs} ${dataAction}>${text}</a>`;
  };
  const divider = '<hr class="dropdown-divider">';

  let actionsHtml = "";
  if (isRoot) {
    actionsHtml = `
      <div class="dropdown is-right">
        <div class="dropdown-trigger">
          <button class="button is-small is-light" aria-haspopup="menu">
            <i class="fas fa-ellipsis-v"></i>
          </button>
        </div>
        <div class="dropdown-menu" role="menu">
          <div class="dropdown-content">
            ${menuItem("New Cluster", false, "new-cluster")}
          </div>
        </div>
      </div>
    `;
  } else if (isCluster) {
    const runDisabled =
      (stateLower === "running" && !item.clonable) ||
      ["immutable", "ice", "hold"].includes(stateLower);
    const killDisabled = stateLower !== "running";
    const holdDisabled = ["hold", "immutable", "ice"].includes(stateLower);
    const releaseDisabled = stateLower !== "hold";
    const iceDisabled = ["ice", "immutable"].includes(stateLower);
    const meltDisabled = stateLower !== "ice";

    actionsHtml = `
      <div class="dropdown is-right">
        <div class="dropdown-trigger">
          <button class="button is-small is-light" aria-haspopup="menu">
            <i class="fas fa-ellipsis-v"></i>
          </button>
        </div>
        <div class="dropdown-menu" role="menu">
          <div class="dropdown-content">
            ${menuItem("Edit", false, "edit-cluster")}
            ${menuItem("View Graph", false, "view-graph")}
            ${divider}
            ${menuItem("New Cluster", false, "new-cluster")}
            ${menuItem("New Job", false, "new-job")}
            ${menuItem("Attach Calendar", false, "attach-calendar")}
            ${divider}
            ${menuItem("Run", runDisabled, "run")}
            ${menuItem("Kill", killDisabled, "kill")}
            ${menuItem("Hold", holdDisabled, "hold")}
            ${menuItem("Release", releaseDisabled, "release")}
            ${menuItem("Ice", iceDisabled, "ice")}
            ${menuItem("Melt", meltDisabled, "melt")}
            ${menuItem("Complete", false, "complete")}
            ${divider}
            ${menuItem("Reset", false, "reset")}
            ${divider}
            ${menuItem("Delete", false, "delete")}
          </div>
        </div>
      </div>
    `;
  } else {
    const runDisabled =
      (stateLower === "running" && !item.clonable) ||
      ["immutable", "ice", "hold"].includes(stateLower);
    const killDisabled = stateLower !== "running";
    const holdDisabled = ["hold", "immutable", "ice"].includes(stateLower);
    const releaseDisabled = stateLower !== "hold";
    const iceDisabled = ["ice", "immutable"].includes(stateLower);
    const meltDisabled = stateLower !== "ice";

    actionsHtml = `
      <div class="dropdown is-right">
        <div class="dropdown-trigger">
          <button class="button is-small is-light" aria-haspopup="menu">
            <i class="fas fa-ellipsis-v"></i>
          </button>
        </div>
        <div class="dropdown-menu" role="menu">
          <div class="dropdown-content">
            ${menuItem("Edit", false, "edit-job")}
            ${divider}
            ${menuItem("Run", runDisabled, "run")}
            ${menuItem("Kill", killDisabled, "kill")}
            ${menuItem("Hold", holdDisabled, "hold")}
            ${menuItem("Release", releaseDisabled, "release")}
            ${menuItem("Ice", iceDisabled, "ice")}
            ${menuItem("Melt", meltDisabled, "melt")}
            ${menuItem("Complete", false, "complete")}
            ${divider}
            ${menuItem("Delete", false, "delete")}
            ${divider}
            ${menuItem("View Log", false, "view-log")}
          </div>
        </div>
      </div>
    `;
  }

  const html = `
    <td>${nameHtml}</td>
    <td><span class="${stateClass}">${item.jobstate || "—"}</span></td>
    <td>${item.server_name || "—"}</td>
    <td class="deps-td ${depsCount > 0 ? "has-tooltip" : ""}" title="${depsTitle}">${depsDisplay}</td>
    <td class="stats-td ${statsTitle ? "has-tooltip" : ""}" title="${statsTitle}">${statsDisplay}</td>
    <td>${formatTplus(item.started) || "—"}</td>
    <td>${formatDuration(item.started, item.ended) || "—"}</td>
    <td>${formatTminus(item.next_start) || "—"}</td>
    <td>${item.cal_name || "—"}</td>
    <td>${actionsHtml}</td>
  `;

  return {
    html,
    isCollapsed: isCluster && appState.collapsedClusters.has(String(item.id)),
    isLastInSiblings,
    hasChildren,
  };
}

// Build single row (initial and new)
function buildSingleRow(
  row,
  item,
  depth = 0,
  parentId = null,
  index = 0,
  siblingCount = 1,
) {
  const { html, isCollapsed, isLastInSiblings, hasChildren } =
    generateRowContent(item, depth, parentId, index, siblingCount);

  row.id = item.is_cluster ? `row-cluster-${item.id}` : `row-job-${item.id}`;
  row.className = item.is_cluster ? "ordo-cluster-row" : "ordo-job-row";
  row.dataset.id = item.id;
  row.dataset.depth = depth;
  row.dataset.parent = parentId || "";
  row.dataset.hidden = "false";
  row.style.setProperty("--depth", depth);
  row.setAttribute("role", "row");
  row.setAttribute("aria-level", (depth + 1).toString());

  if (isLastInSiblings && parentId !== null) {
    row.dataset.lastChild = "true";
  }

  row.innerHTML = html;

  if (isCollapsed) {
    row.classList.add("collapsed");
  }
  row.setAttribute(
    "aria-expanded",
    hasChildren ? (!isCollapsed).toString() : "false",
  );
}

// ==================== FIXED updateRow ====================
export function updateRow(row, item) {
  if (!row || !item) return;

  const depth = Number(row.dataset.depth) || 0;
  const parentId = row.dataset.parent || null;

  const { html, isCollapsed } = generateRowContent(item, depth, parentId);

  // Only replace innerHTML — preserve collapse class and data attributes
  row.innerHTML = html;

  if (isCollapsed) {
    row.classList.add("collapsed");
  } else {
    row.classList.remove("collapsed");
  }

  // Critical: Always update Next Run column for clusters
  if (item.is_cluster && item.next_start !== undefined) {
    const nextRunCell = row.cells[7]; // 8th column (0-based)
    if (nextRunCell) {
      nextRunCell.textContent = formatTminus(item.next_start) || "—";
      nextRunCell.dataset.nextStart = item.next_start;
    }
  }

  // Update live timing cells safely
  const cells = row.cells;
  if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
  if (cells[6])
    cells[6].textContent = formatDuration(item.started, item.ended) || "—";
}

export function insertRow(item, parentId = null) {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;

  const isCluster = !!item.is_cluster || !!item.parent_id;
  const rowId = isCluster ? `row-cluster-${item.id}` : `row-job-${item.id}`;

  if (document.getElementById(rowId)) {
    updateRow(document.getElementById(rowId), item);
    return;
  }

  const newRow = document.createElement("tr");
  newRow.id = rowId;

  let depth = 0;
  if (parentId) {
    const parentRow = document.getElementById(`row-cluster-${parentId}`);
    if (parentRow) depth = Number(parentRow.dataset.depth || 0) + 1;
  }

  buildSingleRow(newRow, item, depth, parentId);

  // === UNIFIED SUBTREE INSERTION (works for both clusters and jobs) ===
  if (parentId) {
    const parentRow = document.getElementById(`row-cluster-${parentId}`);
    if (parentRow) {
      let lastDescendant = parentRow;
      let current = parentRow.nextElementSibling;

      while (current) {
        const rowParent = current.dataset.parent;
        const rowCluster = current.dataset.clusterId || current.dataset.cluster;

        const belongsToSubtree =
          (rowParent && String(rowParent) === String(parentId)) ||
          (rowCluster && String(rowCluster) === String(parentId)) ||
          (rowParent && isDescendantOf(rowParent, parentId));

        if (!belongsToSubtree) break;

        lastDescendant = current;
        current = current.nextElementSibling;
      }

      lastDescendant.after(newRow);
    } else {
      tbody.appendChild(newRow);
    }
  } else {
    tbody.appendChild(newRow);
  }

  // Re-apply collapse state for clusters
  if (isCluster && appState.collapsedClusters.has(String(item.id))) {
    newRow.classList.add("collapsed");
    toggleSubtree(item.id, true);
  }
}

// Helper function
function isDescendantOf(childParentId, targetParentId) {
  let current = childParentId;
  while (current) {
    if (String(current) === String(targetParentId)) return true;
    const row = document.getElementById(`row-cluster-${current}`);
    current = row ? row.dataset.parent : null;
  }
  return false;
}

// Remove row
export function removeRow(id, isCluster) {
  const rowId = isCluster ? `row-cluster-${id}` : `row-job-${id}`;
  const row = document.getElementById(rowId);
  if (row) row.remove();
}

// Initial full render
export function renderJobsTable() {
  const tbody = document.getElementById("tree-body");
  if (!tbody) {
    console.warn("[renderJobsTable] #tree-body not found");
    return;
  }

  tbody.innerHTML = "";

  // Cleanup stale collapsed IDs
  const currentClusterIds = new Set();
  function collectIds(nodes) {
    nodes.forEach((node) => {
      if (node.is_cluster) {
        currentClusterIds.add(String(node.id));
        if (node.children) collectIds(node.children);
      }
    });
  }
  collectIds(appState.monitorData.tree);

  // Remove stale collapsed entries
  appState.collapsedClusters.forEach((id) => {
    if (!currentClusterIds.has(id)) {
      appState.collapsedClusters.delete(id);
    }
  });

  updateCollapsedClusters();

  // Sort and build rows
  sortTreeNodes(appState.monitorData.tree);
  buildRows(appState.monitorData.tree, tbody);

  // Safe collapse application
  appState.collapsedClusters.forEach((id) => {
    const row = document.querySelector(`tr[data-id="${id}"]`);
    if (row) {
      row.classList.add("collapsed");
      toggleSubtree(id, true); // only call if row exists
    }
  });

  updateLiveTimings();
  startLiveTimings();
}

// Recursion for buildRows
export function buildRows(items, tbody, depth = 0, parentId = null) {
  items.forEach((item, index) => {
    const row = document.createElement("tr");
    buildSingleRow(row, item, depth, parentId, index, items.length);
    tbody.appendChild(row);

    if (item.is_cluster && appState.collapsedClusters.has(String(item.id))) {
      row.classList.add("collapsed");
      toggleSubtree(item.id, true); // hides children subtree
    }
    if (item.children && item.children.length > 0) {
      buildRows(item.children, tbody, depth + 1, item.id);
    }
  });
}

// Live timings



// Module-level cache for tree timings
let treeTimingCache = null;
let liveTimingInterval = null;

export function startLiveTimings() {
  if (liveTimingInterval) return;

  // === CACHE TREE TIMING ELEMENTS ONCE ===
  treeTimingCache = {
    rows: []
  };

  document.querySelectorAll("#tree-body tr[data-id]").forEach((row) => {
    const cells = row.cells;
    if (cells.length < 8) return;

    treeTimingCache.rows.push({
      row: row,
      tplusCell: cells[5],
      durationCell: cells[6],
      tminusCell: cells[7]
    });
  });

  liveTimingInterval = setInterval(updateLiveTimings, 1000);
  updateLiveTimings(); // immediate update
}

export function updateLiveTimings() {
  const now = Math.floor(Date.now() / 1000);

  // === MAIN TREE TABLE (Jobs & Clusters) ===
  const monitorTab = document.getElementById("monitor");
  if (monitorTab && monitorTab.classList.contains("active")) {
    document.querySelectorAll("#tree-body tr[data-id]").forEach((row) => {
      const id = row.dataset.id;
      const isCluster = row.classList.contains("ordo-cluster-row");
      const item = isCluster 
        ? findClusterByIdFast(id) 
        : findJobByIdFast(id);

      if (!item) return;

      const cells = row.cells;
      if (!cells) return;

      // T+ (Started)
      if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
      
      // Duration
      if (cells[6]) cells[6].textContent = formatDuration(item.started, item.ended) || "—";
      
      // T- (Next Run) - FIXED
      if (cells[7]) {
        const nextStart = Number(item.next_start);
        cells[7].textContent = (nextStart > now) 
          ? formatTminus(nextStart) 
          : "—";
      }
    });
  }

  // === SERVERS TAB ===
  const serversContent = document.getElementById("servers-content");
  if (serversContent && serversContent.offsetParent !== null) {
    document.querySelectorAll("#servers-body tr").forEach((row) => {
      const updateTime = Number(row.dataset.updateTime);
      if (isNaN(updateTime) || updateTime <= 0) return;
      const server = appState.serversData.find(s => Number(s.update_time) === updateTime);
      if (server) updateFreshnessCell(row, server, now);
    });
  }

  // === CALENDARS ===
  const calendarsContent = document.getElementById("calendars-content");
  if (calendarsContent && calendarsContent.offsetParent !== null) {
    document.querySelectorAll("#calendars-body td[data-next-start]").forEach((cell) => {
      const nextStart = Number(cell.dataset.nextStart);
      if (nextStart > now) {
        cell.textContent = formatTminus(nextStart) || "—";
      } else {
        cell.textContent = "—";
      }
    });
  }
}

export function stopLiveTimings() {
  if (liveTimingInterval) {
    clearInterval(liveTimingInterval);
    liveTimingInterval = null;
  }
  treeTimingCache = null; // clear cache
}

