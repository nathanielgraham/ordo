// ui-handlers.js
import { appState, updateCollapsedClusters } from "./state.js";
import { renderJobsTable } from "./tree/tree-table.js";
//import { removeJobById, removeClusterById } from "./utils.js";
import { openCronsModal } from "./modals.js";

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

import { setupDropdownFlip } from "./dropdown-handlers.js";

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

export function renderServersTable() {
  const tbody = document.getElementById("servers-body");
  const noServers = document.getElementById("no-servers");
  tbody.innerHTML = "";
  if (appState.serversData.length === 0) {
    noServers.style.display = "block";
    return;
  }
  noServers.style.display = "none";

  const now = Math.floor(Date.now() / 1000);
  appState.serversData.forEach(server => {
    // 1. Freshness (tag only, base tooltip without time)
    const updateTime = server.update_time != null ? Number(server.update_time) : null;
    const updatedAgo = updateTime != null && !isNaN(updateTime) ? now - updateTime : Infinity;

/*
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
      //statusTooltip = "Stats last updated"; // timer adds time
    }

    // Add zombie info to base tooltip
    if (server.zombie_processes > 0) {
      statusTooltip += `\nZombies detected: ${server.zombie_processes}`;
    }
*/

    // 2. Load Avg
    const load1 = server.load_1 != null ? server.load_1.toFixed(2) : "—";
    const coresText = server.cores != null ? ` (on ${server.cores} cores)` : "";
    const loadTooltip = server.load_1 != null
      ? `1-min: ${server.load_1.toFixed(2)}${coresText}\n5-min: ${server.load_5?.toFixed(2) ?? "—"}\n15-min: ${server.load_15?.toFixed(2) ?? "—"}`
      : "Load averages not available";

    // 3. CPU %
    const cpu = server.cpu_percent != null ? `${server.cpu_percent.toFixed(1)}%` : "—";
    const cpuTooltip = "CPU utilization (user + system)";

    // 4. Memory + Swap
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
        ? ((server.used_swap || 0) / server.total_swap * 100).toFixed(1) + "%"
        : "—";
      memTooltip = `RAM: ${memPct}% (${usedDisplay}/${totalDisplay} ${unit})\nSwap: ${swapPct}`;
    }

    // 5. Disk + Root
    let disk = "—";
    let diskTooltip = "Disk usage not available";

    if (server.total_disk != null && server.total_disk > 0) {
      const usedBytes = server.used_disk != null ? server.used_disk : 0;
      const totalBytes = server.total_disk;

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
      const diskPct = isNaN(pct) ? "—" : pct.toFixed(1);

      disk = `${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})`;

      const rootPct = server.root_total_disk != null && server.root_total_disk > 0
        ? ((server.root_used_disk || 0) / server.root_total_disk * 100).toFixed(1) + "%"
        : "—";
      diskTooltip = `Aggregate: ${diskPct}% (${usedDisplay}/${totalDisplay} ${unit})\nRoot: ${rootPct}`;
    }

    // 6. Uptime
    const uptime = server.uptime != null ? formatUptime(server.uptime) : "—";

    // 7. Host tooltip
    const hostTooltip = [
      `Host: ${server.host || server.ip_address || "—"}`,
      `Port: ${server.port || "—"}`,
      `OS: ${server.os || "—"}`,
      `CWD: ${server.cwd || "—"}`,
      `Home: ${server.home || "—"}`
    ].filter(Boolean).join("\n");

    // 8. Row creation
    const tr = document.createElement("tr");
    tr.dataset.updateTime = server.update_time || "";
    if (Number.isFinite(updatedAgo) && updatedAgo > 300) tr.classList.add("stale");

    tr.innerHTML = `
      <td>${server.name || "—"}</td>
      <td title="${hostTooltip}">
        ${server.host || server.ip_address || "—"}
      </td>
      <td>
        <span class="tag"</span>
      </td>
      <td title="${loadTooltip}">${load1}</td>
      <td title="${cpuTooltip}">${cpu}</td>
      <td title="${memTooltip}">${mem}</td>
      <td title="${diskTooltip}">${disk}</td>
      <td title="Server uptime">${uptime}</td>
      <td>
        <div class="dropdown is-right">
          <div class="dropdown-trigger">
            <button class="btn btn-sm btn-ghost" aria-haspopup="menu">
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
  });
  setupDropdownFlip();
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
  document.getElementById("calendars-content").style.display = "block";
  if (data.success) {
    appState.calendarsData = data.cals || [];
    renderCalendarsTable();
  }
}

export function toggleCronsRow(calendarId) {
  console.log("[DEBUG] toggleCronsRow START – calendarId:", calendarId);

  const cronsRow = document.querySelector(
    `tr[data-cal-id="${calendarId}"].crons-row`,
  );
  if (!cronsRow) {
    console.warn("[DEBUG] CRONS ROW NOT FOUND – calendarId:", calendarId);
    return;
  }

  console.log(
    "[DEBUG] Found row – current classes:",
    cronsRow.className,
    "inline display:",
    cronsRow.style.display,
  );

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
  console.log(
    "[DEBUG] Toggled – was hidden:",
    wasHidden,
    "now hidden:",
    isNowHidden,
    "final display:",
    cronsRow.style.display,
  );

  const toggleBtn = document.querySelector(
    `.dropdown-item[data-action="view-crons"][data-id="${calendarId}"]`,
  );
  if (toggleBtn) {
    toggleBtn.textContent = isNowHidden ? "View Crons" : "Hide Crons";
    console.log("[DEBUG] Button text updated to:", toggleBtn.textContent);
  } else {
    console.warn("[DEBUG] Toggle button not found for calendarId:", calendarId);
  }
}

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  if (!tbody) return;
  tbody.innerHTML = "";

  appState.calendarsData.forEach((cal) => {
    const cronsCount = cal.crons?.length || 0;
    const clustersCount = cal.cluster_ids?.length || 0;

    const row = document.createElement("tr");
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
                View Crons (${cronsCount})
              </a>
            </div>
          </div>
        </div>
      </td>
    `;
    tbody.appendChild(row);
  });

  setupDropdownFlip();
}

