// modals.js – all modal open/close/save/interaction logic
import { appState } from "./state.js";
import { showToast } from "./ui-handlers.js";
import { getFullPath, findJobById, findClusterById } from "./utils.js";

// ==================== SHARED HELPERS ====================

function resetAllModals() {
  // Reset job modal
  document.getElementById("job-modal")?.classList.remove("active");
  document.getElementById("job-modal")?.classList.remove("mode-job");

  // Reset cluster modal
  document.getElementById("cluster-modal")?.classList.remove("active");
  document.getElementById("cluster-modal")?.classList.remove("mode-cluster");

  // Reset form fields (both modals)
  [
    "job-name",
    "job-description",
    "job-script",
    "job-server",
    "job-loops",
    "job-retrys",
    "job-delay",
    "cluster-name",
    "cluster-description",
    "cluster-loops",
    "modal-needs",
    "modal-needs-any",
    "modal-on-fail",
    "job-needs",
    "job-needs-any",
    "job-on-fail",
    "cluster-needs",
    "cluster-needs-any",
    "cluster-on-fail",
    "cluster-clonable",
  ].forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      if (el.type === "number") el.value = "0";
      else if (el.tagName === "SELECT") el.value = "";
      else if (el.tagName === "TEXTAREA" || el.tagName === "INPUT")
        el.value = "";
    }
  });

  // Destroy all Tom Select instances
  [
    "job-needs",
    "job-needs-any",
    "job-on-fail",
    "cluster-needs",
    "cluster-needs-any",
    "cluster-on-fail",
  ].forEach((id) => {
    const sel = document.getElementById(id);
    if (sel?.tomselect) {
      sel.tomselect.destroy();
      sel.tomselect = null;
    }
  });
}

// ==================== JOB MODAL ====================

