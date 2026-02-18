// ui-handlers.js
import {
  appState,
  updateCollapsedClusters,
  updateCalendarCollapsed,
} from "./state.js";
import { renderJobsTable } from "./tree/tree-table.js";
import { openCronsModal } from "./modals.js";
import {
  updateRow,
  insertRow,
  removeRow,
  updateLiveTimings,
} from "./tree/tree-table.js";

import {
  formatDate,
  formatDuration,
  formatUptime,
  formatRelativeTime,
  buildTree,
  findClusterById,
  findJobById,
  getFullPath,
  removeJobById,
  removeClusterById,
} from "./utils.js";

export function showLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "block";
}

export function hideLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "none";
}

export function showToast(message, type = "info") {
  let container = document.getElementById("toast-container");
  if (!container) {
    container = document.createElement("div");
    container.id = "toast-container";
    document.body.appendChild(container);
  }

  const toast = document.createElement("div");
  toast.className = `toast ${type} show`;
  toast.setAttribute("role", "alert");
  toast.setAttribute("aria-live", "polite");

  const iconClass =
    {
      success: "check-circle",
      info: "info-circle",
      warning: "exclamation-triangle",
      danger: "times-circle",
    }[type] || "info-circle";

  toast.innerHTML = `
    <i class="fas fa-${iconClass}"></i>
    <span>${message}</span>
    <button class="close-btn" aria-label="Close">×</button>
  `;

  container.appendChild(toast);

  // Auto-dismiss
  const duration = type === "danger" ? 8000 : type === "warning" ? 6000 : 4000;
  setTimeout(() => {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 400); // fade-out duration
  }, duration);

  // Manual close
  toast.querySelector(".close-btn").onclick = () => {
    toast.classList.remove("show");
    setTimeout(() => toast.remove(), 400);
  };
}

export function updateFreshnessCell(row, server, now) {
  const updateTime =
    server.update_time != null ? Number(server.update_time) : null;
  const updatedAgo =
    updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

  let status = "Never Connected";
  let statusClass = "is-danger";
  let statusTooltip = "No stats received yet — server may still accept jobs";

  if (Number.isFinite(updatedAgo)) {
    if (updatedAgo < 30) {
      status = "Fresh";
      statusClass = "is-success";
    } else if (updatedAgo < 300) {
      status = "Stale";
      statusClass = "is-warning";
    } else {
      status = "Very Stale";
      statusClass = "is-danger";
    }
  }

  // Add zombie info to tooltip only
  if (server.zombie_processes > 0) {
    statusTooltip += `\nZombies detected: ${server.zombie_processes}`;
  }

  // Calculate current relative time (second-level precision)
  let relTime = "—";
  if (Number.isFinite(updatedAgo)) {
    relTime = formatRelativeTime(updatedAgo);
  }

  // Update tag
  const tag = row.querySelector("span.tag");
  if (tag) {
    tag.textContent = status;
    tag.className = `tag ${statusClass}`;
    tag.title = statusTooltip;
  }

  // Update inline time text
  const timeSpan = row.querySelector("td.time-text");
  if (timeSpan) {
    timeSpan.textContent = relTime;
  }

  // Stale row hint
  if (Number.isFinite(updatedAgo) && updatedAgo > 300) {
    row.classList.add("stale");
  } else {
    row.classList.remove("stale");
  }
}