export function updateServers(data) {
  hideLoading("servers-loading");
  document.getElementById("servers-content").style.display = "block";
  if (data.success) {
    appState.serversData = data.servers || [];
    renderServersTable();
  }
}

export function applyServerBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const idx = appState.serversData.findIndex((s) => s.id === update.id);
      if (idx !== -1)
        appState.serversData[idx] = { ...appState.serversData[idx], ...update };
      else appState.serversData.push(update);
    });
  }
  if (data.deletes) {
    data.deletes.forEach((del) => {
      appState.serversData = appState.serversData.filter(
        (s) => s.id !== (del.id || del),
      );
    });
  }
  renderServersTable();
}

export function applyClusterBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((clusterUpdate) => {
      const clusterId = Number(clusterUpdate.id);
      let clusterNode = findClusterById(appState.monitorData.tree, clusterId);

      if (clusterNode) {
        Object.assign(clusterNode, clusterUpdate);
      } else {
        const newCluster = {
          ...clusterUpdate,
          id: clusterId,
          is_cluster: true,
          children: [],
          depth: clusterUpdate.parent_id
            ? (findClusterById(
                appState.monitorData.tree,
                Number(clusterUpdate.parent_id),
              )?.depth || 0) + 1
            : 0,
        };

        if (clusterUpdate.parent_id != null) {
          const parent = findClusterById(
            appState.monitorData.tree,
            Number(clusterUpdate.parent_id),
          );
          if (parent) parent.children.push(newCluster);
          else appState.monitorData.tree.push(newCluster);
        } else {
          appState.monitorData.tree.push(newCluster);
        }

        clusterNode = newCluster;
      }

      // === MOVE THIS BLOCK HERE (after if/else) ===
      if (clusterUpdate.jobs && Array.isArray(clusterUpdate.jobs)) {
        clusterUpdate.jobs.forEach((jobUpdate) => {
          const jobId = Number(jobUpdate.id);
          let jobNode = findJobById(appState.monitorData.tree, jobId);

          if (jobNode) {
            Object.assign(jobNode, jobUpdate);
          } else {
            const newJob = {
              ...jobUpdate,
              id: jobId,
              is_cluster: false,
              depth: clusterNode.depth + 1,
            };
            clusterNode.children.push(newJob);
            console.log(
              `Added job ${jobId} to cluster ${clusterId} from broadcast`,
            );
          }
        });

        clusterNode.children.sort((a, b) => Number(a.id) - Number(b.id));
      }
      // === END ===
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) =>
      removeClusterById(appState.monitorData.tree, id),
    );
  }

  renderJobsTable();
}

