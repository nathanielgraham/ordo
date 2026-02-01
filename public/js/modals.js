// modals/modals.js
import { appState } from "./state.js";
import { showToast } from "./ui-handlers.js";
import { sendWS } from "./websocket.js";
import { getFullPath, findClusterById, findJobById, commonTimezones } from "./utils.js";
//import { closeAllDropdowns } from "./dropdown-handlers.js";

// ==================== TOM SELECT HELPERS ====================

/**
 * Initialize a Tom Select for dependency fields (multi-select with clear button)
 * @param {string} selectId - ID of the <select> element
 * @param {string} clearBtnId - ID of the "Clear" button
 * @param {number[]} preSelectedIds - Array of pre-selected IDs
 */

// Multi-select (needs, needs_any)
function initDependencySelect(selectId, clearBtnId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;

  if (select.tomselect) select.tomselect.destroy();

  const ts = new TomSelect(select, {
    plugins: ['remove_button'],  // built-in × for each tag
    persist: false,
    maxItems: null,
    create: false,
    sortField: 'text',
    valueField: 'value',
    labelField: 'text',
    render: {
      option: (data, escape) => `<div class="py-1 px-2 text-gray-200 hover:bg-cyan-900/30">${escape(data.text)}</div>`,
      item: (data, escape) => `<div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center shadow-sm">${escape(data.text)}</div>`,
    },
    onInitialize: function () {
      this.control.classList.add('bg-gray-900', 'border-cyan-700', 'focus-within:ring-2', 'focus-within:ring-cyan-500');
    }
  });

  select.tomselect = ts;

  if (preSelectedIds.length > 0) {
    ts.addItems(preSelectedIds.map(String), true);
    ts.refreshState();
  }

  // Clear button
  const clearBtn = document.getElementById(clearBtnId);
  if (clearBtn) {
    clearBtn.addEventListener('click', () => {
      ts.clear(true);
      ts.refreshOptions();
    });
  }
}

function initSingleSelect(selectId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;

  if (select.tomselect) select.tomselect.destroy();

  const ts = new TomSelect(select, {
    maxItems: 1,                    // single select
    plugins: ['remove_button'],     // ← enable X button for removal
    persist: false,
    create: false,
    sortField: 'text',
    valueField: 'value',
    labelField: 'text',
    render: {
      option: (data) => `<div class="py-1 px-2 text-gray-200">${data.text}</div>`,
      item: (data) => `
        <div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center justify-between shadow-sm">
          ${data.text}
        </div>`,
    },
    onInitialize: function () {
      this.control.classList.add("bg-gray-900", "border-cyan-700", "focus-within:ring-2", "focus-within:ring-cyan-500");
    }
  });

  // Custom X click handler (for single-select removal)
  ts.control.addEventListener("click", (e) => {
    if (e.target.classList.contains("remove")) {
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

// ==================== SHARED HELPERS ====================
function resetAllModals() {
  document.querySelectorAll(".app-modal").forEach((modal) => {
    modal.classList.remove("active");
  });

  // Reset form fields
  [
    "job-name",
    "job-description",
    "job-script",
    "job-loops",
    "job-retrys",
    "job-delay",
    "cluster-name",
    "cluster-description",
    "cluster-loops",
    "cluster-clonable",
    "attach-cal-select",
  ].forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      if (el.type === "checkbox") el.checked = false;
      else if (el.type === "number") el.value = "0";
      else if (el.tagName === "SELECT") el.value = "";
      else el.value = "";
    }
  });

  // Destroy Tom Select instances
  [
    "job-needs",
    "job-needs-any",
    "job-on-fail",
    "job-server",
    "cluster-needs",
    "cluster-needs-any",
    "cluster-on-fail",
    "attach-cal-select",
  ].forEach((id) => {
    const sel = document.getElementById(id);
    if (sel?.tomselect) {
      sel.tomselect.destroy();
      sel.tomselect = null;
    }
  });
}

// Populate job dependencies (needs, needs_any)
function populateJobDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`[populateJobDependencies] Select not found: ${selectId}`);
    return;
  }

  select.innerHTML = '<option value="">None / Clear all</option>';

  let optionCount = 0;

  function addJobs(nodes) {
    nodes.forEach(node => {
      console.log("[DEBUG addJobs] checking node:", node.id, node.name, node.is_cluster ? "cluster" : "job");

      // Skip root
      if (node.parent_id === null && node.name === "root") {
        console.log("[DEBUG addJobs] skipping root");
        // Still recurse into children/jobs
      } else if (!node.is_cluster) {
        // Add job
        const opt = document.createElement("option");
        opt.value = node.id;
        opt.textContent = getFullPath(node);
        if (selectedIds.includes(Number(node.id))) opt.selected = true;
        select.appendChild(opt);
        optionCount++;
        console.log("[DEBUG addJobs] Added job option:", node.id, node.name);
      }

      // Recurse children
      if (node.children) addJobs(node.children);

      // Recurse jobs array (if present on cluster)
      if (node.jobs && Array.isArray(node.jobs)) {
        node.jobs.forEach(job => {
          const opt = document.createElement("option");
          opt.value = job.id;
          opt.textContent = getFullPath(job);
          if (selectedIds.includes(Number(job.id))) opt.selected = true;
          select.appendChild(opt);
          optionCount++;
          console.log("[DEBUG addJobs] Added job from cluster jobs array:", job.id, job.name);
        });
      }
    });
  }

  addJobs(appState.monitorData.tree || []);

  console.log(`[populateJobDependencies] ${selectId} finished with ${optionCount} options added (total: ${select.options.length})`);
}