export function renderServersTable() {

  const tbody = document.getElementById("servers-body");
  const table = document.getElementById("servers-table");
  const noServers = document.getElementById("no-servers");

  if (!tbody || !table || !noServers) {
    console.error("[renderServersTable] MISSING DOM ELEMENTS");
    return;
  }

  // ==================== EMPTY STATE ====================
  if (!appState.serversData || appState.serversData.length === 0) {
    table.style.display = "none";
    noServers.style.display = "block";
    return;
  }

  // Show table, hide empty state
  table.style.display = "table";
  noServers.style.display = "none";

  tbody.innerHTML = "";

  const now = Math.floor(Date.now() / 1000);

  appState.serversData.forEach((server, index) => {

    const updateTime = server.update_time != null ? Number(server.update_time) : null;
    const updatedAgo = updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

    let relTime = "—";
    if (Number.isFinite(updatedAgo)) {
      relTime = formatRelativeTime(updatedAgo);
    }

    // Load Avg
    const load1 = server.load_1 != null ? server.load_1.toFixed(2) : "—";
    const coresText = server.cores != null ? ` (on ${server.cores} cores)` : "";
    const loadTooltip = server.load_1 != null
      ? `1-min: ${server.load_1.toFixed(2)}${coresText}\n5-min: ${server.load_5?.toFixed(2) ?? "—"}\n15-min: ${server.load_15?.toFixed(2) ?? "—"}`
      : "Load averages not available";

    // CPU %
    const cpu = server.cpu_percent != null ? `${server.cpu_percent.toFixed(1)}%` : "—";
    const cpuTooltip = "True CPU utilization (user + system) from top snapshot";

    // Memory + Swap
    let mem = "—";
    let memTooltip = "Memory usage not available";
    if (server.total_memory != null && server.total_memory > 0) {
      const usedBytes = server.used_memory != null ? server.used_memory : 0;
      const totalBytes = server.total_memory;
      let unit = "GB";
      let divisor = 1024 * 1024 * 1024;
      let precision = 1;
      if (totalBytes < 10 * 1024 * 1024 * 1024) {
        unit = "MB";
        divisor = 1024 * 1024;
        precision = 2;
      }
      const usedDisplay = (usedBytes / divisor).toFixed(precision);
      const totalDisplay = (totalBytes / divisor).toFixed(precision);
      const pct = (usedBytes / totalBytes) * 100;
      const memPct = isNaN(pct) ? "—" : pct.toFixed(1);
      mem = `${memPct}% (${usedDisplay}/${totalDisplay} ${unit})`;
      const swapPct = server.total_swap != null && server.total_swap > 0
        ? (((server.used_swap || 0) / server.total_swap) * 100).toFixed(1) + "%"
        : "—";
      memTooltip = `RAM: ${memPct}% (${usedDisplay}/${totalDisplay} ${unit})\nSwap: ${swapPct}`;
    }

    // Disk (server sends values in KB)
    let disk = "—";
    let diskTooltip = "Disk usage not available";
    if (server.total_disk != null && server.total_disk > 0) {
      const usedKB = Number(server.used_disk || 0);
      const totalKB = Number(server.total_disk);
      const usedGB = usedKB / 1024 / 1024;
      const totalGB = totalKB / 1024 / 1024;

      let unit = "GB";
      let precision = 2;
      if (totalGB >= 1000) {
        unit = "TB";
        precision = 2;
      } else if (totalGB < 1) {
        unit = "MB";
        precision = 0;
      }

      const usedDisplay = usedGB.toFixed(precision);
      const totalDisplay = totalGB.toFixed(precision);
      const pct = totalGB > 0 ? (usedGB / totalGB * 100) : 0;
      const diskPct = pct.toFixed(1);

      disk = `${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})`;

      let rootInfo = "";
      if (server.root_total_disk != null && server.root_total_disk > 0) {
        const rootPct = ((server.root_used_disk || 0) / server.root_total_disk * 100).toFixed(1);
        rootInfo = `\nRoot: ${rootPct}%`;
      }
      diskTooltip = `Aggregate: ${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})${rootInfo}`;
    }

    // Uptime
    const uptime = server.uptime != null ? formatUptime(server.uptime) : "—";

    // Host tooltip
    const pingText = server.ping != null ? server.ping.toFixed(3) + "s" : "—";
    const hostTooltip = [
      `Host: ${server.host || server.ip_address || "—"}`,
      `Port: ${server.port || "—"}`,
      `Ping: ${pingText}`,
      `OS: ${server.os || "—"}`,
      `CWD: ${server.cwd || "—"}`,
      `Home: ${server.home || "—"}`,
    ].filter(Boolean).join("\n");

    // Row creation
    const tr = document.createElement("tr");
    tr.dataset.updateTime = server.update_time || "";
    tr.innerHTML = `
      <td>${server.name || "—"}</td>
      <td title="${hostTooltip}">
        ${server.host || server.ip_address || "—"}
      </td>
      <td>
        <span class="tag is-danger" title="">Never Connected</span>
      </td>
      <td class="time-text text-grey">${relTime}</td>
      <td title="${loadTooltip}">${load1}</td>
      <td title="${cpuTooltip}">${cpu}</td>
      <td title="${memTooltip}">${mem}</td>
      <td title="${diskTooltip}">${disk}</td>
      <td title="Server uptime">${uptime}</td>
      <td>
        <div class="dropdown is-right">
          <div class="dropdown-trigger">
            <button class="btn btn-sm btn-ghost" aria-haspopup="menu" title="Actions">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item" data-action="edit-server" data-id="${server.id}">Edit</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item is-danger" data-action="delete-server" data-id="${server.id}">Delete</a>
            </div>
          </div>
        </div>
      </td>
    `;
    tbody.appendChild(tr);

    updateFreshnessCell(tr, server, now);
  });

}