export function applyJobBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      let node = findJobById(appState.monitorData.tree, id);

      if (node) {
        // Update existing job
        Object.assign(node, update);
      } else {
        // Create new job
        const parentCluster =
          update.cluster_id != null
            ? findClusterById(
                appState.monitorData.tree,
                Number(update.cluster_id),
              )
            : null;

        const newJob = {
          ...update,
          id,
          is_cluster: false,
          depth: parentCluster ? parentCluster.depth + 1 : 0,
        };

        if (parentCluster) {
          parentCluster.children.push(newJob);
          // Optional: sort children by id or name after insert
          // parentCluster.children.sort((a, b) => a.id - b.id);
        } else {
          // Fallback: add to root
          appState.monitorData.tree.push(newJob);
        }
      }
    });
  }

  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => removeJobById(appState.monitorData.tree, id));
  }

  renderJobsTable();
}

export function applyCalBroadcast(data) {
  console.log(
    "[DEBUG] applyCalBroadcast received:",
    JSON.stringify(data, null, 2),
  );

  // Log current state before update
  console.log(
    "[DEBUG] Before update – calendars count:",
    appState.calendarsData.length,
  );
  appState.calendarsData.forEach((cal) => {
    console.log(
      `[DEBUG] Cal ${cal.id} (${cal.name}) has ${cal.crons?.length || 0} crons before update`,
    );
  });

  // Handle updates – FULL REPLACE
  if (data.updates && Array.isArray(data.updates)) {
    data.updates.forEach((update) => {
      const updateId = Number(update.id);
      if (isNaN(updateId)) {
        console.warn("[DEBUG] Invalid calendar ID in update:", update);
        return;
      }

      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === updateId,
      );

      if (index !== -1) {
        const oldCrons = appState.calendarsData[index].crons?.length || 0;
        console.log(
          `[DEBUG] Replacing cal ${updateId} – old crons: ${oldCrons}, new crons: ${update.crons?.length || 0}`,
        );
        appState.calendarsData[index] = {
          ...update,
          id: updateId,
          crons: update.crons || [], // force empty array
        };
      } else {
        console.log(`[DEBUG] Adding new cal ${updateId}`);
        appState.calendarsData.push({
          ...update,
          id: updateId,
          crons: update.crons || [],
        });
      }
    });
  }

  // Handle deletes
  if (data.deletes && Array.isArray(data.deletes)) {
    const deleteIds = data.deletes
      .map((d) => Number(d.id || d))
      .filter((id) => !isNaN(id));
    const uniqueDeletes = [...new Set(deleteIds)];

    uniqueDeletes.forEach((id) => {
      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === id,
      );
      if (index !== -1) {
        console.log(`[DEBUG] Deleting calendar ${id}`);
        appState.calendarsData.splice(index, 1);
      }
    });
  }

  // Log state after update
  console.log(
    "[DEBUG] After update – calendars count:",
    appState.calendarsData.length,
  );
  appState.calendarsData.forEach((cal) => {
    console.log(
      `[DEBUG] Cal ${cal.id} (${cal.name}) has ${cal.crons?.length || 0} crons after update`,
    );
  });

  renderCalendarsTable();

  // Refresh open crons modal if affected
  const cronsModal = document.getElementById("crons-modal");
  if (cronsModal?.classList.contains("active")) {
    const openCalId = Number(cronsModal.dataset.calId);
    const wasAffected =
      data.updates?.some((u) => Number(u.id) === openCalId) ||
      data.deletes?.some((d) => Number(d.id || d) === openCalId);

    if (wasAffected) {
      console.log("[DEBUG] Refreshing open crons modal for calId:", openCalId);
      cronsModal.classList.remove("active");
      setTimeout(() => {
        console.log("[DEBUG] Re-opening crons modal after delay");
        openCronsModal(openCalId);
      }, 800);
    } else {
      console.log("[DEBUG] No refresh needed – open modal not affected");
    }
  }

  showToast("Calendars updated", "info");
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