export function openJobModal(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  let item = null;
  if (mode === "edit" && itemId) {
    item = findJobById(appState.monitorData.tree, itemId);
  }

  appState.currentEditItem = item;
  appState.currentParentId = parentId;
  appState.currentParentName = parentName;

  const isEdit = mode === "edit";

  // Title & context
  //document.getElementById("job-modal-title").textContent = isEdit ? "Edit Job" : "New Job";
  document.getElementById("job-modal-title").innerHTML = isEdit
    ? "Edit Job"
    : "New Job <i class='fas fa-cog ml-2'></i>";
  const contextEl = document.getElementById("job-context");
  contextEl.textContent = isEdit
    ? `ID: ${item?.id || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

  // Pre-fill
  document.getElementById("job-name").value = isEdit
    ? item?.name || ""
    : "new-job";
  document.getElementById("job-description").value = isEdit
    ? item?.description || ""
    : "";
  document.getElementById("job-script").value = isEdit
    ? item?.script || ""
    : "";
  document.getElementById("job-loops").value = isEdit
    ? (item?.loops ?? 0)
    : "0";
  document.getElementById("job-retrys").value = isEdit
    ? (item?.retrys ?? 0)
    : "0";
  document.getElementById("job-delay").value = isEdit
    ? (item?.delay ?? 0)
    : "0";

  // Populate server list (single select)
  const serverSelect = document.getElementById("job-server");
  serverSelect.innerHTML = '<option value="">None / Clear</option>';

  appState.serversData.forEach((s) => {
    const opt = document.createElement("option");
    opt.value = s.name;
    opt.textContent = s.name;
    if (isEdit && s.name === item?.server_name) opt.selected = true;
    if (!isEdit && appState.serversData[0]) opt.selected = true;
    serverSelect.appendChild(opt);
  });

  // Initialize as single-select (no clear button unless added)
  initSingleSelect("job-server", item?.server_name ? [item.server_name] : []);

  // Dependencies (jobs only)
  populateJobDependencies("job-needs", item?.needs_ids || []);
  populateJobDependencies("job-needs-any", item?.needs_any_ids || []);

  // On Fail (clusters only)
  populateClusterDependencies(
    "job-on-fail",
    item?.on_fail_id ? [item.on_fail_id] : [],
  );

  // Init Tom Select
  initDependencySelect("job-needs", "clear-job-needs", item?.needs_ids || []);
  initDependencySelect(
    "job-needs-any",
    "clear-job-needs-any",
    item?.needs_any_ids || [],
  );
  initSingleSelect("job-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);

  document.getElementById("job-modal").classList.add("active");
}

// ==================== CLUSTER MODAL ====================

export function openClusterModal(
  mode = "create",
  itemId = null,
  parentId = null,
  parentName = null,
) {
  let item = null;
  if (mode === "edit" && itemId) {
    item = findClusterById(appState.monitorData.tree, itemId);
  }

  appState.currentEditItem = item;
  appState.currentParentId = parentId;
  appState.currentParentName = parentName;

  const isEdit = mode === "edit";

  // Title & context
  // document.getElementById("cluster-modal-title").textContent = isEdit ? "Edit Cluster" : "New Cluster";
  document.getElementById("cluster-modal-title").innerHTML = isEdit
    ? "Edit Cluster"
    : "New Cluster <i class='fas fa-folder ml-2'></i>";
  const contextEl = document.getElementById("cluster-context");
  contextEl.textContent = isEdit
    ? `ID: ${item?.id || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

  // Pre-fill
  document.getElementById("cluster-name").value = isEdit
    ? item?.name || ""
    : "new-cluster";
  document.getElementById("cluster-description").value = isEdit
    ? item?.description || ""
    : "";
  document.getElementById("cluster-loops").value = isEdit
    ? (item?.loops ?? 0)
    : "0";

  document.getElementById("cluster-clonable").checked =
    mode === "edit" && !!item?.clonable;

  // Dependencies (clusters only)
  populateClusterDependencies("cluster-needs", item?.needs_ids || []);
  populateClusterDependencies("cluster-needs-any", item?.needs_any_ids || []);

  // On Fail (clusters only)
  populateClusterDependencies(
    "cluster-on-fail",
    item?.on_fail_id ? [item.on_fail_id] : [],
  );

  // Init Tom Select
  initDependencySelect(
    "cluster-needs",
    "clear-cluster-needs",
    item?.needs_ids || [],
  );
  initDependencySelect(
    "cluster-needs-any",
    "clear-cluster-needs-any",
    item?.needs_any_ids || [],
  );
  initSingleSelect(
    "cluster-on-fail",
    item?.on_fail_id ? [item.on_fail_id] : [],
  );

  document.getElementById("cluster-modal").classList.add("active");
}

// ==================== SAVE FUNCTIONS ====================

function saveJob() {
  const isEdit = !!appState.currentEditItem;
  const payload = {
    command: isEdit ? "update_job" : "create_job",
    id: isEdit ? Number(appState.currentEditItem.id) : undefined,
    parent_id: !isEdit ? appState.currentParentId : undefined,
    name: document.getElementById("job-name").value.trim() || undefined,
    description:
      document.getElementById("job-description").value.trim() || undefined,
    script: document.getElementById("job-script").value.trim() || undefined,
    server: document.getElementById("job-server").value || undefined,
    loops: Number(document.getElementById("job-loops").value) || 0,
    retrys: Number(document.getElementById("job-retrys").value) || 0,
    delay: Number(document.getElementById("job-delay").value) || 0,
    needs_ids:
      document.getElementById("job-needs").tomselect?.getValue().map(Number) ||
      [],
    needs_any_ids:
      document
        .getElementById("job-needs-any")
        .tomselect?.getValue()
        .map(Number) || [],
    on_fail_id: document.getElementById("job-on-fail").tomselect?.getValue()
      ? Number(document.getElementById("job-on-fail").tomselect.getValue())
      : null,
  };

  console.log("Sending job payload:", payload);

  if (appState.ws?.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast(isEdit ? "Job updated" : "Job created", "success");
  } else {
    showToast("Not connected", "danger");
  }

  document.getElementById("job-modal").classList.remove("active");
  resetAllModals();
}

function saveCluster() {
  const isEdit = !!appState.currentEditItem;
  const payload = {
    command: isEdit ? "update_cluster" : "create_cluster",
    id: isEdit ? Number(appState.currentEditItem.id) : undefined,
    parent_id: !isEdit ? appState.currentParentId : undefined,
    name: document.getElementById("cluster-name").value.trim() || undefined,
    description:
      document.getElementById("cluster-description").value.trim() || undefined,
    loops: Number(document.getElementById("cluster-loops").value) || 0,
    needs_ids:
      document
        .getElementById("cluster-needs")
        .tomselect?.getValue()
        .map(Number) || [],
    needs_any_ids:
      document
        .getElementById("cluster-needs-any")
        .tomselect?.getValue()
        .map(Number) || [],
    clonable: document.getElementById("cluster-clonable").checked,
    on_fail_id: document.getElementById("cluster-on-fail").tomselect?.getValue()
      ? Number(document.getElementById("cluster-on-fail").tomselect.getValue())
      : null,
  };

  console.log("Sending cluster payload:", payload);

  if (appState.ws?.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast(isEdit ? "Cluster updated" : "Cluster created", "success");
  } else {
    showToast("Not connected", "danger");
  }

  document.getElementById("cluster-modal").classList.remove("active");
  resetAllModals();
}

// ==================== BUTTON LISTENERS ====================

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("save-job")?.addEventListener("click", saveJob);
  document
    .getElementById("save-cluster")
    ?.addEventListener("click", saveCluster);
  document.getElementById("cancel-job")?.addEventListener("click", () => {
    document.getElementById("job-modal").classList.remove("active");
    resetAllModals();
  });
  document.getElementById("cancel-cluster")?.addEventListener("click", () => {
    document.getElementById("cluster-modal").classList.remove("active");
    resetAllModals();
  });

  // Close buttons
  document.querySelectorAll(".close-btn[data-dismiss]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const modalId = btn.dataset.dismiss;
      document.getElementById(modalId).classList.remove("active");
      resetAllModals();
    });
  });
});