export function updateAccount(data) {
  appState.accountData = data;
  hideLoading("account-loading");
  document.getElementById("account-content").style.display = "block";
  renderUserProfile();
}

export function renderUserProfile() {
  if (!appState.accountData || !appState.accountData.success) return;
  document.getElementById("account-email").textContent =
    appState.accountData.email || "—";
  document.getElementById("account-id").textContent =
    appState.accountData.id || "—";
  document.getElementById("account-level").textContent =
    appState.accountData.level || "—";
  document.getElementById("edit-name").value = appState.accountData.name || "";
  document.getElementById("edit-mode").value = appState.accountData.mode || "";
  document.getElementById("account-creation").textContent =
    formatDate(appState.accountData.creation_time) || "—";
  document.getElementById("account-update").textContent =
    formatDate(appState.accountData.update_time) || "—";
  document.getElementById("account-remote").textContent =
    appState.accountData.remote_address || "—";
  document.getElementById("account-token").value =
    appState.accountData.token || "—";
}

export function updateOrgAndTeam(data) {
  appState.orgData = data;
  renderOrgTeam();
  hideLoading("account-loading");
  document.getElementById("account-content").style.display = "block";
}

export function renderOrgTeam() {
  if (!appState.orgData) return;
  document.getElementById("org-id").textContent = appState.orgData.id || "—";
  document.getElementById("edit-org-name").value = appState.orgData.name || "";
  document.getElementById("edit-org-desc").value =
    appState.orgData.description || "";
  document.getElementById("org-creation").textContent =
    formatDate(appState.orgData.creation_time) || "—";

  const teamBody = document.getElementById("team-body");
  teamBody.innerHTML = "";
  if (appState.orgData.members?.length) {
    appState.orgData.members.forEach((member) => {
      const row = document.createElement("tr");
      row.innerHTML = `
          <td>${member.email || "—"}</td>
          <td>${member.id || "—"}</td>
          <td>${member.level || "—"}</td>
          <td>${formatDate(member.creation_time) || "—"}</td>
        `;
      teamBody.appendChild(row);
    });
    document.getElementById("no-team").style.display = "none";
  } else {
    document.getElementById("no-team").style.display = "block";
  }
}

/*
export function updateLog(data) {
  document.getElementById("log-content").textContent = data.out;
  const jobId = data.job_id;
  const runId = data.id || "unknown";
  document.querySelector("#log-modal .modal-title").textContent =
    `Job ${jobId} (Run ${runId})`;
}
*/

export function updateLog(data) {
  const loading = document.getElementById("log-loading");
  const pre = document.getElementById("log-content");

  loading.style.display = "none";
  pre.style.display = "block";

  pre.textContent = data.out || "(no output captured)";
  pre.scrollTop = pre.scrollHeight;

  const jobName = data.job_name || "Unnamed Job";
  const jobId = data.job_id || "—";
  const runId = data.id || "latest"; // prefer log_id, fallback to id
  const serverName = data.server_name || "—";

  // Replace the current status calculation with this:

  let status = "Success";
  let statusClass = "success"; // for optional coloring later

  if (data.signal != null && data.signal !== 0) {
    status = `Terminated (signal ${data.signal})`;
    statusClass = "warning"; // or "danger" if you want red
  } else if (data.exit_code != null && data.exit_code !== 0) {
    status = `Failed (exit ${data.exit_code})`;
    statusClass = "danger";
  } else if (data.exit_code === 0) {
    status = "Success";
    statusClass = "success";
  } else {
    status = "—";
    statusClass = "unknown";
  }

  // Then in title:
  document.getElementById("log-modal-title").textContent =
    `Job: ${jobName} • ID: ${jobId} • Run: ${runId} (${status})`;

  // Optional: add a CSS class to the title for color
  document.getElementById("log-modal-title").className =
    `modal-title ${statusClass}`;

  // Two-line subtitle
  const startDate = data.started ? formatDate(data.started) : "—";
  const duration = formatDuration(data.started, data.ended);
  const pid = data.pid || "—";

  document.getElementById("log-modal-subtitle").innerHTML =
    `Path: ${data.job_path || "—"} • Server: ${serverName}<br>` +
    `Started: ${startDate} • Duration: ${duration} • PID: ${pid}`;
}

