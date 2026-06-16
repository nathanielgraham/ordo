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
    // CPU
    if (item.pctcpu !== null && item.pctcpu !== undefined) {
      const cpu = parseFloat(item.pctcpu);
      let cpuClass = "cpu-low";
      if (cpu > 80) cpuClass = "cpu-high";
      else if (cpu > 50) cpuClass = "cpu-medium";

      statsDisplay = `<span class="stats-badge ${cpuClass}">${cpu.toFixed(1)}%</span>`;
      statsTooltipLines.push(`CPU: ${cpu.toFixed(1)}%`);
    }

    // Memory
    if (item.pctmem !== null && item.pctmem !== undefined) {
      statsTooltipLines.push(`Memory: ${parseFloat(item.pctmem).toFixed(1)}%`);
    }

    // RSS
    if (item.rss !== null && item.rss !== undefined) {
      const rssMB = Math.round(item.rss / 1024 / 1024);
      statsTooltipLines.push(`RSS: ${rssMB} MB`);
    }

    // Process Info
    if (item.pid !== null && item.pid !== undefined) {
      statsTooltipLines.push(`PID: ${item.pid}`);
    }
    if (item.ppid !== null && item.ppid !== undefined) {
      statsTooltipLines.push(`PPID: ${item.ppid}`);
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
    <td class="deps-td ${depsCount > 0 ? "has-tooltip" : ""}" data-tooltip="${depsTitle}">${depsDisplay}</td>
    <td class="stats-td ${statsTitle ? "has-tooltip" : ""}" data-tooltip="${statsTitle}">${statsDisplay}</td>
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

// ==================== INSERT FUNCTIONS (with tree sync) ====================

export function insertCluster(item, parentId = null) {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;

  const rowId = `row-cluster-${item.id}`;
  if (document.getElementById(rowId)) {
    updateClusterRow(document.getElementById(rowId), item);
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

  // === CORRECT INSERTION: After ALL siblings AND their entire job subtrees ===
  if (parentId) {
    const parentRow = document.getElementById(`row-cluster-${parentId}`);
    if (parentRow) {
      let insertionPoint = parentRow;
      let current = parentRow.nextElementSibling;

      while (current) {
        const currentDepth = Number(current.dataset.depth || 0);
        if (currentDepth <= depth) {
          // Left the subtree of the parent
          break;
        }
        insertionPoint = current;
        current = current.nextElementSibling;
      }

      insertionPoint.after(newRow);
      console.log(`[insertCluster] ✅ Inserted cluster ${item.id} after full subtree of parent ${parentId}`);
    } else {
      tbody.appendChild(newRow);
    }
  } else {
    // Root level
    tbody.appendChild(newRow);
  }

  // Tree state sync
  if (appState.monitorData?.tree) {
    let treeCluster = findClusterById(appState.monitorData.tree, item.id);
    if (!treeCluster) {
      const newCluster = { ...item, is_cluster: true, children: [] };
      if (!parentId || parentId === 1) {
        appState.monitorData.tree.push(newCluster);
      } else {
        const parent = findClusterById(appState.monitorData.tree, parentId);
        if (parent) {
          if (!parent.children) parent.children = [];
          parent.children.push(newCluster);
        }
      }
    }
  }

  // Apply collapse state if needed
  if (appState.collapsedClusters.has(String(item.id))) {
    newRow.classList.add("collapsed");
    toggleSubtree(item.id, true);
  }
}

export function insertCluster2(item, parentId = null) {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;

  const rowId = `row-cluster-${item.id}`;
  if (document.getElementById(rowId)) {
    updateClusterRow(document.getElementById(rowId), item);
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

  // === CORRECT INSERTION LOGIC ===
  // Insert after ALL sibling clusters AND after all their jobs
  if (parentId) {
    const parentRow = document.getElementById(`row-cluster-${parentId}`);
    if (parentRow) {
      let insertionPoint = parentRow;

      let current = parentRow.nextElementSibling;
      while (current) {
        const isSameParent = current.dataset.parent === String(parentId);
        if (!isSameParent) break;   // left this subtree

        insertionPoint = current;
        current = current.nextElementSibling;
      }

      insertionPoint.after(newRow);
    } else {
      tbody.appendChild(newRow);
    }
  } else {
    tbody.appendChild(newRow);
  }

  // Tree state sync
  if (appState.monitorData?.tree) {
    let treeCluster = findClusterById(appState.monitorData.tree, item.id);
    if (!treeCluster) {
      const newCluster = { ...item, is_cluster: true, children: [] };
      if (!parentId || parentId === 1) {
        appState.monitorData.tree.push(newCluster);
      } else {
        const parent = findClusterById(appState.monitorData.tree, parentId);
        if (parent) {
          if (!parent.children) parent.children = [];
          parent.children.push(newCluster);
        }
      }
    }
  }

  // Apply collapse if needed
  if (appState.collapsedClusters.has(String(item.id))) {
    newRow.classList.add("collapsed");
    toggleSubtree(item.id, true);
  }

  console.log(`[insertCluster] ✅ Inserted new cluster ${item.id} at the END of siblings under parent ${parentId}`);
}

export function insertJob(item, parentId = null) {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;

  const rowId = `row-job-${item.id}`;
  if (document.getElementById(rowId)) {
    updateJobRow(document.getElementById(rowId), item);
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

  // === INSERT AFTER ALL JOBS BUT BEFORE SUB-CLUSTERS ===
  if (parentId) {
    const parentRow = document.getElementById(`row-cluster-${parentId}`);
    if (parentRow) {
      let insertionPoint = parentRow;

      let current = parentRow.nextElementSibling;
      while (current) {
        const isSubCluster = current.classList.contains("ordo-cluster-row");
        const rowParent = current.dataset.parent;

        // Stop at the first sub-cluster or when we leave this parent's subtree
        if (
          isSubCluster ||
          (rowParent && String(rowParent) !== String(parentId))
        ) {
          break;
        }

        insertionPoint = current;
        current = current.nextElementSibling;
      }

      insertionPoint.after(newRow);
    } else {
      tbody.appendChild(newRow);
    }
  } else {
    tbody.appendChild(newRow);
  }

  // Tree state sync
  if (appState.monitorData?.tree) {
    const jobInTree = findJobById(appState.monitorData.tree, item.id);
    if (!jobInTree) {
      const parent = findClusterById(appState.monitorData.tree, parentId);
      if (parent) {
        if (!parent.jobs) parent.jobs = [];
        parent.jobs.push({ ...item, is_cluster: false });
      }
    }
  }

  console.log(
    `[insertJob] Inserted job ${item.id} AFTER jobs, BEFORE subclusters in parent ${parentId}`,
  );
}

/**
 * Updates a tooltip cell (deps or stats) safely
 */
function updateTooltipCell(cell, html, tooltipText, hasTooltip) {
  if (!cell) return;

  const currentHtml = cell.innerHTML.trim();
  const currentTooltip = cell.getAttribute("data-tooltip") || "";
  const currentlyHasTooltip = cell.classList.contains("has-tooltip");

  // Only update DOM if something actually changed
  if (
    html !== currentHtml ||
    tooltipText !== currentTooltip ||
    hasTooltip !== currentlyHasTooltip
  ) {
    cell.innerHTML = html;
    cell.setAttribute("data-tooltip", tooltipText || "");
    cell.classList.toggle("has-tooltip", hasTooltip);
  }
}

// ==================== SURGICAL UPDATE FUNCTIONS ====================

export function updateClusterRow(row, item) {
  if (!row || !item) return;

  const cells = row.cells;
  if (!cells || cells.length < 9) return;

  const state = (item.jobstate || item.state || "unknown").toLowerCase().trim();

  // 0. NAME
  if (cells[0]) {
    const nameCell = cells[0];
    const toggleHtml = '<span class="ordo-toggle"></span>';
    const icon = '<i class="fas fa-folder mr-2 has-text-info"></i>';
    nameCell.innerHTML = `${toggleHtml}${icon}${item.name}/`;
  }

  // 1. State Badge
  if (cells[1]) {
    cells[1].innerHTML = `<span class="state-badge ${state}">${item.jobstate || "—"}</span>`;
  }

  // 2. Server
  if (cells[2]) cells[2].textContent = item.server_name || "—";

  // Inside updateClusterRow function
  if (cells[3]) {
    // assuming deps is column 3
    const cell = cells[3];
    let count = 0;
    let tooltipLines = [];

    if (Array.isArray(item.needs_ids) && item.needs_ids.length) {
      count += item.needs_ids.length;
      tooltipLines.push(
        `Needs:\n${item.needs_ids
          .map(
            (id) => `• ${resolveDepName(id, appState.monitorData.tree, true)}`,
          )
          .join("\n")}`,
      );
    }
    if (Array.isArray(item.needs_any_ids) && item.needs_any_ids.length) {
      count += item.needs_any_ids.length;
      tooltipLines.push(
        `Needs Any:\n${item.needs_any_ids
          .map(
            (id) => `• ${resolveDepName(id, appState.monitorData.tree, true)}`,
          )
          .join("\n")}`,
      );
    }
    if (item.on_fail_id) {
      count += 1;
      tooltipLines.push(
        `On Fail: ${resolveDepName(item.on_fail_id, appState.monitorData.tree, true)}`,
      );
    }

    const tooltipText = tooltipLines.join("\n\n");
    const html = count > 0 ? String(count) : "—";

    // Use the helper if you added it, otherwise direct update
    cell.textContent = html;
    cell.setAttribute("data-tooltip", tooltipText);
    cell.classList.toggle("has-tooltip", count > 0);
  }

  // 4. Stats (CPU)
  if (cells[4]) {
    let html = "—";
    let tooltipLines = [];

    if (item.pctcpu != null) {
      const cpu = parseFloat(item.pctcpu);
      let cls = "cpu-low";
      if (cpu > 80) cls = "cpu-high";
      else if (cpu > 50) cls = "cpu-medium";
      html = `<span class="stats-badge ${cls}">${cpu.toFixed(1)}%</span>`;
      tooltipLines.push(`CPU: ${cpu.toFixed(1)}%`);
    }

    if (item.pctmem != null) {
      tooltipLines.push(`Memory: ${parseFloat(item.pctmem).toFixed(1)}%`);
    }
    if (item.rss != null) {
      const rssMB = Math.round(item.rss / 1024 / 1024);
      tooltipLines.push(`RSS: ${rssMB} MB`);
    }
    if (item.pid != null) {
      tooltipLines.push(`PID: ${item.pid}`);
    }
    if (item.ppid != null) {
      tooltipLines.push(`PPID: ${item.ppid}`);
    }

    const tooltipText = tooltipLines.length
      ? tooltipLines.join("\n")
      : "No stats available";

    cells[4].innerHTML = html;
    cells[4].setAttribute("data-tooltip", tooltipText);
    cells[4].classList.toggle("has-tooltip", tooltipLines.length > 0);
  }

  // 5-7. Timing columns
  if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
  if (cells[6])
    cells[6].textContent = formatDuration(item.started, item.ended) || "—";
  if (cells[7]) cells[7].textContent = formatTminus(item.next_start) || "—";

  // 8. Calendar name (important for clusters)
  if (cells[8]) {
    cells[8].textContent = item.cal_name || "—";
  }

  console.log(`[updateClusterRow] Updated cluster ${item.id}`);
}

export function updateJobRow(row, item) {
  if (!row || !item) return;

  const cells = row.cells;
  if (!cells || cells.length < 9) return;

  const state = (item.jobstate || item.state || "unknown").toLowerCase().trim();

  // 0. Name
  if (cells[0]) {
    const nameCell = cells[0];
    const icon = '<i class="fas fa-cog mr-2 has-text-grey"></i>';
    nameCell.innerHTML = `${icon}${item.name}`;
  }

  // 1. State Badge
  if (cells[1]) {
    cells[1].innerHTML = `<span class="state-badge ${state}">${item.jobstate || "—"}</span>`;
  }

  // 2. Server
  if (cells[2]) cells[2].textContent = item.server_name || "—";

  // === 3. Dependencies Tooltip ===
  if (cells[3]) {
    let count = 0;
    let tooltipLines = [];

    if (Array.isArray(item.needs_ids) && item.needs_ids.length) {
      count += item.needs_ids.length;
      tooltipLines.push(
        `Needs:\n${item.needs_ids
          .map(
            (id) => `• ${resolveDepName(id, appState.monitorData.tree, false)}`,
          )
          .join("\n")}`,
      );
    }
    if (Array.isArray(item.needs_any_ids) && item.needs_any_ids.length) {
      count += item.needs_any_ids.length;
      tooltipLines.push(
        `Needs Any:\n${item.needs_any_ids
          .map(
            (id) => `• ${resolveDepName(id, appState.monitorData.tree, false)}`,
          )
          .join("\n")}`,
      );
    }
    if (item.on_fail_id) {
      count += 1;
      tooltipLines.push(
        `On Fail: ${resolveDepName(item.on_fail_id, appState.monitorData.tree, false)}`,
      );
    }

    const tooltipText = tooltipLines.join("\n\n");
    const html = count > 0 ? String(count) : "—";

    updateTooltipCell(cells[3], html, tooltipText, count > 0);
  }

  // === 4. Stats Tooltip ===
  if (cells[4]) {
    let html = "—";
    let tooltipLines = [];
    let hasStats = false;

    if (item.pctcpu != null) {
      hasStats = true;
      const cpu = parseFloat(item.pctcpu);
      let cls = "cpu-low";
      if (cpu > 80) cls = "cpu-high";
      else if (cpu > 50) cls = "cpu-medium";

      html = `<span class="stats-badge ${cls}">${cpu.toFixed(1)}%</span>`;
      tooltipLines.push(`CPU: ${cpu.toFixed(1)}%`);
    }
    if (item.pctmem != null)
      tooltipLines.push(`Memory: ${parseFloat(item.pctmem).toFixed(1)}%`);
    if (item.rss != null)
      tooltipLines.push(`RSS: ${Math.round(item.rss / 1024 / 1024)} MB`);
    if (item.pid != null) tooltipLines.push(`PID: ${item.pid}`);
    if (item.ppid != null) tooltipLines.push(`PPID: ${item.ppid}`);

    const tooltipText = tooltipLines.length
      ? tooltipLines.join("\n")
      : "No stats available";

    updateTooltipCell(cells[4], html, tooltipText, hasStats);
  }

  // 5-7. Timing columns
  if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
  if (cells[6])
    cells[6].textContent = formatDuration(item.started, item.ended) || "—";
  if (cells[7]) cells[7].textContent = formatTminus(item.next_start) || "—";

  console.log(`[updateJobRow] Updated job ${item.id}`);
}

// ==================== REMOVE FUNCTIONS ====================

export function removeClusterRow(id) {
  const row = document.getElementById(`row-cluster-${id}`);
  if (row) row.remove();
  appState.clustersMap.delete(Number(id));
  console.log(`[removeClusterRow] Removed cluster ${id}`);
}

export function removeJobRow(id) {
  const row = document.getElementById(`row-job-${id}`);
  if (row) row.remove();
  appState.jobsMap.delete(Number(id));
  console.log(`[removeJobRow] Removed job ${id}`);
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
    rows: [],
  };

  document.querySelectorAll("#tree-body tr[data-id]").forEach((row) => {
    const cells = row.cells;
    if (cells.length < 8) return;

    treeTimingCache.rows.push({
      row: row,
      tplusCell: cells[5],
      durationCell: cells[6],
      tminusCell: cells[7],
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
      const item = isCluster ? findClusterByIdFast(id) : findJobByIdFast(id);

      if (!item) return;

      const cells = row.cells;
      if (!cells) return;

      // T+ (Started)
      if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";

      // Duration
      if (cells[6])
        cells[6].textContent = formatDuration(item.started, item.ended) || "—";

      // T- (Next Run) - FIXED
      if (cells[7]) {
        const nextStart = Number(item.next_start);
        cells[7].textContent = nextStart > now ? formatTminus(nextStart) : "—";
      }
    });
  }

  // === SERVERS TAB ===
  const serversContent = document.getElementById("servers-content");
  if (serversContent && serversContent.offsetParent !== null) {
    document.querySelectorAll("#servers-body tr").forEach((row) => {
      const updateTime = Number(row.dataset.updateTime);
      if (isNaN(updateTime) || updateTime <= 0) return;
      const server = appState.serversData.find(
        (s) => Number(s.update_time) === updateTime,
      );
      if (server) updateFreshnessCell(row, server, now);
    });
  }

  // === CALENDARS ===
  const calendarsContent = document.getElementById("calendars-content");
  if (calendarsContent && calendarsContent.offsetParent !== null) {
    document
      .querySelectorAll("#calendars-body td[data-next-start]")
      .forEach((cell) => {
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