// Save attach calendar
document.getElementById("save-attach-cal")?.addEventListener("click", () => {
  const calId = document.getElementById("attach-cal-select").value;
  const payload = {
    command: "update_cluster",
    id: appState.currentAttachClusterId,
    cal_id: calId ? Number(calId) : null,
  };
  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast("Calendar updated", "info");
  } else {
    showToast("Not connected", "danger");
  }
  document.getElementById("attach-cal-modal").classList.remove("active");
});

// Log modal buttons
document.getElementById("close-log")?.addEventListener("click", () => {
  document.getElementById("log-modal").classList.remove("active");
});

document.getElementById("refresh-log")?.addEventListener("click", () => {
  const modal = document.getElementById("log-modal");
  const jobId = modal.dataset.jobId;

  if (jobId && appState.ws?.readyState === WebSocket.OPEN) {
    document.getElementById("log-modal-title").textContent =
      `Job ID: ${jobId} — Refreshing...`;
    document.getElementById("log-modal-subtitle").textContent = "";
    appState.ws.send(JSON.stringify({ command: "read_log", id: jobId }));
  }
});

document.getElementById("view-history")?.addEventListener("click", () => {
  const jobId = document.getElementById("log-modal").dataset.jobId;
  if (jobId && appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify({ command: "find_log", id: jobId }));

    const historyModal = document.getElementById("log-history-modal");
    historyModal.classList.add("active");

    // Get job name from latest log title (already set when opening log modal)
    //const latestTitle = document.querySelector("#log-modal .modal-title").textContent || "";
    //const jobPart = latestTitle.replace("Latest Log: ", "").replace(/ \(Job ID: .*\)/, "") || "Unnamed Job";

    // Set history title
    document.querySelector("#log-history-modal .modal-title").textContent =
      `Log History for Job ID ${jobId}`;
  } else {
    showToast("Not connected or no job ID", "danger");
  }
});

