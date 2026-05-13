// modals.js
import { appState } from "./state.js";
import { showToast, renderCalendarsTable } from "./ui-handlers.js";
import { sendWS } from "./websocket.js";
import {
  getFullPath,
  findClusterById,
  findJobById,
  commonTimezones,
  formatDate,
} from "./utils.js";

// ==================== TOM SELECT HELPERS ====================
function initDependencySelect(selectId, clearBtnId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return console.warn(`Select not found: ${selectId}`);
  if (select.tomselect) select.tomselect.destroy();

  const ts = new TomSelect(select, {
    plugins: ["remove_button"],
    persist: false,
    maxItems: null,
    create: false,
    sortField: "text",
    valueField: "value",
    labelField: "text",
    render: {
      option: (data, escape) =>
        `<div class="py-1 px-2 text-gray-200 hover:bg-cyan-900/30">${escape(data.text)}</div>`,
      item: (data, escape) =>
        `<div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center shadow-sm">${escape(data.text)}</div>`,
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
  select.tomselect = ts;

  if (preSelectedIds.length > 0) {
    ts.addItems(preSelectedIds.map(String), true);
  }

  const clearBtn = document.getElementById(clearBtnId);
  if (clearBtn) {
    clearBtn.addEventListener("click", () => ts.clear(true));
  }
}

function initSingleSelect(selectId, preSelectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) return;
  if (select.tomselect) select.tomselect.destroy();

  const ts = new TomSelect(select, {
    maxItems: 1,
    plugins: ["remove_button"],
    persist: false,
    create: false,
    sortField: "text",
    valueField: "value",
    labelField: "text",
    render: {
      option: (data) =>
        `<div class="py-1 px-2 text-gray-200">${data.text}</div>`,
      item: (data) => `
        <div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 m-1 flex items-center justify-between shadow-sm">
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
  });

  select.tomselect = ts;

  if (preSelectedIds.length > 0) {
    ts.addItems(preSelectedIds.map(String), true);
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
    "calendar-name",
    "calendar-tz",
    "calendar-tz-custom",
    "calendar-description",
    "cron-expression",
    "cron-description",
    "cron-begin",
    "cron-expire",
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
  document.getElementById("job-modal-title").textContent = isEdit
    ? "Edit Job"
    : "New Job";
  document.getElementById("job-context").textContent = isEdit
    ? `ID: ${item?.id || "—"}`
    : parentName
      ? `In cluster: ${parentName}`
      : "In root";

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

  // Populate server select
  const serverSelect = document.getElementById("job-server");
  serverSelect.innerHTML = '<option value="">None / Clear</option>';
  appState.serversData.forEach((s) => {
    const opt = document.createElement("option");
    opt.value = s.name;
    opt.textContent = s.name;
    if (isEdit && s.name === item?.server_name) opt.selected = true;
    serverSelect.appendChild(opt);
  });

  // Populate dependencies
  populateJobDependencies("job-needs", item?.needs_ids || []);
  populateJobDependencies("job-needs-any", item?.needs_any_ids || []);
  populateClusterDependencies(
    "job-on-fail",
    item?.on_fail_id ? [item.on_fail_id] : [],
  );

  // Initialize Tom Select
  initDependencySelect("job-needs", "clear-job-needs", item?.needs_ids || []);
  initDependencySelect(
    "job-needs-any",
    "clear-job-needs-any",
    item?.needs_any_ids || [],
  );
  initSingleSelect("job-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);
  initSingleSelect("job-server", item?.server_name ? [item.server_name] : []);

  document.getElementById("job-modal").classList.add("active");
}

// ==================== SERVER MODAL ====================
export function openServerModal(mode = "create", serverData = null) {
  const modal = document.getElementById('server-modal');
  if (!modal) {
    console.error("Server modal element not found");
    return;
  }

  const titleEl = document.getElementById('server-modal-title');
  
  if (mode === "edit" && serverData) {
    titleEl.textContent = "Edit Server";
    document.getElementById('server-name').value = serverData.name || '';
    document.getElementById('server-host').value = serverData.host || serverData.ip_address || '';
    document.getElementById('server-user').value = serverData.user || '';
    document.getElementById('server-port').value = serverData.port || '22';
    // Do NOT prefill password for security
    appState.currentEditServerId = serverData.id;
  } else {
    // Create mode
    titleEl.textContent = "Add Server";
    document.getElementById('server-name').value = '';
    document.getElementById('server-host').value = '';
    document.getElementById('server-user').value = '';
    document.getElementById('server-port').value = '22';
    document.getElementById('server-password').value = '';
    appState.currentEditServerId = null;
  }

  modal.classList.add('active');
  document.getElementById('server-name').focus();
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

  // Safe element access
  const titleEl = document.getElementById("cluster-modal-title");
  if (titleEl) titleEl.textContent = isEdit ? "Edit Cluster" : "New Cluster";

  const contextEl = document.getElementById("cluster-context");
  if (contextEl) {
    contextEl.textContent = isEdit
      ? `ID: ${item?.id || "—"}`
      : parentName
        ? `In cluster: ${parentName}`
        : "In root";
  }

  const nameEl = document.getElementById("cluster-name");
  if (nameEl) nameEl.value = isEdit ? (item?.name || "") : "new-cluster";

  const descEl = document.getElementById("cluster-description");
  if (descEl) descEl.value = isEdit ? (item?.description || "") : "";

  const loopsEl = document.getElementById("cluster-loops");
  if (loopsEl) loopsEl.value = isEdit ? (item?.loops ?? 0) : "0";

  const clonableEl = document.getElementById("cluster-clonable");
  if (clonableEl) clonableEl.checked = isEdit && !!item?.clonable;

  // Populate dependencies (safe)
  populateClusterDependencies("cluster-needs", item?.needs_ids || []);
  populateClusterDependencies("cluster-needs-any", item?.needs_any_ids || []);
  populateClusterDependencies(
    "cluster-on-fail",
    item?.on_fail_id ? [item.on_fail_id] : [],
  );

  // Initialize Tom Selects (safe)
  initDependencySelect("cluster-needs", "clear-cluster-needs", item?.needs_ids || []);
  initDependencySelect("cluster-needs-any", "clear-cluster-needs-any", item?.needs_any_ids || []);
  initSingleSelect("cluster-on-fail", item?.on_fail_id ? [item.on_fail_id] : []);

  // Finally show the modal
  const modal = document.getElementById("cluster-modal");
  if (modal) modal.classList.add("active");
}

// ==================== ATTACH CALENDAR MODAL ====================
export function openAttachCalendarModal(
  clusterId,
  clusterName,
  currentCalName = "",
  currentCalId = null,
) {
  appState.currentAttachClusterId = clusterId;

  const clusterNameEl = document.getElementById("attach-cluster-name");
  if (clusterNameEl)
    clusterNameEl.textContent = clusterName || `Cluster #${clusterId}`;

  const select = document.getElementById("calendar-select");
  if (!select)
    return console.error("[Attach Calendar] #calendar-select not found");

  if (select.tomselect) select.tomselect.destroy();
  select.innerHTML = "";

  new TomSelect(select, {
    maxItems: 1,
    plugins: ["remove_button"],
    placeholder: "Select calendar or type to search...",
    options: appState.calendarsData.map((cal) => ({
      value: String(cal.id),
      text: cal.name || `Calendar ${cal.id}`,
    })),
    create: false,
    sortField: "text",
    clearButtonTitle: "Detach calendar / None",
    onInitialize: function () {
      if (currentCalId != null) this.setValue(String(currentCalId));
    },
    render: {
      item: (data, escape) => `
        <div class="item bg-gray-800 text-cyan-200 border border-cyan-800 rounded px-2 py-1 flex items-center justify-between shadow-sm">
          ${escape(data.text)}
        </div>`,
    },
  });

  document.getElementById("attach-calendar-modal").classList.add("active");
}

// ==================== CONFIRM MODAL ====================
export function openConfirmModal(title = "Confirm", message = "Are you sure?", onConfirm = null, onCancel = null) {
  const modal = document.getElementById("confirm-modal");
  if (!modal) {
    console.error("[openConfirmModal] Modal not found");
    return;
  }

  // Set title and message
  const titleEl = modal.querySelector(".modal-title");
  if (titleEl) titleEl.textContent = title;

  const msgEl = document.getElementById("confirm-message");
  if (msgEl) msgEl.textContent = message;

  // Get buttons
  const yesBtn = document.getElementById("confirm-yes");
  const noBtn  = document.getElementById("confirm-no");

  if (!yesBtn) {
    console.error("[openConfirmModal] #confirm-yes button missing");
    modal.classList.add("active");
    return;
  }

  // Clone buttons to clear old listeners
  const newYes = yesBtn.cloneNode(true);
  yesBtn.parentNode.replaceChild(newYes, yesBtn);

  if (noBtn) {
    const newNo = noBtn.cloneNode(true);
    noBtn.parentNode.replaceChild(newNo, noBtn);

    // No button = cancel
    newNo.addEventListener("click", () => {
      modal.classList.remove("active");
      if (typeof onCancel === "function") onCancel();
    });
  }

  // Yes button = confirm / delete
  newYes.addEventListener("click", () => {
    modal.classList.remove("active");
    if (typeof onConfirm === "function") onConfirm();
  });

  modal.classList.add("active");
}

// ==================== CALENDAR MODAL ====================
function populateTimezoneSelect() {
  const tzSelect = document.getElementById("calendar-tz");
  if (!tzSelect) return;

  tzSelect.innerHTML = '<option value="">Select common timezone...</option>';
  commonTimezones.forEach((tz) => {
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

function populateJobDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`[populateJobDependencies] Select not found: ${selectId}`);
    return;
  }
  select.innerHTML = '<option value="">None / Clear all</option>';
  let optionCount = 0;
  function addJobs(nodes) {
    nodes.forEach((node) => {
      console.log(
        "[DEBUG addJobs] checking node:",
        node.id,
        node.name,
        node.is_cluster ? "cluster" : "job",
      );
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
        node.jobs.forEach((job) => {
          const opt = document.createElement("option");
          opt.value = job.id;
          opt.textContent = getFullPath(job);
          if (selectedIds.includes(Number(job.id))) opt.selected = true;
          select.appendChild(opt);
          optionCount++;
          console.log(
            "[DEBUG addJobs] Added job from cluster jobs array:",
            job.id,
            job.name,
          );
        });
      }
    });
  }
  addJobs(appState.monitorData.tree || []);
  console.log(
    `[populateJobDependencies] ${selectId} finished with ${optionCount} options added (total: ${select.options.length})`,
  );
}

function populateClusterDependencies(selectId, selectedIds = []) {
  const select = document.getElementById(selectId);
  if (!select) {
    console.warn(`[populateClusterDependencies] Select not found: ${selectId}`);
    return;
  }
  select.innerHTML = '<option value="">None / Clear all</option>';
  let optionCount = 0;
  function addClusters(nodes) {
    nodes.forEach((node) => {
      console.log(
        "[DEBUG addClusters] checking node:",
        node.id,
        node.name,
        node.is_cluster ? "cluster" : "job",
      );
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
        console.log(
          "[DEBUG addClusters] Added cluster option:",
          node.id,
          node.name,
        );
      }
      // Recurse children
      if (node.children) addClusters(node.children);
    });
  }
  addClusters(appState.monitorData.tree || []);
  console.log(
    `[populateClusterDependencies] ${selectId} finished with ${optionCount} options added (total: ${select.options.length})`,
  );
}

// utils.js or modals.js
function getTimezoneOptions() {
  const options = [];

  // Modern browsers: full IANA list
  if (Intl && Intl.supportedValuesOf) {
    const timezones = Intl.supportedValuesOf("timeZone");
    timezones.forEach((tz) => {
      // Optional: friendly name with offset (dynamic)
      const formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: tz,
        timeZoneName: "long",
      });
      const parts = formatter.formatToParts(new Date());
      const tzName = parts.find((p) => p.type === "timeZoneName")?.value || tz;
      options.push({
        value: tz,
        text: `${tz} – ${tzName}`,
      });
    });
  } else {
    // Static fallback - large curated list (add more as needed)
    const staticTz = [
      "UTC",
      "America/New_York – Eastern Time (US & Canada)",
      "America/Chicago – Central Time (US & Canada)",
      "America/Denver – Mountain Time (US & Canada)",
      "America/Los_Angeles – Pacific Time (US & Canada)",
      "Europe/London – GMT / BST",
      "Europe/Paris – Central European Time",
      "Europe/Berlin – Central European Time",
      "Asia/Tokyo – Japan Standard Time",
      "Asia/Shanghai – China Standard Time",
      "Asia/Singapore – Singapore Time",
      "Australia/Sydney – Eastern Time (Australia)",
      "Pacific/Auckland – New Zealand Time",
      // ... add 100+ more major ones
    ];
    staticTz.forEach((tz) => {
      options.push({ value: tz.split(" – ")[0], text: tz });
    });
  }

  // Sort alphabetically by text
  options.sort((a, b) => a.text.localeCompare(b.text));

  return options;
}

export function openCalendarModal(mode = "create", calId = null) {
  const isEdit = mode === "edit";
  document.getElementById("calendar-modal-title").textContent = isEdit
    ? "Edit Calendar"
    : "Create Calendar";

  // Populate Tom Select for timezone
  const tzSelect = document.getElementById("calendar-tz");
  if (tzSelect.tomselect) tzSelect.tomselect.destroy(); // clean up previous

  const tom = new TomSelect(tzSelect, {
    maxItems: 1,
    plugins: ["remove_button"],
    placeholder: "Type to search or select timezone...",
    searchField: ["text", "value"],
    options: getTimezoneOptions(), // large list - see below
    render: {
      option: (data) => `<div>${data.text}</div>`,
      item: (data) => `<div class="item">${data.text}</div>`,
    },
    onInitialize: function () {
      // Default to browser's local timezone on create
      if (!isEdit) {
        const localTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
        if (this.options[localTz]) {
          this.setValue(localTz);
        } else {
          // Fallback: show custom input pre-filled
          document.getElementById("calendar-tz-custom").value = localTz;
          document.getElementById("calendar-tz-custom").style.display = "block";
        }
      }
    },
  });

  tzSelect.tomselect = tom;

  // Show/hide custom input based on selection
  tom.on("change", () => {
    const customInput = document.getElementById("calendar-tz-custom");
    if (tom.getValue() === "") {
      customInput.style.display = "block";
      customInput.required = true;
    } else {
      customInput.style.display = "none";
      customInput.required = false;
      customInput.value = "";
    }
  });

  document.getElementById("calendar-name").value = "";
  document.getElementById("calendar-tz").value = "";
  document.getElementById("calendar-tz-custom").value = "";
  document.getElementById("calendar-tz-custom").style.display = "none";
  document.getElementById("calendar-description").value = "";

  // ... rest of modal population (name, description, edit pre-fill)
  if (isEdit && calId) {
    const cal = appState.calendarsData.find((c) => c.id === Number(calId));
    if (cal) {
      appState.currentEditCalId = Number(calId);
      document.getElementById("calendar-name").value = cal.name || "";
      // Set Tom Select value (or custom)
      if (tom.options[cal.tz]) {
        tom.setValue(cal.tz);
      } else {
        tom.setValue("");
        document.getElementById("calendar-tz-custom").value = cal.tz || "";
        document.getElementById("calendar-tz-custom").style.display = "block";
      }
      document.getElementById("calendar-description").value =
        cal.description || "";
    }
  } else {
    appState.currentEditCalId = null;
  }

  document.getElementById("calendar-modal").classList.add("active");
}

// ==================== CRONS LIST MODAL ====================
// modals.js (most recent version)
export function openCronsModal(calId) {
  console.log("[DEBUG] openCronsModal called – calId:", calId);
  const cal = appState.calendarsData.find((c) => c.id === Number(calId));
  if (!cal) {
    console.warn("[DEBUG] Calendar not found for calId:", calId);
    showToast("Calendar not found", "danger");
    return;
  }
  console.log(
    "[DEBUG] Found calendar:",
    cal.name,
    "with",
    cal.crons?.length || 0,
    "crons",
  );
  const modal = document.getElementById("crons-modal");
  if (!modal) {
    console.error("[DEBUG] #crons-modal not found");
    showToast("Crons modal not found", "danger");
    return;
  }
  modal.dataset.calId = calId;
  document.getElementById("crons-modal-title").textContent =
    `Crons for ${cal.name}`;
  const loading = document.getElementById("crons-loading");
  const content = document.getElementById("crons-content");
  const body = document.getElementById("crons-body");
  const noCronsMsg = document.getElementById("no-crons-message");
  loading.style.display = "block";
  content.style.display = "none";
  body.innerHTML = "";
  if (cal.crons.length > 0) {
    cal.crons.forEach((cron) => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${cron.id}</td>
        <td>${cron.name}</td>
        <td>${cron.english || "—"}</td>
        <td>${cron.begin ? new Date(cron.begin * 1000).toLocaleString() : "Immediate"}</td>
        <td>${cron.expire ? new Date(cron.expire * 1000).toLocaleString() : "Never"}</td>
        <td>${cron.description || "—"}</td>
        <td>${formatDate(cron.next_start)}</td>
        <td>
          <button class="btn btn-sm btn-danger delete-cron" data-cron-id="${cron.id}" data-cal-id="${cal.id}">
            <i class="fas fa-trash"></i>
          </button>
        </td>
      `;
      body.appendChild(tr);
    });
    noCronsMsg.style.display = "none";
  } else {
    noCronsMsg.style.display = "block";
  }
  loading.style.display = "none";
  content.style.display = "block";
  modal.classList.add("active");
}

// ==================== SINGLE CRON MODAL ====================
// Replace openCronModal
export function openCronModal(mode = "create", calId, cron = null) {
  const isEdit = mode === "edit" && cron;
  const titleEl = document.getElementById("cron-modal-title");
  titleEl.textContent = isEdit ? "Edit Cron" : "Add Cron";

  // Clear fields first
  document.getElementById("cron-expression").value = "";
  document.getElementById("cron-description").value = "";
  document.getElementById("cron-begin").value = "";
  document.getElementById("cron-expire").value = "";

  if (isEdit && cron) {
    document.getElementById("cron-expression").value = cron.name || "";
    document.getElementById("cron-description").value = cron.description || "";
    document.getElementById("cron-begin").value = cron.begin || "";
    document.getElementById("cron-expire").value = cron.expire || "";
  }

  const modal = document.getElementById("cron-modal");
  modal.dataset.calId = calId;
  modal.dataset.cronId = isEdit ? cron.id : "";
  modal.classList.add("active");
}

// ==================== SAVE FUNCTIONS ====================
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
    cal_id: calId || "", // empty = detach
  });
  showToast(calId ? "Calendar attached" : "Calendar detached", "success");
  document.getElementById("attach-calendar-modal").classList.remove("active");
}

function saveJob() {
  const isEdit = !!appState.currentEditItem;
  const newName = document.getElementById("job-name").value.trim();
  const payload = {
    command: isEdit ? "update_job_config" : "create_job",
    id: isEdit ? Number(appState.currentEditItem.id) : undefined,
    parent_id: !isEdit ? appState.currentParentId : undefined,
    name: !isEdit ? newName : undefined,
    newname: isEdit && newName ? newName : undefined,
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
    name: !isEdit ? newName : undefined,
    newname: isEdit && newName ? newName : undefined,
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

function saveCalendar() {
  const name = document.getElementById("calendar-name")?.value.trim();
  const tom = document.getElementById("calendar-tz")?.tomselect;
  let tz = tom?.getValue() || "";
  const customTz = document.getElementById("calendar-tz-custom")?.value.trim();

  if (tz === "" && customTz) {
    tz = customTz;
  }

  const description = document
    .getElementById("calendar-description")
    ?.value.trim();

  if (!name) return showToast("Name is required", "danger");
  if (!tz) return showToast("Timezone is required", "danger");

  const isEdit = !!appState.currentEditCalId;
  const payload = {
    command: isEdit ? "update_cal" : "create_cal",
    id: isEdit ? appState.currentEditCalId : undefined,
    newname: isEdit ? name : undefined,
    name: !isEdit ? name : undefined,
    tz,
    description: description || undefined,
  };

  sendWS(payload);
  showToast(isEdit ? "Calendar updated" : "Calendar created", "success");
  document.getElementById("calendar-modal").classList.remove("active");
  appState.currentEditCalId = null;
}

// ==================== SAVE CRON ====================
function saveCron() {
  const modal = document.getElementById("cron-modal");
  const calId = Number(modal.dataset.calId);
  const cronIdStr = modal.dataset.cronId;
  const isEdit = !!cronIdStr && cronIdStr !== "";
  const cronId = isEdit ? Number(cronIdStr) : null;

  const expression = document.getElementById("cron-expression")?.value.trim();
  const description = document.getElementById("cron-description")?.value.trim();
  const begin = document.getElementById("cron-begin")?.value.trim();
  const expire = document.getElementById("cron-expire")?.value.trim();

  if (!expression) {
    return showToast("Cron expression is required", "danger");
  }
  if (isNaN(calId) || calId <= 0) {
    return showToast("Invalid calendar ID", "danger");
  }

  const payload = {
    command: isEdit ? "update_cron" : "create_cron",
    cal_id: calId,
  };

  if (isEdit) {
    payload.id = cronId;
    // Only send newname if the expression actually changed or always (safe)
    payload.newname = expression;
  } else {
    payload.name = expression;
  }

  if (description) payload.description = description;
  if (begin) payload.begin = Number(begin);
  if (expire) payload.expire = Number(expire);

  sendWS(payload);
  showToast(isEdit ? "Cron updated" : "Cron added", "success");
  modal.classList.remove("active");

  // Full re-render calendars table to reflect changes immediately
  renderCalendarsTable();
}

// ==================== DOMContentLoaded - attach all listeners ====================
document.addEventListener("DOMContentLoaded", () => {
  // Save buttons
  document.getElementById("save-job")?.addEventListener("click", saveJob);
  document
    .getElementById("save-cluster")
    ?.addEventListener("click", saveCluster);
  document
    .getElementById("save-calendar")
    ?.addEventListener("click", saveCalendar);
  document.getElementById("save-cron")?.addEventListener("click", saveCron);

  // Cancel/close buttons
  document.addEventListener("click", (e) => {
    const btn = e.target.closest("[data-dismiss]");
    if (!btn) return;

    const modalId = btn.dataset.dismiss;
    const modal = document.getElementById(modalId);

    if (!modal) return;

    modal.classList.remove("active");

    // Special cleanup
    if (modal.id === "log-history-modal") {
      const logBody = modal.querySelector(".modal-body");
      if (logBody) logBody.innerHTML = "";
    }

    if (modal.id === "graph-modal" && window.cy) {
      window.cy.destroy();
      window.cy = null;
    }

    // General reset for all modals
    resetAllModals();
  });

  // Create calendar button
  document
    .getElementById("create-calendar-btn")
    ?.addEventListener("click", () => {
      openCalendarModal("create");
    });

  document
    .getElementById("save-attach-calendar")
    ?.addEventListener("click", saveAttachCalendar);

  document
    .getElementById("add-server-btn")
    ?.addEventListener("click", () => openServerModal("create"));

  document.getElementById("save-server")?.addEventListener("click", () => {
    const name = document.getElementById("server-name").value.trim();
    const host = document.getElementById("server-host").value.trim();
    const user = document.getElementById("server-user").value.trim();
    const port = Number(document.getElementById("server-port").value) || 22;
    const password =
      document.getElementById("server-password").value || undefined;

    if (!name || !host || !user) {
      showToast("Name, Host, and User required", "danger");
      return;
    }

    const payload = {
      host,
      user,
      port,
    };

    if (appState.currentEditServerId) {
      // EDIT: use "newname" for rename, include id
      payload.command = "update_monitor";
      payload.id = appState.currentEditServerId;
      payload.newname = name; // <-- key change here
    } else {
      // CREATE: use "name"
      payload.command = "create_monitor";
      payload.name = name;
      if (password) payload.password = password;
    }

    sendWS(payload);
    showToast(
      appState.currentEditServerId ? "Updating server..." : "Adding server...",
      "info",
    );
    document.getElementById("server-modal").classList.remove("active");
  });

  // Add Cron button in crons modal
  document.getElementById("add-cron-btn")?.addEventListener("click", () => {
    const modal = document.getElementById("crons-modal");
    const calId = modal?.dataset?.calId;

    if (!calId || isNaN(Number(calId))) {
      showToast("Cannot add cron – calendar ID missing", "danger");
      return;
    }

    console.log("[DEBUG] Add Cron clicked – calId:", calId);
    openCronModal("create", Number(calId));
  });

  // Event delegation for dynamic delete-cron buttons in crons modal
  document.addEventListener("click", (e) => {
    const deleteBtn = e.target.closest(".delete-cron");
    if (!deleteBtn) return;

    e.preventDefault();
    e.stopPropagation();

    const cronId = Number(deleteBtn.dataset.cronId);
    const calId = Number(deleteBtn.dataset.calId);

    if (isNaN(cronId) || isNaN(calId)) {
      showToast("Invalid cron or calendar ID", "danger");
      return;
    }

    openConfirmModal(
      "Confirm Delete Cron",
      "Are you sure you want to delete this cron expression? This cannot be undone.",
      () => {
        sendWS({ command: "delete_cron", id: cronId });
        showToast("Cron deleted", "success");

        // Re-open the crons modal to refresh the list
        document.getElementById("crons-modal")?.classList.remove("active");
        setTimeout(() => openCronsModal(calId), 300);
      },
      () => showToast("Delete cancelled", "info"),
    );
  });

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

  // Copy token
  /*
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
  */

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
});