export function updateLogHistory(data) {
  const tbody = document.getElementById("log-history-body");
  const noHistory = document.getElementById("no-history");
  tbody.innerHTML = "";
  if (!data.logs || data.logs.length === 0) {
    noHistory.style.display = "block";
    return;
  }
  noHistory.style.display = "none";
  data.logs.forEach((log) => {
    const row = document.createElement("tr");
    row.style.cursor = "pointer";
    row.innerHTML = `
        <td>${log.id}</td>
        <td>${formatDate(log.started) || "—"}</td>
        <td>${formatDuration(log.started, log.ended) || "—"}</td>
        <td>${log.exit_code === 0 ? "Success" : (log.exit_code ?? "—")}</td>
      `;
    row.addEventListener("click", () => {
      const jobId = document.getElementById("log-modal").dataset.jobId;
      appState.ws.send(
        JSON.stringify({
          command: "read_log",
          id: jobId,
          log_id: log.id,
        }),
      );
      document.getElementById("log-history-modal").classList.remove("active");
      //document.querySelector("#log-modal .modal-title").textContent = `Run: ${id} (Job ID: ${id})`;
    });
    tbody.appendChild(row);
  });
}

/*
export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";
  if (data.success) {
    appState.monitorData.tree = buildTree(data);
    renderJobsTable();
  }
}
*/

export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";

  if (data.success) {
    appState.monitorData.tree = buildTree(data);

    // ────────────────────────────────────────────────
    // Clean up any collapsed IDs that no longer exist in the current tree
    const currentClusterIds = new Set();
    function collectClusterIds(nodes) {
      nodes.forEach((node) => {
        if (node.is_cluster) {
          currentClusterIds.add(String(node.id));
          if (node.children) collectClusterIds(node.children);
        }
      });
    }
    collectClusterIds(appState.monitorData.tree);

    let cleanedCount = 0;
    const before = [...appState.collapsedClusters];
    appState.collapsedClusters.forEach((id) => {
      if (!currentClusterIds.has(id)) {
        appState.collapsedClusters.delete(id);
        cleanedCount++;
      }
    });

    if (cleanedCount > 0) {
      updateCollapsedClusters(); // save cleaned set to localStorage
      console.log(
        `Cleaned ${cleanedCount} stale collapsed cluster ID(s):`,
        before.filter((id) => !currentClusterIds.has(id)),
      );
      // Optional: showToast(`View refreshed — removed collapsed state for ${cleanedCount} deleted cluster(s)`, "info");
    }
    // ────────────────────────────────────────────────

    renderJobsTable();
  }
}

export function updateCalendars(data) {
  hideLoading("calendars-loading");

  const content = document.getElementById("calendars-content");
  if (content) content.style.display = "block";   // ← always show the content area

  appState.calendarsData = data.cals || [];
  renderCalendarsTable();
}