document.getElementById("close-log-history")?.addEventListener("click", () => {
  document.getElementById("log-history-modal").classList.remove("active");
});

// Invite team modal
document.getElementById("invite-team")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.add("active");
  document.getElementById("invite-email").value = "";
});

document.getElementById("cancel-invite")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.remove("active");
});

document.getElementById("close-invite")?.addEventListener("click", () => {
  document.getElementById("invite-modal").classList.remove("active");
});

document.getElementById("send-invite")?.addEventListener("click", () => {
  const email = document.getElementById("invite-email").value.trim();
  if (!email) {
    showToast("Enter email", "danger");
    return;
  }
  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(
      JSON.stringify({
        command: "register_user",
        email,
        team_member: "1",
      }),
    );
    showToast("Invitation sent", "success");
    document.getElementById("invite-modal").classList.remove("active");
  } else {
    showToast("Not connected", "danger");
  }
});

// Global cancel button handler (for all cancel buttons in modals)
document.addEventListener("click", (e) => {
  const cancelBtn = e.target.closest(
    '[id^="cancel-"], .btn[data-action="cancel"]',
  );
  if (cancelBtn) {
    const modal = cancelBtn.closest(".app-modal");
    if (modal) {
      modal.classList.remove("active");
    }
  }
});

function initSingleSelect(selectId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;

  if (select.tomselect) select.tomselect.destroy();

  const ts = new TomSelect(select, {
    plugins: ["remove_button"], // ← enable × for single-select
    persist: false,
    maxItems: 1, // enforce single only
    create: false,
    sortField: "text",
    valueField: "value",
    labelField: "text",
    render: {
      option: (data) =>
        `<div class="py-1 px-2 text-gray-200">${data.text}</div>`,
      item: (
        data,
      ) => `<div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center justify-between shadow-sm">
                        ${data.text}
                        <span class="custom-remove ml-2 cursor-pointer text-red-400 hover:text-red-300 font-bold">×</span>
                      </div>`,
    },
    onInitialize: function () {
      this.control.classList.add(
        "bg-gray-900",
        "border-cyan-700",
        "focus-within:ring-2",
        "focus-within:ring-cyan-500",
      );
    },
  });

  // Add click handler for custom ×
  ts.control.addEventListener("click", (e) => {
    if (e.target.classList.contains("custom-remove")) {
      ts.clear(true);
      ts.refreshOptions();
      e.stopPropagation();
    }
  });

  select.tomselect = ts;

  if (preSelectedIds.length > 0) {
    ts.addItems(preSelectedIds.map(String), true);
    ts.refreshState();
    ts.refreshOptions(false);
  }
}

function initDependencySelect(selectId, clearBtnId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`Select element not found for ID: ${selectId}`);
    return;
  }

  // Destroy previous instance safely
  if (select.tomselect) {
    select.tomselect.destroy();
    select.tomselect = null;
  }

  // Clear native selected state
  Array.from(select.options).forEach((opt) => (opt.selected = false));

  const ts = new TomSelect(select, {
    plugins: ["remove_button"],
    persist: false,
    maxItems: null,
    create: false,
    sortField: "text",
    valueField: "value",
    labelField: "text",
    render: {
      option: (data) =>
        `<div class="py-1 px-2 text-gray-200">${data.text}</div>`,
      item: (
        data,
      ) => `<div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center justify-between shadow-sm">
                        ${data.text}
                      </div>`,
    },
    onInitialize: function () {
      this.control.classList.add(
        "bg-gray-900",
        "border-cyan-700",
        "focus-within:ring-2",
        "focus-within:ring-cyan-500",
      );
    },
    onItemRemove: function (value) {
      // Force refresh after manual × removal
      this.refreshState();
      this.refreshOptions(false);
    },
  });

  select.tomselect = ts;

  // Force-add pre-selected values
  console.log(`Forcing add items to ${selectId}:`, preSelectedIds);
  if (preSelectedIds.length > 0) {
    const stringIds = preSelectedIds.map((id) => String(id));
    ts.addItems(stringIds, true);
    ts.refreshState();
    ts.refreshOptions(false);
  }

  // Clear button: robust clear
  const clearBtn = document.getElementById(clearBtnId);
  if (clearBtn) {
    clearBtn.addEventListener("click", () => {
      ts.clear(true); // clear internal state
      ts.setText(""); // clear input text
      ts.refreshState(); // update UI
      ts.refreshOptions(false); // close dropdown
      ts.blur(); // remove focus
      console.log(`Cleared ${selectId} - current values:`, ts.getValue());
    });
  }

  // Optional: log changes for debug
  ts.on("change", () => {
    console.log(`${selectId} changed to:`, ts.getValue());
  });
}