// Populate cluster dependencies (needs, needs_any, on_fail)
function populateClusterDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`[populateClusterDependencies] Select not found: ${selectId}`);
    return;
  }

  select.innerHTML = '<option value="">None / Clear all</option>';

  let optionCount = 0;

  function addClusters(nodes) {
    nodes.forEach(node => {
      console.log("[DEBUG addClusters] checking node:", node.id, node.name, node.is_cluster ? "cluster" : "job");

      // Skip root
      if (node.parent_id === null && node.name === "root") {
        console.log("[DEBUG addClusters] skipping root");
      } else if (node.is_cluster) {
        // Add cluster
        const opt = document.createElement("option");
        opt.value = node.id;
        opt.textContent = getFullPath(node);
        if (selectedIds.includes(Number(node.id))) opt.selected = true;
        select.appendChild(opt);
        optionCount++;
        console.log("[DEBUG addClusters] Added cluster option:", node.id, node.name);
      }

      // Recurse children
      if (node.children) addClusters(node.children);
    });
  }

  addClusters(appState.monitorData.tree || []);

  console.log(`[populateClusterDependencies] ${selectId} finished with ${optionCount} options added (total: ${select.options.length})`);
}

// ==================== JOB MODAL ====================
export function openJobModal(mode = "create", itemId = null, parentId = null, parentName = null) {
  let item = null;
  if (mode === "edit" && itemId) {
    item = findJobById(appState.monitorData.tree, itemId);
  }

  appState.currentEditItem = item;
  appState.currentParentId = parentId;
  appState.currentParentName = parentName;

  const isEdit = mode === "edit";

  document.getElementById("job-modal-title").textContent = isEdit ? "Edit Job" : "New Job";
  document.getElementById("job-context").textContent = isEdit
    ? `ID: ${item?.id || "—"}`
    : parentName ? `In cluster: ${parentName}` : "In root";

  // Pre-fill fields
  document.getElementById("job-name").value = isEdit ? item?.name || "" : "new-job";
  document.getElementById("job-description").value = isEdit ? item?.description || "" : "";
  document.getElementById("job-script").value = isEdit ? item?.script || "" : "";
  document.getElementById("job-loops").value = isEdit ? (item?.loops ?? 0) : "0";
  document.getElementById("job-retrys").value = isEdit ? (item?.retrys ?? 0) : "0";
  document.getElementById("job-delay").value = isEdit ? (item?.delay ?? 0) : "0";

console.log("[DEBUG modal] tree exists?", !!appState.monitorData.tree);
console.log("[DEBUG modal] tree length?", appState.monitorData.tree?.length || 0);
console.log("[DEBUG modal] item prefill:", item);

  // Populate server select
  const serverSelect = document.getElementById("job-server");
  serverSelect.innerHTML = '<option value="">None / Clear</option>';
  appState.serversData.forEach(s => {
    const opt = document.createElement("option");
    opt.value = s.name;
    opt.textContent = s.name;
    if (isEdit && s.name === item?.server_name) opt.selected = true;
    serverSelect.appendChild(opt);
  });

  // IMPORTANT: Populate dependencies FIRST (before Tom Select init)
  populateJobDependencies("job-needs", item?.needs_ids || []);
  populateJobDependencies("job-needs-any", item?.needs_any_ids || []);
  populateClusterDependencies("job-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);

// After populate calls, before initDependencySelect / initSingleSelect
console.log("[DEBUG modal] options added to cluster-needs:", document.getElementById("cluster-needs")?.options.length);
console.log("[DEBUG modal] options added to cluster-needs-any:", document.getElementById("cluster-needs-any")?.options.length);
console.log("[DEBUG modal] options added to cluster-on-fail:", document.getElementById("cluster-on-fail")?.options.length);

  // Now initialize Tom Select (options are already populated)
  initDependencySelect("job-needs", "clear-job-needs", item?.needs_ids || []);
  initDependencySelect("job-needs-any", "clear-job-needs-any", item?.needs_any_ids || []);
  initSingleSelect("job-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);
  initSingleSelect("job-server", item?.server_name ? [item.server_name] : []);

  document.getElementById("job-modal").classList.add("active");
}

// ==================== CLUSTER MODAL ====================
export function openClusterModal(mode = "create", itemId = null, parentId = null, parentName = null) {
  let item = null;
  if (mode === "edit" && itemId) {
    item = findClusterById(appState.monitorData.tree, itemId);
  }

  appState.currentEditItem = item;
  appState.currentParentId = parentId;
  appState.currentParentName = parentName;

  const isEdit = mode === "edit";

  document.getElementById("cluster-modal-title").textContent = isEdit ? "Edit Cluster" : "New Cluster";
  document.getElementById("cluster-context").textContent = isEdit
    ? `ID: ${item?.id || "—"}`
    : parentName ? `In cluster: ${parentName}` : "In root";

  document.getElementById("cluster-name").value = isEdit ? item?.name || "" : "new-cluster";
  document.getElementById("cluster-description").value = isEdit ? item?.description || "" : "";
  document.getElementById("cluster-loops").value = isEdit ? (item?.loops ?? 0) : "0";
  document.getElementById("cluster-clonable").checked = isEdit && !!item?.clonable;

  // IMPORTANT: Populate dependencies FIRST
  populateClusterDependencies("cluster-needs", item?.needs_ids || []);
  populateClusterDependencies("cluster-needs-any", item?.needs_any_ids || []);
  populateClusterDependencies("cluster-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);

  // Now initialize Tom Select
  initDependencySelect("cluster-needs", "clear-cluster-needs", item?.needs_ids || []);
  initDependencySelect("cluster-needs-any", "clear-cluster-needs-any", item?.needs_any_ids || []);
  initSingleSelect("cluster-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);

  document.getElementById("cluster-modal").classList.add("active");
}

// ==================== ATTACH CALENDAR MODAL ====================
export function openAttachCalendarModal(clusterId, clusterName, currentCalName = "", currentCalId = null) {
  appState.currentAttachClusterId = clusterId;

  const clusterNameEl = document.getElementById("attach-cluster-name");
  if (clusterNameEl) {
    clusterNameEl.textContent = clusterName || `Cluster #${clusterId}`;
  }

  const select = document.getElementById("calendar-select");
  if (!select) {
    console.error("[Attach Calendar] #calendar-select not found");
    return;
  }

  if (select.tomselect) {
    select.tomselect.destroy();
  }

  select.innerHTML = '';

  new TomSelect(select, {
    maxItems: 1,
    plugins: ['remove_button'], // ← This enables the X button for single-select
    placeholder: "Select calendar or type to search...",
    options: appState.calendarsData.map(cal => ({
      value: String(cal.id),
      text: cal.name || `Calendar ${cal.id}`
    })),
    create: false,
    sortField: 'text',
    clearButtonTitle: "Detach calendar / None",
    onInitialize: function () {
      if (currentCalId != null) {
        this.setValue(String(currentCalId));
      }
    },
    // Custom render for single item to ensure X is visible
    render: {
      item: function (data, escape) {
        return `
          <div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 flex items-center justify-between shadow-sm">
            ${escape(data.text)}
          </div>
        `;
      }
    }
  });

  document.getElementById("attach-calendar-modal").classList.add("active");
}

// modals.js – add this function

export function openConfirmModal(title = "Confirm Action", message, onConfirm, onCancel = () => {}) {
  const modal = document.getElementById("confirm-modal");
  if (!modal) {
    console.error("Confirm modal not found in DOM");
    return;
  }

  // Set dynamic content
  modal.querySelector(".modal-title").textContent = title;
  modal.querySelector("#confirm-message").textContent = message;

  // Clean up previous listeners to avoid duplicates
  const yesBtn = document.getElementById("confirm-yes");
  const noBtn = document.getElementById("confirm-no");
  const closeBtn = document.getElementById("close-confirm");

  const yesHandler = () => {
    onConfirm();
    modal.classList.remove("active");
    cleanup();
  };

  const cancelHandler = () => {
    onCancel();
    modal.classList.remove("active");
    cleanup();
  };

  const cleanup = () => {
    yesBtn.removeEventListener("click", yesHandler);
    noBtn.removeEventListener("click", cancelHandler);
    closeBtn.removeEventListener("click", cancelHandler);
  };

  yesBtn.addEventListener("click", yesHandler);
  noBtn.addEventListener("click", cancelHandler);
  closeBtn.addEventListener("click", cancelHandler);

  // Show the modal
  modal.classList.add("active");
}

// ==================== SAVE FUNCTIONS ====================
function saveJob() {
  const isEdit = !!appState.currentEditItem;
  const newName = document.getElementById("job-name").value.trim();

  const payload = {
    command: isEdit ? "update_job" : "create_job",
    id: isEdit ? Number(appState.currentEditItem.id) : undefined,
    parent_id: !isEdit ? appState.currentParentId : undefined,
    name: !isEdit ? newName : undefined, // only for create
    newname: isEdit && newName ? newName : undefined, // only for update
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

  sendWS(payload);
  showToast(isEdit ? "Job updated" : "Job created", "success");
  document.getElementById("job-modal").classList.remove("active");
  resetAllModals();
}

function saveCluster() {
  const isEdit = !!appState.currentEditItem;
  const newName = document.getElementById("cluster-name").value.trim();

  const payload = {
    command: isEdit ? "update_cluster" : "create_cluster",
    id: isEdit ? Number(appState.currentEditItem.id) : undefined,
    parent_id: !isEdit ? appState.currentParentId : undefined,
    name: !isEdit ? newName : undefined, // only for create
    newname: isEdit && newName ? newName : undefined, // only for update
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

  sendWS(payload);
  showToast(isEdit ? "Cluster updated" : "Cluster created", "success");
  document.getElementById("cluster-modal").classList.remove("active");
  resetAllModals();
}

// Save attach calendar
function saveAttachCalendar() {
  const select = document.getElementById("calendar-select");
  if (!select) {
    console.error("[Save Calendar] #calendar-select not found");
    return;
  }

  const calId = select.value;
  sendWS({
    command: "update_cluster",
    id: appState.currentAttachClusterId,
    cal_id: calId || ""  // empty = detach
  });

  showToast(calId ? "Calendar attached" : "Calendar detached", "success");
  document.getElementById("attach-calendar-modal").classList.remove("active");
};

// ==================== EVENT LISTENERS ====================
document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("save-job")?.addEventListener("click", saveJob);
  document
    .getElementById("save-cluster")
    ?.addEventListener("click", saveCluster);

  document
    .getElementById("save-calendar")
    ?.addEventListener("click", saveAttachCalendar);

  // Cancel buttons
  document.querySelectorAll("#cancel-job, #cancel-cluster").forEach((btn) => {
    btn.addEventListener("click", () => {
      btn.closest(".app-modal").classList.remove("active");
      resetAllModals();
    });
  });

  // Close buttons (generic)
  document.querySelectorAll(".close-btn[data-dismiss]").forEach((btn) => {
    btn.addEventListener("click", () => {
      const modalId = btn.dataset.dismiss;
      document.getElementById(modalId)?.classList.remove("active");
      resetAllModals();
    });
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
    if (jobId && appState.ws?.readyState === WebSocket.OPEN) {
      appState.ws.send(JSON.stringify({ command: "find_log", id: jobId }));
      document.getElementById("log-history-modal").classList.add("active");
    } else {
      showToast("Not connected or no job ID", "danger");
    }
  });

  document
    .getElementById("close-log-history")
    ?.addEventListener("click", () => {
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
    if (!email) return showToast("Enter email", "danger");
    sendWS({ command: "register_user", email, team_member: "1" });
    showToast("Invitation sent", "success");
    document.getElementById("invite-modal").classList.remove("active");
  });

  // Save profile/org (from account page)
  document.getElementById("save-profile")?.addEventListener("click", () => {
    const name = document.getElementById("edit-name").value.trim();
    const mode = document.getElementById("edit-mode").value.trim();
    if (!name && !mode) return showToast("No changes", "info");
    sendWS({
      command: "update_user",
      name: name || undefined,
      mode: mode || undefined,
    });
    showToast("Profile update requested", "info");
  });

  document.getElementById("save-org")?.addEventListener("click", () => {
    const payload = { command: "update_org" };
    const name = document.getElementById("edit-org-name").value.trim();
    const desc = document.getElementById("edit-org-desc").value.trim();
    if (name) payload.name = name;
    if (desc) payload.description = desc;
    if (Object.keys(payload).length === 1)
      return showToast("No changes", "info");
    sendWS(payload);
    showToast("Organization update requested", "info");
  });
});

// modals.js – Calendar and Cron modal logic

// Populate TZ select (common + custom fallback)
function populateTimezoneSelect() {
  const tzSelect = document.getElementById("calendar-tz");
  if (!tzSelect) return;

  tzSelect.innerHTML = '<option value="">Select common timezone...</option>';
  commonTimezones.forEach(tz => {
    const option = document.createElement("option");
    option.value = tz;
    option.textContent = tz;
    tzSelect.appendChild(option);
  });

  tzSelect.addEventListener("change", () => {
    const customInput = document.getElementById("calendar-tz-custom");
    if (tzSelect.value === "") {
      customInput.style.display = "block";
      customInput.required = true;
    } else {
      customInput.style.display = "none";
      customInput.required = false;
      customInput.value = "";
    }
  });
}

// modals.js – updated openCalendarModal with pre-fill for edit
export function openCalendarModal(mode = "create", calId = null) {
  console.log("[DEBUG] Edit mode – calId:", calId, "mode:", mode);
  const isEdit = mode === "edit";
  document.getElementById("calendar-modal-title").textContent = isEdit ? "Edit Calendar" : "Create Calendar";

  // Populate TZ select
  populateTimezoneSelect();

  // Clear form
  document.getElementById("calendar-name").value = "";
  document.getElementById("calendar-tz").value = "";
  document.getElementById("calendar-tz-custom").value = "";
  document.getElementById("calendar-tz-custom").style.display = "none";
  document.getElementById("calendar-description").value = "";

  if (isEdit && calId) {
    const cal = appState.calendarsData.find(c => c.id === Number(calId));
console.log("[DEBUG] Edit mode – calId:", calId, "found cal:", cal);
    if (cal) {
      appState.currentEditCalId = Number(calId); // ← track for save

      document.getElementById("calendar-name").value = cal.name || "";

      const tzSelect = document.getElementById("calendar-tz");
      if (commonTimezones.includes(cal.tz)) {
        tzSelect.value = cal.tz;
        document.getElementById("calendar-tz-custom").style.display = "none";
      } else {
        tzSelect.value = "";
        document.getElementById("calendar-tz-custom").value = cal.tz || "";
        document.getElementById("calendar-tz-custom").style.display = "block";
      }

      document.getElementById("calendar-description").value = cal.description || "";
    } else {
      console.warn("[Edit Calendar] Calendar not found:", calId);
      showToast("Calendar data not found", "warning");
    }
  } else {
    appState.currentEditCalId = null; // clear for create
  }

  document.getElementById("calendar-modal").classList.add("active");
}

function saveCalendar() {
  const name = document.getElementById("calendar-name")?.value.trim();
  const tzSelect = document.getElementById("calendar-tz");
  const tzCustom = document.getElementById("calendar-tz-custom")?.value.trim();
  const description = document.getElementById("calendar-description")?.value.trim();

  if (!name) {
    showToast("Name is required", "danger");
    return;
  }

  const tz = tzSelect?.value || tzCustom;
  if (!tz) {
    showToast("Timezone is required", "danger");
    return;
  }

  const isEdit = !!appState.currentEditCalId;
  const payload = {
    command: isEdit ? "update_cal" : "create_cal",
    id: isEdit ? appState.currentEditCalId : undefined,
    newname: isEdit ? name : undefined,
    name: !isEdit ? name : undefined,
    tz,
    description: description || undefined
  };

  Object.keys(payload).forEach(key => {
    if (payload[key] === undefined) delete payload[key];
  });

  sendWS(payload);
  showToast(isEdit ? "Calendar updated" : "Calendar created", "success");
  document.getElementById("calendar-modal").classList.remove("active");

  // Clear state after save
  appState.currentEditCalId = null;
}

// Cron modal open
function openCronModal(mode = "create", calId, cron = null) {
  //closeAllDropdowns(); // ← close dropdowns when modal opens

  const isEdit = mode === "edit";
  document.getElementById("cron-modal-title").textContent = isEdit ? "Edit Cron" : "Add Cron";

  // Pre-fill if edit
  document.getElementById("cron-expression").value = isEdit ? cron?.name || "" : "";
  document.getElementById("cron-description").value = isEdit ? cron?.description || "" : "";
  document.getElementById("cron-begin").value = isEdit ? cron?.begin || "" : "";
  document.getElementById("cron-expire").value = isEdit ? cron?.expire || "" : "";

  // Store calId and cronId for save
  const modal = document.getElementById("cron-modal");
  modal.dataset.calId = calId;
  modal.dataset.cronId = isEdit ? cron?.id : "";

  modal.classList.add("active");
}

// Save cron
function saveCron() {
  const modal = document.getElementById("cron-modal");
  const calId = modal.dataset.calId;
  const cronId = modal.dataset.cronId;
  const isEdit = !!cronId;

  const name = document.getElementById("cron-expression")?.value.trim();
  const description = document.getElementById("cron-description")?.value.trim();
  const begin = document.getElementById("cron-begin")?.value.trim();
  const expire = document.getElementById("cron-expire")?.value.trim();

  if (!name) {
    showToast("Cron expression is required", "danger");
    return;
  }

  const payload = {
    command: isEdit ? "update_cron" : "create_cron",
    id: isEdit ? Number(cronId) : undefined,
    cal_id: Number(calId),
    name,
    description: description || undefined,
    begin: begin ? Number(begin) : undefined,
    expire: expire ? Number(expire) : undefined
  };

  sendWS(payload);
  showToast(isEdit ? "Cron updated" : "Cron added", "success");
  modal.classList.remove("active");
}

// Initialize all listeners once on DOM ready
document.addEventListener("DOMContentLoaded", () => {
  // Save calendar
  document.getElementById("save-calendar")?.addEventListener("click", saveCalendar);

  // Create calendar button
  document.getElementById("create-calendar-btn")?.addEventListener("click", () => {
    openCalendarModal("create");
  });

  // Save cron
  document.getElementById("save-cron")?.addEventListener("click", saveCron);

  // Delegated click handler for add/edit/delete cron (table buttons)
  document.addEventListener("click", e => {
    const target = e.target;

    if (target.classList.contains("add-cron")) {
      const calId = target.dataset.calId;
      openCronModal("create", calId);
    }

    if (target.classList.contains("edit-cron")) {
      const cronId = target.dataset.cronId;
      const calId = target.dataset.calId;
      const cal = appState.calendarsData.find(c => c.id == calId);
      const cron = cal?.crons.find(c => c.id == cronId);
      if (cron) openCronModal("edit", calId, cron);
    }

    if (target.classList.contains("delete-cron")) {
      const cronId = target.dataset.cronId;
      openConfirmModal(
        "Confirm Delete Cron",
        "Are you sure you want to delete this cron expression?",
        () => {
          sendWS({
            command: "delete_cron",
            id: cronId
          });
          showToast("Cron deleted", "success");
        }
      );
    }
  });
});

