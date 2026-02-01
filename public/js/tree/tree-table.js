// tree/tree-table.js – Pure rendering logic only (buildRows, sort, renderJobsTable)
import { appState } from "../state.js";
import { setupDropdownFlip } from "../dropdown-handlers.js";
import {
  formatTplus,
  formatTminus,
  formatDuration,
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

  nodes.forEach(node => {
    if (node.children && node.children.length > 0) {
      sortTreeNodes(node.children);
    }
  });
}

// Main render function (called after data updates or tab activation)
export function renderJobsTable() {
  const tbody = document.getElementById("tree-body");
  if (!tbody) return;
  tbody.innerHTML = "";

  // Cleanup stale collapsed IDs
  const currentClusterIds = new Set();
  function collectIds(nodes) {
    nodes.forEach(node => {
      if (node.is_cluster) {
        currentClusterIds.add(String(node.id));
        if (node.children) collectIds(node.children);
      }
    });
  }
  collectIds(appState.monitorData.tree);

  let cleaned = false;
  const before = [...appState.collapsedClusters];
  appState.collapsedClusters.forEach(id => {
    if (!currentClusterIds.has(id)) {
      appState.collapsedClusters.delete(id);
      cleaned = true;
    }
  });
  if (cleaned) updateCollapsedClusters();

  // Sort & build
  sortTreeNodes(appState.monitorData.tree);
  buildRows(appState.monitorData.tree, tbody);

  // Re-apply dropdown flip after DOM update
  setupDropdownFlip();

  // Update timings immediately + start interval
  updateTreeTimings();
  startTreeTimings();
}

// Build table rows recursively (the core DOM builder)
export function buildRows(items, tbody, depth = 0, parentId = null) {
  const collapsedSet = appState.collapsedClusters;
  items.forEach((item, index) => {
    const isCluster = item.is_cluster;
    const hasChildren = isCluster && item.children?.length > 0;
    const state = item.jobstate?.toLowerCase() || "";
    const isRoot = item.name === "root" && item.parent_id == null;

    // Action button disabling logic
    const runDisabled =
      ["immutable", "ice", "hold"].includes(state) ||
      (state === "running" && !item.clonable)
        ? "disabled"
        : "";
    const killDisabled = state === "running" ? "" : "disabled";
    const holdDisabled = ["hold", "immutable", "ice"].includes(state) ? "disabled" : "";
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

    const isLastInSiblings = index === items.length - 1;
    if (isLastInSiblings && parentId !== null) {
      row.dataset.lastChild = "true";
    }

    const toggleHtml = item.is_cluster
      ? `<span class="ordo-toggle ${hasChildren ? '' : 'empty'}"></span>`
      : "";

    const icon = isCluster
      ? '<i class="fas fa-folder mr-2 has-text-info"></i>'
      : '<i class="fas fa-cog mr-2 has-text-grey"></i>';

    const nameHtml = `${toggleHtml}${icon}${isCluster ? item.name + "/" : item.name}`;

    // Dependencies badge + tooltip
    let depsCount = 0;
    let depsTooltipLines = [];
    const isThisCluster = !!item.is_cluster;

    if (item.needs_ids?.length) {
      depsCount += item.needs_ids.length;
      const lines = item.needs_ids.map(id =>
        `• ${resolveDepName(id, appState.monitorData.tree, isThisCluster)}`
      );
      depsTooltipLines.push(`Needs (blocking):\n${lines.join("\n")}`);
    }

    if (item.needs_any_ids?.length) {
      depsCount += item.needs_any_ids.length;
      const lines = item.needs_any_ids.map(id =>
        `• ${resolveDepName(id, appState.monitorData.tree, isThisCluster)}`
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
    const depsTitle = depsTooltipLines.length ? depsTooltipLines.join("\n\n") : "";

    // Stats badge + tooltip
    let statsDisplay = "—";
    let statsTooltipLines = [];
    if (!item.is_cluster) {
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
        item.pid !== undefined &&
        item.pctcpu == null &&
        item.pctmem == null &&
        item.rss == null
      ) {
        statsTooltipLines.push("");
        statsTooltipLines.push("Full stats not collected – run update_stats.pl");
      }
    }

    const statsTitle = statsTooltipLines.length ? statsTooltipLines.join("\n") : "";
    if (statsTitle && statsDisplay.includes("tag")) {
      const tempDiv = document.createElement("div");
      tempDiv.innerHTML = statsDisplay;
      const tag = tempDiv.querySelector(".tag");
      if (tag) tag.setAttribute("title", statsTitle);
      statsDisplay = tempDiv.innerHTML;
    }

    // Helper: menu item with data-action
    function menuItem(text, disabled = false, action = null) {
      const cls = disabled ? "dropdown-item disabled" : "dropdown-item";
      const attrs = disabled ? 'aria-disabled="true" tabindex="-1"' : "";
      const dataAction = action ? `data-action="${action}"` : "";
      return `<a href="javascript:void(0)" class="${cls}" ${attrs} ${dataAction}>${text}</a>`;
    }

    const divider = '<hr class="dropdown-divider">';

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

    const stateLower = (item.jobstate || "").toLowerCase().trim();
    const stateClass = `state-badge ${stateLower || "unknown"}`;

    row.innerHTML = `
      <td>${nameHtml}</td>
      <td><span class="${stateClass}">${item.jobstate || "—"}</span></td>
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

    if (isCluster) {
      const clusterIdStr = String(item.id);
      if (collapsedSet.has(clusterIdStr)) {
        row.classList.add("collapsed");
        row.setAttribute("aria-expanded", "false");
      } else {
        row.setAttribute("aria-expanded", "true");
      }
    }
  });
}


export function updateTreeTimings() {
  document.querySelectorAll("#tree-body tr[data-id]").forEach(row => {
    const id = row.dataset.id;
    const isClusterRow = row.classList.contains("ordo-cluster-row");
    const item = isClusterRow
      ? findClusterById(appState.monitorData.tree, id)
      : findJobById(appState.monitorData.tree, id);
    if (!item) return;

    const cells = row.cells;
    if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
    if (cells[6]) cells[6].textContent = formatDuration(item.started, item.ended) || "—";
    if (cells[7]) cells[7].textContent = formatTminus(item.next_start) || "—";
  });
}

let timingInterval = null;
export function startTreeTimings() {
  if (timingInterval) return;
  timingInterval = setInterval(updateTreeTimings, 1000);
  updateTreeTimings();
}

export function stopTreeTimings() {
  if (timingInterval) {
    clearInterval(timingInterval);
    timingInterval = null;
  }
}