export function toggleCronsRow(calendarId) {

  const cronsRow = document.querySelector(
    `tr[data-cal-id="${calendarId}"].crons-row`,
  );
  if (!cronsRow) {
    return;
  }

  const wasHidden = cronsRow.classList.contains("hidden");
  cronsRow.classList.toggle("hidden");

  // Force visibility for table rows
  if (cronsRow.classList.contains("hidden")) {
    cronsRow.style.display = "none";
  } else {
    cronsRow.style.display = "table-row";
    cronsRow.style.minHeight = "200px"; // ← temporary test height
    cronsRow.style.background = "rgba(255, 0, 0, 0.3)"; // ← temporary red tint
  }

  const isNowHidden = cronsRow.classList.contains("hidden");

  const toggleBtn = document.querySelector(
    `.dropdown-item[data-action="view-crons"][data-id="${calendarId}"]`,
  );
  if (toggleBtn) {
    toggleBtn.textContent = isNowHidden ? "View Crons" : "Hide Crons";
  } else {
    console.warn("[DEBUG] Toggle button not found for calendarId:", calendarId);
  }
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  const table = document.getElementById("calendars-table");
  const noCalendars = document.getElementById("no-calendars");

  if (!tbody || !table || !noCalendars) return;

  const calendars = appState.calendarsData || [];

  if (calendars.length === 0) {
    table.style.display = "none";
    noCalendars.style.display = "block";
    return;
  }

  // Show table, hide empty state
  table.style.display = "table";
  noCalendars.style.display = "none";

  tbody.innerHTML = "";

  calendars.forEach((cal) => {
    const hasCrons = cal.crons && cal.crons.length > 0;
    const isCollapsed = appState.collapsedCalendars.has(String(cal.id));

    const calRow = document.createElement("tr");
    calRow.className = `ordo-calendar-row ${isCollapsed ? "collapsed" : ""}`;
    calRow.dataset.id = cal.id;
    calRow.dataset.depth = 0;
    calRow.style.setProperty("--depth", "0");

    const toggleHtml = hasCrons 
      ? `<span class="ordo-toggle"></span>` 
      : `<span class="ordo-toggle empty"></span>`;

    calRow.innerHTML = `
      <td>${toggleHtml}<i class="fas fa-folder mr-2 has-text-info"></i>${cal.name || "—"}</td>
      <td>${cal.tz || "—"}</td>
      <td>${cal.description || "—"}</td>
      <td>${cal.crons?.length || 0}</td>
      <td>${cal.cluster_ids?.length || 0}</td>
      <td>—</td>
      <td>—</td>
      <td>—</td>
      <td>${generateCalendarActions(cal.id, hasCrons)}</td>
    `;

    tbody.appendChild(calRow);

    if (hasCrons) {
      (cal.crons || []).forEach((cron, idx) => {
        const isLast = idx === cal.crons.length - 1;
        const cronRow = document.createElement("tr");
        cronRow.className = `ordo-cron-row ${isCollapsed ? "hidden" : ""}`;
        cronRow.dataset.id = `cron-${cal.id}-${cron.id}`;
        cronRow.dataset.depth = 1;
        cronRow.dataset.parent = cal.id;
        cronRow.dataset.lastChild = isLast ? "true" : "false";
        cronRow.style.setProperty("--depth", "1");

        const cronIcon = '<i class="fas fa-clock mr-2 has-text-cyan"></i>';

        cronRow.innerHTML = `
          <td>${cronIcon}${cron.name || "—"}</td>
          <td>${cron.english || "—"}</td>
          <td>${cron.description || "—"}</td>
          <td>—</td>
          <td>—</td>
          <td>${cron.begin ? formatDate(cron.begin) : "Immediate"}</td>
          <td>${cron.expire ? formatDate(cron.expire) : "Never"}</td>
          <td>${formatDate(cron.next_start) || "—"}</td>
          <td>${generateCronActions(cal.id, cron.id)}</td>
        `;

        tbody.appendChild(cronRow);
      });
    }
  });
}

// Helper: calendar dropdown actions
function generateCalendarActions(calId, hasCrons) {
  return `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" role="menu">
        <div class="dropdown-content">
          <a href="#" class="dropdown-item" data-action="edit-calendar" data-id="${calId}">Edit</a>
          <a href="#" class="dropdown-item" data-action="add-cron" data-cal-id="${calId}">Add Cron</a>
          <hr class="dropdown-divider">
          <a href="#" class="dropdown-item is-danger" data-action="delete-calendar" data-id="${calId}">Delete</a>
        </div>
      </div>
    </div>
  `;
}