/*
// Initialize Tom Select for dependency selects
function initDependencySelect(selectId, clearBtnId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`Select element not found for ID: ${selectId}`);
    return;
  }

  // Destroy any previous Tom Select instance to prevent memory leaks/duplicates
  if (select.tomselect) {
    select.tomselect.destroy();
    select.tomselect = null;
  }

  // Clear any lingering native selected state (safety)
  Array.from(select.options).forEach(opt => {
    opt.selected = false;
  });

  // Initialize Tom Select
  const ts = new TomSelect(select, {
    plugins: ['remove_button'],           // enables × on each tag
    persist: false,
    maxItems: null,                       // allow any number of selections
    create: false,                        // no custom creation
    sortField: 'text',                    // alphabetical sorting
    valueField: 'value',
    labelField: 'text',
    render: {
      option: function(data, escape) {
        // Dropdown option (clean, minimal)
        return `<div class="py-1 px-2 text-gray-200 hover:bg-cyan-900/30">${escape(data.text)}</div>`;
      },
      item: function(data, escape) {
        // Selected tag/pill
        return `<div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center justify-between shadow-sm">
                  ${escape(data.text)}
                  <span class="remove ml-2 cursor-pointer text-red-400 hover:text-red-300 font-bold">×</span>
                </div>`;
      }
    },
    onInitialize: function() {
      // Cyberpunk focus glow
      this.control.classList.add(
        'bg-gray-900',
        'border-cyan-700',
        'focus-within:ring-2',
        'focus-within:ring-cyan-500',
        'focus-within:border-cyan-500',
        'transition-all',
        'duration-150'
      );
    }
  });

  // Store the instance
  select.tomselect = ts;

  // Force-add pre-selected values AFTER initialization
  console.log(`Forcing add items to ${selectId}:`, preSelectedIds);

  if (preSelectedIds.length > 0) {
    // Ensure values are strings (Tom Select expects string values by default)
    const stringIds = preSelectedIds.map(id => String(id));
    ts.addItems(stringIds, true);  // true = silent (no events)
    ts.refreshState();             // force UI refresh
    ts.refreshOptions(false);      // close dropdown if open
  }

  // Clear button handler
  const clearBtn = document.getElementById(clearBtnId);
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      ts.clear(true);
      ts.refreshOptions();
      console.log(`Cleared ${selectId}`);
    });
  }

  // Optional: log current values after init for debugging
  console.log(`Tom Select ${selectId} initialized with values:`, ts.getValue());
}

*/

