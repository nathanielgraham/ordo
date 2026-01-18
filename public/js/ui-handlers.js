// ui-handlers.js 
import { appState, updateCollapsedClusters } from "./state.js";
import { renderJobsTable } from './tree-table.js';

import {
  formatDate,
  formatDuration,
  buildTree,
  findClusterById,
  findJobById,
  getFullPath
} from './utils.js';

export function showLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "block";
}

export function hideLoading(containerId) {
  const loading = document.getElementById(containerId);
  if (loading) loading.style.display = "none";
}

export function showToast(message, type = "info") {
  const toast = document.createElement("div");
  toast.className = `notification is-${type}`;
  toast.innerHTML = `<button class="delete"></button><span>${message}</span>`;
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
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

export function updateLog(data) {
  document.getElementById("log-content").textContent = data.out;
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
      document
        .getElementById("log-history-modal")
        .classList.remove("is-active");
      document.querySelector("#log-modal .modal-card-title").textContent =
        `Job Log - Run #${log.id}`;
    });
    tbody.appendChild(row);
  });
}

export function updateJobsClusters(data) {
  hideLoading("monitor-loading");
  document.getElementById("monitor-content").style.display = "block";
  if (data.success) {
    appState.monitorData.tree = buildTree(data);
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

export function renderCalendarsTable() {
  const tbody = document.getElementById("calendars-body");
  tbody.innerHTML = "";
  appState.calendarsData.forEach((cal) => {
    const row = document.createElement("tr");
    row.innerHTML = `
        <td>${cal.name || "—"}</td>
        <td>${cal.type || "—"}</td>
        <td>${cal.cron || "—"}</td>
        <td><span class="tag is-light">${cal.state || "—"}</span></td>
        <td>
          <div class="dropdown">
            <div class="dropdown-trigger">
              <button class="button is-small is-light" aria-haspopup="true" aria-controls="dropdown-menu">
                <i class="fas fa-ellipsis-v"></i>
              </button>
            </div>
            <div class="dropdown-menu" role="menu">
              <div class="dropdown-content">
                <a href="#" class="dropdown-item">Edit</a>
                <hr class="dropdown-divider">
                <a href="#" class="dropdown-item is-danger">Delete</a>
              </div>
            </div>
          </div>
        </td>
      `;
    tbody.appendChild(row);
  });
}

export function updateServers(data) {
  hideLoading("servers-loading");
  document.getElementById("servers-content").style.display = "block";
  if (data.success) {
    appState.serversData = data.servers || [];
    renderServersTable();
  }
}

export function renderServersTable() {
  const tbody = document.getElementById("servers-body");
  tbody.innerHTML = "";
  appState.serversData.forEach((server) => {
    const row = document.createElement("tr");
    row.innerHTML = `
        <td>${server.name || "—"}</td>
        <td><span class="tag ${server.status === "online" ? "is-success" : "is-danger"}">${server.status || "—"}</span></td>
        <td>${server.load || "—"}</td>
        <td>
          <div class="dropdown">
            <div class="dropdown-trigger">
              <button class="button is-small is-light" aria-haspopup="true" aria-controls="dropdown-menu">
                <i class="fas fa-ellipsis-v"></i>
              </button>
            </div>
            <div class="dropdown-menu" role="menu">
              <div class="dropdown-content">
                <a href="#" class="dropdown-item">Edit</a>
                <hr class="dropdown-divider">
                <a href="#" class="dropdown-item is-danger">Delete</a>
              </div>
            </div>
          </div>
        </td>
      `;
    tbody.appendChild(row);
  });
}

export function applyClusterBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      let node = findClusterById(appState.monitorData.tree, update.id);
      if (node) {
        Object.assign(node, update);
      } else {
        const newNode = {
          ...update,
          id: Number(update.id),
          type: "cluster",
          is_cluster: true,
          children: [],
          depth: 0,
        };
        if (update.parent_id != null) {
          const parent = findClusterById(
            appState.monitorData.tree,
            update.parent_id,
          );
          if (parent) parent.children.push(newNode);
          else appState.monitorData.tree.push(newNode);
        } else {
          appState.monitorData.tree.push(newNode);
        }
      }
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
      let node = findJobById(appState.monitorData.tree, update.id);
      if (node) {
        Object.assign(node, update);
      } else {
        const newNode = {
          ...update,
          id: Number(update.id),
          type: "job",
          is_cluster: false,
          depth: 0,
        };
        if (update.cluster_id != null) {
          const parent = findClusterById(
            appState.monitorData.tree,
            update.cluster_id,
          );
          if (parent) parent.children.push(newNode);
          else appState.monitorData.tree.push(newNode);
        } else {
          appState.monitorData.tree.push(newNode);
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
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === id,
      );
      if (index !== -1) {
        appState.calendarsData[index] = {
          ...appState.calendarsData[index],
          ...update,
        };
      } else {
        appState.calendarsData.push({ ...update, id });
      }
    });
  }
  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => {
      const index = appState.calendarsData.findIndex(
        (cal) => Number(cal.id) === id,
      );
      if (index !== -1) appState.calendarsData.splice(index, 1);
    });
  }
  renderCalendarsTable();
}

export function applyServerBroadcast(data) {
  if (data.updates) {
    data.updates.forEach((update) => {
      const id = Number(update.id);
      const index = appState.serversData.findIndex((s) => Number(s.id) === id);
      if (index !== -1) {
        appState.serversData[index] = {
          ...appState.serversData[index],
          ...update,
        };
      } else {
        appState.serversData.push({ ...update, id });
      }
    });
  }
  if (data.deletes) {
    const uniqueDeletes = [
      ...new Set(data.deletes.map((d) => Number(d.id || d))),
    ];
    uniqueDeletes.forEach((id) => {
      const index = appState.serversData.findIndex((s) => Number(s.id) === id);
      if (index !== -1) appState.serversData.splice(index, 1);
    });
  }
  renderServersTable();
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
        .forEach((a) => a.classList.remove("is-active"));
      const activeLink = document.querySelector(
        `#docs-toc a[data-file="${file}"]`,
      );
      if (activeLink) activeLink.classList.add("is-active");
    })
    .catch((err) => {
      document.getElementById("docs-content").innerHTML =
        `<p class="has-text-danger has-text-centered">Error: ${err.message}</p>`;
    });
}

  // Load Quickstart on first open
  const quickstartLink = document.querySelector(
    '#docs-toc a[data-file="quickstart.md"]',
  ); 
  if (quickstartLink) {
    quickstartLink.click(); // Triggers your existing TOC handler → loads Quickstart
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

      const contentContainer = document.querySelector(
        ".docs-content-container",
      );
      if (contentContainer) {
        contentContainer.focus();
        contentContainer.scrollTop = 0; // Optional: scroll to top on new page
      }
    }
  });