// Helper: cron dropdown actions
function generateCronActions(calId, cronId) {
  return `
    <div class="dropdown is-right">
      <div class="dropdown-trigger">
        <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
          <i class="fas fa-ellipsis-v"></i>
        </button>
      </div>
      <div class="dropdown-menu" role="menu">
        <div class="dropdown-content">
          <a href="#" class="dropdown-item" data-action="edit-cron" data-cal-id="${calId}" data-cron-id="${cronId}">Edit</a>
          <hr class="dropdown-divider">
          <a href="#" class="dropdown-item is-danger" data-action="delete-cron" data-cron-id="${cronId}">Delete</a>
        </div>
      </div>
    </div>
  `;
}

export function updateServers(data) {
  hideLoading("servers-loading");

  const content = document.getElementById("servers-content");
  if (content) content.style.display = "block";

  // Always set data (even if success:0)
  appState.serversData = data.success ? (data.servers || []) : [];

  renderServersTable();
}

export function applyServerBroadcast(data) {
  // Ensure the array exists
  if (!appState.serversData) {
    appState.serversData = [];
  }

  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);

      const idx = appState.serversData.findIndex((s) => Number(s.id) === id);

      if (idx !== -1) {
        // Update existing
        appState.serversData[idx] = { ...appState.serversData[idx], ...update };
      } else {
        // Add new
        appState.serversData.push(update);
      }
    });
  }

  if (data.deletes) {
    const deleteIds = data.deletes.map((d) => Number(d.id || d));
    appState.serversData = appState.serversData.filter(
      (s) => !deleteIds.includes(Number(s.id)),
    );
  }

  renderServersTable(); // ← your server render function
}

export function applyClusterBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const isCluster = true; // this broadcast is always for clusters

      // 1. Update the in-memory tree (this is the key fix)
      const clusterInTree = findClusterById(appState.monitorData.tree, id);
      if (clusterInTree) {
        Object.assign(clusterInTree, update); // update next_start + everything else
      }

      // 2. Update the DOM row
      const rowId = `row-cluster-${id}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        updateRow(existingRow, { ...update, is_cluster: true });
      } else {
        const parentId = update.parent_id || null;
        insertRow({ ...update, is_cluster: true }, parentId);
      }

      // 3. Handle jobs inside this cluster (if any)
      if (update.jobs && Array.isArray(update.jobs)) {
        update.jobs.forEach((jobUpdate) => {
          const jobId = Number(jobUpdate.id);

          // Update job in tree
          const jobInTree = findJobById(appState.monitorData.tree, jobId);
          if (jobInTree) {
            Object.assign(jobInTree, jobUpdate);
          }

          // Update job DOM row
          const jobRowId = `row-job-${jobId}`;
          const jobRow = document.getElementById(jobRowId);
          if (jobRow) {
            updateRow(jobRow, { ...jobUpdate, is_cluster: false });
          } else {
            insertRow({ ...jobUpdate, is_cluster: false }, id);
          }
        });
      }
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => {
      removeClusterById(appState.monitorData.tree, id);
      const row = document.getElementById(`row-cluster-${id}`);
      if (row) row.remove();
    });
  }

  // Refresh live timings (now sees fresh data)
  updateLiveTimings();

}

export function applyJobBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);

      // Update in-memory tree (this was missing!)
      const jobInTree = findJobById(appState.monitorData.tree, id);
      if (jobInTree) {
        Object.assign(jobInTree, update);
      }

      // Update DOM row
      const rowId = `row-job-${id}`;
      const existingRow = document.getElementById(rowId);
      if (existingRow) {
        updateRow(existingRow, { ...update, is_cluster: false });
      } else {
        // Find parent cluster and insert under it
        const parentClusterId = update.cluster_id || update.parent_id;
        if (parentClusterId) {
          insertRow({ ...update, is_cluster: false }, parentClusterId);
        }
      }
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => {
      removeJobById(appState.monitorData.tree, id); // make sure this helper exists
      const row = document.getElementById(`row-job-${id}`);
      if (row) row.remove();
    });
  }

  updateLiveTimings();
}

export function applyCalBroadcast(data) {
  if (!appState.calendarsData) {
    appState.calendarsData = [];
  }

  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);

      const idx = appState.calendarsData.findIndex((c) => Number(c.id) === id);

      if (idx !== -1) {
        appState.calendarsData[idx] = {
          ...appState.calendarsData[idx],
          ...update,
        };
      } else {
        appState.calendarsData.push(update);
      }
    });
  }

  if (data.deletes) {
    const deleteIds = data.deletes.map((d) => Number(d.id || d));
    appState.calendarsData = appState.calendarsData.filter(
      (c) => !deleteIds.includes(Number(c.id)),
    );
  }

  renderCalendarsTable();
}

export function loadDoc(file) {
  const content = document.getElementById("docs-content");
  content.innerHTML =
    '<p class="has-text-centered"><i class="fas fa-spinner fa-spin"></i> Loading...</p>';
  fetch(`/docs/${file}`)
    .then((response) => {
      if (!response.ok) throw new Error(`Failed to load ${file}`);
      return response.text();
    })
    .then((md) => {
      const html = marked.parse(md);
      document.getElementById("docs-content").innerHTML = html;

      // Safe highlight — hljs should now be defined
      if (typeof hljs !== "undefined") {
        hljs.highlightAll();
      } else {
        console.warn(
          "highlight.js failed to load — code blocks will not be highlighted",
        );
      }

      // Update active TOC link
      document
        .querySelectorAll("#docs-toc a")
        .forEach((a) => a.classList.remove("active"));
      const activeLink = document.querySelector(
        `#docs-toc a[data-file="${file}"]`,
      );
      if (activeLink) activeLink.classList.add("active");
    })
    .catch((err) => {
      document.getElementById("docs-content").innerHTML =
        `<p class="has-text-danger has-text-centered">Error: ${err.message}</p>`;
    });
}