// For job dependencies
function populateJobDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;

  select.innerHTML = '<option value="">None / Clear all</option>';

  function addJobs(items) {
    items.forEach((item) => {
      // Skip adding root as an option, but still recurse
      if (item.parent_id === null) {
        // Root - don't add option, but process children/jobs
      } else {
        // Normal node - add if it's a job
        if (!item.is_cluster) {
          const opt = document.createElement("option");
          opt.value = item.id;
          opt.textContent = getFullPath(item);
          if (selectedIds.includes(Number(item.id))) opt.selected = true;
          select.appendChild(opt);
        }
      }

      // Always recurse deeper
      if (item.children) addJobs(item.children);

      if (item.jobs && Array.isArray(item.jobs)) {
        item.jobs.forEach((job) => {
          if (
            appState.currentEditItem &&
            Number(job.id) === Number(appState.currentEditItem.id)
          )
            return;

          const opt = document.createElement("option");
          opt.value = job.id;
          opt.textContent = getFullPath(job);
          if (selectedIds.includes(Number(job.id))) opt.selected = true;
          select.appendChild(opt);
        });
      }
    });
  }

  addJobs(appState.monitorData.tree || []);
}

// For cluster dependencies (needs, needs_any, on_fail)
function populateClusterDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;

  select.innerHTML = '<option value="">None / Clear all</option>';

  function addClusters(items) {
    items.forEach((item) => {
      // Skip adding root as an option, but still recurse
      if (item.parent_id === null) {
        // Root - don't add option
      } else {
        // Normal cluster - add it
        if (item.is_cluster) {
          const opt = document.createElement("option");
          opt.value = item.id;
          opt.textContent = getFullPath(item);
          if (selectedIds.includes(Number(item.id))) opt.selected = true;
          select.appendChild(opt);
        }
      }

      // Always recurse deeper
      if (item.children) addClusters(item.children);
    });
  }

  addClusters(appState.monitorData.tree || []);
}

// Open Attach Calendar Modal
export function openAttachCalendarModal(
  clusterId,
  clusterName,
  currentCalName = "",
  currentCalId = null,
) {
  appState.currentAttachClusterId = clusterId;
  document.getElementById("attach-target-name").textContent = clusterName;
  document.getElementById("attach-current-cal").textContent =
    currentCalName || "None";
  const select = document.getElementById("attach-cal-select");
  select.innerHTML = '<option value="">None (run manually only)</option>';
  appState.calendarsData.forEach((cal) => {
    const opt = document.createElement("option");
    opt.value = cal.id;
    opt.textContent = cal.name;
    if (Number(cal.id) === Number(currentCalId)) opt.selected = true;
    select.appendChild(opt);
  });
  document.getElementById("attach-cal-modal").classList.add("active");
}

// Copy token
document.getElementById("copy-token")?.addEventListener("click", () => {
  const tokenInput = document.getElementById("account-token");
  if (!tokenInput.value) {
    showToast("No token to copy", "warning");
    return;
  }
  tokenInput.select();
  tokenInput.setSelectionRange(0, 99999);
  try {
    document.execCommand("copy");
    showToast("Token copied!", "success");
  } catch (err) {
    showToast("Failed to copy", "danger");
  }
});

// Save profile
document.getElementById("save-profile")?.addEventListener("click", () => {
  const name = document.getElementById("edit-name").value.trim();
  const mode = document.getElementById("edit-mode").value.trim();
  if (!name && !mode) {
    showToast("No changes", "info");
    return;
  }
  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(
      JSON.stringify({
        command: "update_user",
        name: name || undefined,
        mode: mode || undefined,
      }),
    );
    showToast("Profile update requested", "info");
  } else {
    showToast("Not connected", "danger");
  }
});

// Save org
document.getElementById("save-org")?.addEventListener("click", () => {
  const payload = { command: "update_org" };
  const name = document.getElementById("edit-org-name").value.trim();
  const desc = document.getElementById("edit-org-desc").value.trim();
  if (name) payload.name = name;
  if (desc) payload.description = desc;
  if (Object.keys(payload).length === 1) {
    showToast("No changes", "info");
    return;
  }
  if (appState.ws && appState.ws.readyState === WebSocket.OPEN) {
    appState.ws.send(JSON.stringify(payload));
    showToast("Organization update requested", "info");
  } else {
    showToast("Not connected", "danger");
  }
});