// Mobile TOC toggle
document.getElementById("docs-toc-toggle")?.addEventListener("click", () => {
  document.getElementById("docs-toc").classList.toggle("is-open");
});

// TOC click handler
// Inside your TOC click handler
document.getElementById("docs-toc").addEventListener("click", (e) => {
  const link = e.target.closest("a");
  if (link && link.dataset.file) {
    e.preventDefault();
    loadDoc(link.dataset.file);

    const contentContainer = document.querySelector(".docs-content-container");
    if (contentContainer) {
      contentContainer.focus();
      contentContainer.scrollTop = 0; // Optional: scroll to top on new page
    }
  }
});

export function attachCalendarsTreeListeners() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;

  tbody.addEventListener("click", (e) => {
    const toggle = e.target.closest(".ordo-toggle");
    if (!toggle || toggle.classList.contains("empty")) return;

    const row = toggle.closest("tr");
    if (!row || !row.dataset.id) return;

    const calId = String(row.dataset.id);

    // Toggle collapsed state (same logic as main tree)
    const isNowCollapsed = !appState.collapsedCalendars.has(calId);

    if (isNowCollapsed) {
      appState.collapsedCalendars.add(calId);
    } else {
      appState.collapsedCalendars.delete(calId);
    }

    // Re-render the whole table (simplest and most reliable)
    renderCalendarsTable();

    // Save to localStorage
    if (typeof updateCalendarCollapsed === "function") {
      updateCalendarCollapsed();
    }
  });
}

export function attachCalendarsTreeListeners2() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;

  tbody.addEventListener("click", (e) => {
    const toggle = e.target.closest(".ordo-toggle");
    if (!toggle || toggle.classList.contains("empty")) return;

    const row = toggle.closest("tr");
    if (!row || !row.classList.contains("ordo-calendar-row")) return;

    const calId = row.dataset.id;
    const isNowCollpsed = row.classList.toggle("collapsed");

    // Persist
    if (isNowCollapsed) {
      appState.collapsedCalendars.add(calId);
    } else {
      appState.collapsedCalendars.delete(calId);
    }
    updateCalendarCollapsed();

    // Show/hide children using .hidden
    document.querySelectorAll(`tr[data-parent="${calId}"]`).forEach((child) => {
      child.classList.toggle("hidden", isNowCollapsed);
    });

    row.setAttribute(
      "aria-expanded",
      (
        !isNowCollapsed && row.querySelector(".ordo-toggle:not(.empty)")
      ).toString(),
    );
  });
}
