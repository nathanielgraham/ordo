document.addEventListener("DOMContentLoaded", function () {
  console.log("DOM ready - attaching listeners");
  let ws = null;
  let monitorData = { tree: [] };
  let accountData = null;
  let orgData = null;
  let calendarsData = [];
  let serversData = [];
  let currentEditItem = null;
  let currentParentId = null;
  let currentParentName = null;
  let currentAttachClusterId = null;

  const COLLAPSE_KEY = "ordo_collapsed_clusters";

  function getCollapsedIds() {
    try {
      const stored = localStorage.getItem(COLLAPSE_KEY);
      return stored ? new Set(JSON.parse(stored)) : new Set();
    } catch {
      return new Set();
    }
  }

  function saveCollapsedIds(set) {
    try {
      localStorage.setItem(COLLAPSE_KEY, JSON.stringify([...set]));
    } catch {}
  }

  function closeAllDropdowns() {
    document.querySelectorAll("#tree-body .dropdown.is-active").forEach((d) => {
      d.classList.remove("is-active", "is-up");
    });
  }

  function openDependencyGraph(clusterId, clusterName) {
    document.getElementById("graph-title").textContent = `${clusterName}`;
    document.getElementById("graph-modal").classList.add("is-active");

    const container = document.getElementById("graph-container");
    container.innerHTML =
      '<div class="has-text-centered p-6"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';

    const rootNode = findClusterById(monitorData.tree, clusterId);
    if (!rootNode) {
      container.innerHTML =
        '<p class="has-text-danger has-text-centered">Cluster not found</p>';
      return;
    }

    const elements = [];
    const added = new Set();

    const getCyId = (node) => (node.is_cluster ? `c${node.id}` : `j${node.id}`);
    const getLabel = (node) => (node.is_cluster ? `${node.name}/` : node.name);

    function traverse(node) {
      const cyId = getCyId(node);
      if (added.has(cyId)) return cyId;
      added.add(cyId);

      let parentCyId = null;
      if (node.parent_id) {
        parentCyId = `c${node.parent_id}`;
      } else if (node.cluster_id) {
        parentCyId = `c${node.cluster_id}`;
      }

      if (node.is_cluster) {
        elements.push({
          data: { id: cyId, label: getLabel(node), parent: parentCyId },
          classes: "cluster",
        });
      } else {
        elements.push({
          data: { id: cyId, label: getLabel(node), parent: parentCyId },
          classes: "job",
        });
      }

      // Children
      if (node.children) node.children.forEach(traverse);
      if (node.jobs)
        node.jobs.forEach((job) => traverse({ ...job, is_cluster: false }));

      // === Blocking needs ===
      if (node.needs_ids?.length) {
        node.needs_ids.forEach((depId) => {
          const lookupFn = node.is_cluster ? findClusterById : findJobById;
          const dep = lookupFn(monitorData.tree, depId);
          if (dep) {
            traverse(dep);
            const source = node.is_cluster ? getCyId(dep) : cyId; // reverse for clusters
            const target = node.is_cluster ? cyId : getCyId(dep);
            elements.push({
              data: { source, target, label: "needs" },
              classes: "needs",
            });
          }
        });
      }

      // === Needs_any (OR) ===
      if (node.needs_any_ids?.length) {
        node.needs_any_ids.forEach((depId) => {
          const lookupFn = node.is_cluster ? findClusterById : findJobById;
          const dep = lookupFn(monitorData.tree, depId);
          if (dep) {
            traverse(dep);
            const source = node.is_cluster ? getCyId(dep) : cyId; // reverse for clusters
            const target = node.is_cluster ? cyId : getCyId(dep);
            elements.push({
              data: { source, target, label: "needs any" },
              classes: "needs_any",
            });
          }
        });
      }

      // === on_fail (always cluster) ===
      if (node.on_fail_id) {
        const fail = findClusterById(monitorData.tree, node.on_fail_id);
        if (fail) {
          traverse(fail);
          elements.push({
            data: { source: cyId, target: getCyId(fail), label: "on fail" },
            classes: "on_fail",
          });
        }
      }

      return cyId;
    }

    traverse(rootNode);

    if (container.cy) container.cy.destroy();

    const cy = cytoscape({
      container: container,
      elements: elements,
      style: [
        {
          selector: "node",
          style: {
            label: "data(label)",
            "text-valign": "center",
            color: "#fff",
            "text-outline-width": 2,
            "text-outline-color": "#000",
            "font-size": 13,
          },
        },
        {
          selector: ".cluster",
          style: {
            "background-color": "#3273dc",
            "background-opacity": 0.2,
            "border-color": "#3273dc",
            "border-width": 3,
            shape: "roundrectangle",
            padding: 60,
            "text-valign": "top",
            "text-margin-y": -20,
            "font-weight": "bold",
            "font-size": 15,
          },
        },
        {
          selector: ".job",
          style: {
            "background-color": "#48c774",
            shape: "rectangle",
          },
        },
        {
          selector: ".needs",
          style: {
            width: 4,
            "line-color": "#000",
            "target-arrow-color": "#000",
            "target-arrow-shape": "triangle",
            "curve-style": "bezier",
            "font-size": 11,
            "text-background-color": "#fff",
            "text-background-opacity": 0.9,
            "text-background-padding": "4px",
          },
        },
        {
          selector: ".needs_any",
          style: {
            width: 2,
            "line-color": "#888",
            "target-arrow-color": "#888",
            "target-arrow-shape": "vee",
            "line-style": "dashed",
            "curve-style": "bezier",
            "font-size": 11,
            "text-background-color": "#fff",
            "text-background-opacity": 0.9,
            "text-background-padding": "4px",
          },
        },
        {
          selector: ".on_fail",
          style: {
            width: 2,
            "line-color": "#f14668",
            "target-arrow-color": "#f14668",
            "target-arrow-shape": "diamond",
            "line-style": "dashed",
            "curve-style": "bezier",
            label: "data(label)",
            "font-size": 11,
            "text-background-color": "#fff",
            "text-background-opacity": 0.9,
            "text-background-padding": "4px",
          },
        },
      ],
      layout: {
        name: "dagre",
        rankDir: "TB",
        nodeSep: 70,
        rankSep: 200,
        edgeSep: 30,
      },
      zoomingEnabled: true,
      panningEnabled: true,
      boxSelectionEnabled: false,
      autoungrabify: true,
    });

    // Remove spinner reliably
    const removeSpinner = () => {
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    };

    cy.on("layoutstop", () => {
      cy.fit(cy.elements(), 100);
      cy.center();
    });

    // Fit button
    document.getElementById("zoom-fit").onclick = () => {
      cy.fit(cy.elements(), 100);
      cy.center();
    };

    // Fallback: remove after max 3 seconds
    setTimeout(removeSpinner, 3000);

    // Also on ready (extra safety)
    cy.ready(removeSpinner);

    // Fit button
    document.getElementById("zoom-in").onclick = () => cy.zoom(cy.zoom() * 1.2);
    document.getElementById("zoom-out").onclick = () =>
      cy.zoom(cy.zoom() / 1.2);
    document.getElementById("zoom-fit").onclick = () =>
      cy.fit(cy.elements(), 100);
  }

  // Load Quickstart on first open
  const quickstartLink = document.querySelector(
    '#docs-toc a[data-file="quickstart.md"]',
  );
  if (quickstartLink) {
    quickstartLink.click(); // Triggers your existing TOC handler → loads Quickstart
  }

  // Logout clears collapsed state
  const logoutLink = document.querySelector('#private-end a[href="/logout"]');
  if (logoutLink) {
    logoutLink.addEventListener("click", () =>
      localStorage.removeItem(COLLAPSE_KEY),
    );
  }

  document.addEventListener("click", (e) => {
    // Close modal via X button or background
    const closeTrigger = e.target.closest(".modal .delete, .modal-background");
    if (closeTrigger) {
      const modal = closeTrigger.closest(".modal");
      if (modal) {
        modal.classList.remove("is-active");
        closeAllDropdowns();
      }
    }

    // Close dropdowns when clicking outside
    if (!e.target.closest(".dropdown")) {
      closeAllDropdowns();
    }
  });

  // Ensure dropdowns close whenever any modal is active
  document.addEventListener("click", () => {
    if (document.querySelector(".modal.is-active")) {
      closeAllDropdowns();
    }
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document.querySelectorAll(".modal.is-active").forEach((modal) => {
        modal.classList.remove("is-active");
      });
      closeAllDropdowns();
    }
  });

  // Mobile TOC toggle
  document.getElementById("docs-toc-toggle")?.addEventListener("click", () => {
    document.getElementById("docs-toc").classList.toggle("is-open");
  });

  // Tree table interaction
  document.getElementById("tree-body").addEventListener("click", (e) => {
    // Collapse/expand toggle
    const toggle = e.target.closest(".ordo-toggle");
    if (toggle) {
      const row = toggle.closest("tr");
      const clusterId = row.dataset.id;
      const isCollapsed = row.classList.toggle("collapsed");
      const currentCollapsed = getCollapsedIds();
      if (isCollapsed) currentCollapsed.add(clusterId);
      else currentCollapsed.delete(clusterId);
      saveCollapsedIds(currentCollapsed);
      toggleSubtree(clusterId, isCollapsed);
      row.setAttribute("aria-expanded", (!isCollapsed).toString());
      if (!isCollapsed) forceExpandDescendants(clusterId);
      return;
    }

    // === Trigger: open/close dropdown ===
    // === Trigger: open/close dropdown ===
    const trigger = e.target.closest(".dropdown-trigger button");
    if (trigger) {
      e.stopPropagation(); // prevent page click closing

      const dropdown = trigger.closest(".dropdown");
      const menu = dropdown.querySelector(".dropdown-menu");
      const willOpen = !dropdown.classList.contains("is-active");

      // Close all other dropdowns
      document.querySelectorAll(".dropdown.is-active").forEach((d) => {
        if (d !== dropdown) {
          d.classList.remove("is-active", "is-up");
        }
      });

      dropdown.classList.toggle("is-active", willOpen);

      if (willOpen) {
        menu.style.display = "block";
        menu.offsetHeight;

        const triggerRect = trigger.getBoundingClientRect();
        const menuRect = menu.getBoundingClientRect();
        const viewportHeight = window.innerHeight;

        const navbarHeight = 60;
        const margin = 40;

        const spaceBelow = viewportHeight - triggerRect.bottom;
        const spaceAbove = triggerRect.top - navbarHeight;

        const menuHeight = menuRect.height;

        // Flip up if more space above
        const useUp = spaceAbove > spaceBelow;

        dropdown.classList.toggle("is-up", useUp);

        // Max height to fit chosen direction
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

      if (text === "edit") {
        const node = isCluster
          ? findClusterById(monitorData.tree, id)
          : findJobById(monitorData.tree, id);
        if (node) openEntityModal("edit", isCluster ? "cluster" : "job", node);
        return;
      }

      if (text === "view graph") {
        const clusterId = Number(row.dataset.id);
        const clusterName = row
          .querySelector("td:first-child")
          .textContent.trim()
          .replace(/\/$/, "");
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
        const clusterId = Number(row.dataset.id);
        const clusterName = row
          .querySelector("td:first-child")
          .textContent.trim()
          .replace(/\/$/, "");
        const node = findClusterById(monitorData.tree, clusterId);
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
        document.getElementById("confirm-modal").classList.add("is-active");

        const yesBtn = document.getElementById("confirm-yes");
        const noBtn = document.getElementById("confirm-no");
        const closeBtn = document.getElementById("close-confirm");

        const handleConfirm = () => {
          sendCommand(text, id, type);
          document
            .getElementById("confirm-modal")
            .classList.remove("is-active");
          yesBtn.removeEventListener("click", handleConfirm);
        };

        yesBtn.addEventListener("click", handleConfirm);
        noBtn.addEventListener("click", () =>
          document
            .getElementById("confirm-modal")
            .classList.remove("is-active"),
        );
        closeBtn.addEventListener("click", () =>
          document
            .getElementById("confirm-modal")
            .classList.remove("is-active"),
        );
        return;
      }

      if (text === "view log" && !isCluster) {
        ws.send(JSON.stringify({ command: "read_log", id }));
        document.getElementById("log-modal").classList.add("is-active");
        document.querySelector("#log-modal .modal-card-title").textContent =
          "Latest Job Log";
        document.getElementById("log-modal").dataset.jobId = id;
        return;
      }

      sendCommand(text, id, type);
    }
  });

  // Save entity (create/edit job/cluster)
  document.getElementById("save-entity").addEventListener("click", () => {
    const name = document.getElementById("entity-name").value.trim();
    if (!name) {
      showToast("Name is required", "danger");
      return;
    }

    const isEdit = currentEditItem !== null;
    const isJob =
      document.getElementById("entity-script-field").style.display !== "none";

    const payload = {
      command: isEdit
        ? isJob
          ? "update_job"
          : "update_cluster"
        : isJob
          ? "create_job"
          : "create_cluster",
      name,
    };

    if (isEdit) payload.id = currentEditItem.id;
    else payload.parent_id = currentParentId;

    if (isJob) {
      const script = document.getElementById("entity-script").value.trim();
      const server = document.getElementById("entity-server").value;
      if (!script || !server) {
        showToast("Script and Server are required for jobs", "danger");
        return;
      }
      payload.script = script;
      payload.server = server;

      const retrys = document.getElementById("entity-retrys").value;
      if (retrys) payload.retrys = Number(retrys);
      const delay = document.getElementById("entity-delay").value;
      if (delay) payload.delay = Number(delay);
    }

    const description = document
      .getElementById("entity-description")
      .value.trim();
    if (description) payload.description = description;

    const loops = document.getElementById("entity-loops").value;
    if (loops) payload.loops = Number(loops);

    // Dependencies
    const needsSelect = document.getElementById("entity-needs");
    const needsIds = Array.from(needsSelect.selectedOptions)
      .map((opt) => Number(opt.value))
      .filter((id) => id > 0);
    if (
      needsIds.length > 0 ||
      needsSelect.querySelector('option[value=""]').selected
    ) {
      payload.needs_ids = needsIds.length > 0 ? needsIds : [];
    }

    const needsAnySelect = document.getElementById("entity-needs-any");
    const needsAnyIds = Array.from(needsAnySelect.selectedOptions)
      .map((opt) => Number(opt.value))
      .filter((id) => id > 0);
    if (
      needsAnyIds.length > 0 ||
      needsAnySelect.querySelector('option[value=""]').selected
    ) {
      payload.needs_any_ids = needsAnyIds.length > 0 ? needsAnyIds : [];
    }

    const onFailSelect = document.getElementById("entity-on-fail");
    const onFailId = onFailSelect.value;
    if (onFailId) {
      payload.on_fail_id = Number(onFailId);
    } else if (onFailSelect.querySelector('option[value=""]').selected) {
      payload.on_fail_id = null;
    }

    ws.send(JSON.stringify(payload));
    showToast(isEdit ? "Update sent" : "Creation requested", "info");
    document.getElementById("entity-modal").classList.remove("is-active");
  });

  // Save attach calendar
  document.getElementById("save-attach-cal").addEventListener("click", () => {
    const calId = document.getElementById("attach-cal-select").value;

    const payload = {
      command: "update_cluster",
      id: currentAttachClusterId,
      cal_id: calId ? Number(calId) : null,
    };

    ws.send(JSON.stringify(payload));
    showToast("Calendar updated", "info");
    document.getElementById("attach-cal-modal").classList.remove("is-active");
  });

  // Log modal specific buttons
  document.getElementById("close-log").addEventListener("click", () => {
    document.getElementById("log-modal").classList.remove("is-active");
  });

  document.getElementById("refresh-log").addEventListener("click", () => {
    const jobId = document.getElementById("log-modal").dataset.jobId;
    if (jobId) ws.send(JSON.stringify({ command: "read_log", id: jobId }));
  });

  document.getElementById("view-history").addEventListener("click", () => {
    const jobId = document.getElementById("log-modal").dataset.jobId;
    if (jobId) {
      ws.send(JSON.stringify({ command: "find_log", id: jobId }));
      document.getElementById("log-history-modal").classList.add("is-active");
    }
  });

  document.getElementById("close-log-history").addEventListener("click", () => {
    document.getElementById("log-history-modal").classList.remove("is-active");
  });

  // Global refresh - detects active tab
  document.getElementById("global-refresh")?.addEventListener("click", () => {
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      showToast("Not connected", "danger");
      return;
    }

    const activeTab =
      document.querySelector(".tabs li.is-active")?.dataset.target;

    switch (activeTab) {
      case "monitor":
        ws.send(JSON.stringify({ command: "find_cluster", name: "/root" }));
        break;
      case "calendars":
        ws.send(JSON.stringify({ command: "find_cal" }));
        break;
      case "servers":
        ws.send(JSON.stringify({ command: "find_monitor" }));
        break;
      case "account":
        ws.send(JSON.stringify({ command: "read_user" }));
        ws.send(JSON.stringify({ command: "read_org" }));
        break;
      default:
        showToast("No refresh action for this tab", "info");
    }
  });

  // Copy token
  document.getElementById("copy-token").addEventListener("click", () => {
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
  document.getElementById("save-profile").addEventListener("click", () => {
    const name = document.getElementById("edit-name").value.trim();
    const mode = document.getElementById("edit-mode").value.trim();
    if (!name && !mode) {
      showToast("No changes", "info");
      return;
    }
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(
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
  document.getElementById("save-org").addEventListener("click", () => {
    const payload = { command: "update_org" };
    const name = document.getElementById("edit-org-name").value.trim();
    const desc = document.getElementById("edit-org-desc").value.trim();
    if (name) payload.name = name;
    if (desc) payload.description = desc;
    if (Object.keys(payload).length === 1) {
      showToast("No changes", "info");
      return;
    }
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(payload));
      showToast("Organization update requested", "info");
    } else {
      showToast("Not connected", "danger");
    }
  });

  // Invite team member
  document.getElementById("invite-team").addEventListener("click", () => {
    document.getElementById("invite-modal").classList.add("is-active");
    document.getElementById("invite-email").value = "";
  });

  document.getElementById("cancel-invite").addEventListener("click", () => {
    document.getElementById("invite-modal").classList.remove("is-active");
  });

  document.getElementById("close-invite").addEventListener("click", () => {
    document.getElementById("invite-modal").classList.remove("is-active");
  });

  document.getElementById("send-invite").addEventListener("click", () => {
    const email = document.getElementById("invite-email").value.trim();
    if (!email) {
      showToast("Enter email", "danger");
      return;
    }
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(
        JSON.stringify({
          command: "register_user",
          email: email,
          team_member: "1",
        }),
      );
      showToast("Invitation sent", "success");
      document.getElementById("invite-modal").classList.remove("is-active");
    } else {
      showToast("Not connected", "danger");
    }
  });

  // Global handler for ALL Cancel buttons in modals
  document.addEventListener("click", (e) => {
    const cancelBtn = e.target.closest(
      '[id^="cancel-"], .button[data-action="cancel"]',
    );
    if (cancelBtn) {
      // Find the nearest modal and close it
      const modal = cancelBtn.closest(".modal");
      if (modal) {
        modal.classList.remove("is-active");
        closeAllDropdowns(); // optional: safety
      }
    }
  });

  // Live timer update (safe)
  setInterval(() => {
    document.getElementById("current-time").textContent =
      new Date().toLocaleString();
    document.querySelectorAll("#tree-body tr[data-id]").forEach((row) => {
      const id = row.dataset.id;
      const isClusterRow = row.classList.contains("ordo-cluster-row");
      const item = isClusterRow
        ? findClusterById(monitorData.tree, id)
        : findJobById(monitorData.tree, id);
      if (!item) return;

      const cells = row.cells;
      if (cells[5]) cells[5].textContent = formatTplus(item.started) || "—";
      if (cells[6])
        cells[6].textContent = formatDuration(item.started, item.ended) || "—";
      if (cells[7]) cells[7].textContent = formatTminus(item.next_start) || "—";
    });
  }, 1000);

  function getStateColor(state) {
    if (!state) return "#97C2FC";
    const lower = state.toLowerCase();
    if (["complete", "success"].includes(lower)) return "#4CAF50";
    if (lower === "running") return "#2196F3";
    if (["failed", "killed", "zombie"].includes(lower)) return "#F44336";
    if (["hold", "ice"].includes(lower)) return "#FF9800";
    if (lower === "immutable") return "#9C27B0";
    return "#9E9E9E";
  }

  function getFullPath(node, tree = monitorData.tree) {
    if (!node.parent_id) return node.name + (node.is_cluster ? "/" : "");
    const parent = findClusterById(tree, node.parent_id);
    if (!parent) return node.name + (node.is_cluster ? "/" : "");
    return getFullPath(parent, tree) + node.name + (node.is_cluster ? "/" : "");
  }

  function populateDependencySelects(
    selectId,
    selectedIds = [],
    includeNone = true,
  ) {
    const select = document.getElementById(selectId);
    select.innerHTML = "";

    if (includeNone) {
      const noneOpt = document.createElement("option");
      noneOpt.value = "";
      noneOpt.textContent = "None";
      select.appendChild(noneOpt);
    }

    function addClusters(items) {
      items.forEach((item) => {
        if (item.is_cluster) {
          if (currentEditItem && Number(item.id) === Number(currentEditItem.id))
            return;
          const opt = document.createElement("option");
          opt.value = item.id;
          opt.textContent = getFullPath(item);
          if (selectedIds.includes(Number(item.id))) opt.selected = true;
          select.appendChild(opt);

          if (item.children) addClusters(item.children);
        }
      });
    }

    addClusters(monitorData.tree);
  }

  function openEntityModal(
    mode = "create",
    type = "job",
    item = null,
    parentId = null,
    parentName = null,
  ) {
    currentEditItem = item;
    currentParentId = parentId;
    currentParentName = parentName;

    const isEdit = mode === "edit";
    const isJob = type === "job";

    document.getElementById("entity-modal-title").textContent = isEdit
      ? `Edit ${isJob ? "Job" : "Cluster"}`
      : `New ${isJob ? "Job" : "Cluster"}`;

    const contextEl = document.getElementById("entity-context");
    if (isEdit) contextEl.textContent = `ID: ${item.id}`;
    else if (parentName) contextEl.textContent = `In cluster: ${parentName}`;
    else contextEl.textContent = "In root";

    document.getElementById("entity-script-field").style.display = isJob
      ? "block"
      : "none";
    document.getElementById("entity-server-field").style.display = isJob
      ? "block"
      : "none";
    document.getElementById("entity-retrys-field").style.display = isJob
      ? "block"
      : "none";
    document.getElementById("entity-delay-field").style.display = isJob
      ? "block"
      : "none";

    if (isEdit && item) {
      document.getElementById("entity-name").value = item.name || "";
      document.getElementById("entity-description").value =
        item.description || "";
      document.getElementById("entity-script").value = item.script || "";
      document.getElementById("entity-server").value = item.server_name || "";
      document.getElementById("entity-loops").value = item.loops ?? 0;
      document.getElementById("entity-retrys").value = item.retrys ?? 0;
      document.getElementById("entity-delay").value = item.delay ?? 0;

      populateDependencySelects("entity-needs", item.needs_ids || [], true);
      populateDependencySelects(
        "entity-needs-any",
        item.needs_any_ids || [],
        true,
      );
      populateDependencySelects(
        "entity-on-fail",
        item.on_fail_id ? [item.on_fail_id] : [],
        true,
      );
    } else {
      document.getElementById("entity-name").value = isJob
        ? "new-job"
        : "new-cluster";
      document.getElementById("entity-description").value = "";
      document.getElementById("entity-script").value = "";
      document.getElementById("entity-loops").value = "0";
      document.getElementById("entity-retrys").value = "0";
      document.getElementById("entity-delay").value = "0";

      populateDependencySelects("entity-needs", [], true);
      populateDependencySelects("entity-needs-any", [], true);
      populateDependencySelects("entity-on-fail", [], true);
    }

    const serverSelect = document.getElementById("entity-server");
    serverSelect.innerHTML = "";
    serversData.forEach((s) => {
      const opt = document.createElement("option");
      opt.value = s.name;
      opt.textContent = s.name;
      if (!isEdit && serversData[0]) opt.selected = true;
      if (isEdit && s.name === item.server_name) opt.selected = true;
      serverSelect.appendChild(opt);
    });

    document.getElementById("entity-modal").classList.add("is-active");
  }

  function openAttachCalendarModal(
    clusterId,
    clusterName,
    currentCalName = "",
    currentCalId = null,
  ) {
    currentAttachClusterId = clusterId;
    document.getElementById("attach-target-name").textContent = clusterName;
    document.getElementById("attach-current-cal").textContent =
      currentCalName || "None";

    const select = document.getElementById("attach-cal-select");
    select.innerHTML = '<option value="">None (run manually only)</option>';
    calendarsData.forEach((cal) => {
      const opt = document.createElement("option");
      opt.value = cal.id;
      opt.textContent = cal.name;
      if (Number(cal.id) === Number(currentCalId)) opt.selected = true;
      select.appendChild(opt);
    });

    document.getElementById("attach-cal-modal").classList.add("is-active");
  }

  function sendCommand(action, id, type) {
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
    ws.send(JSON.stringify({ command, id }));
  }

/*

function checkLoginAndConnect() {
  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];

  if (token) {
    document.body.classList.add('is-logged-in');
    connectWS(token);

    // Optional: activate default private tab
    const defaultTab = document.querySelector('#private-tabs .is-active');
    if (defaultTab) defaultTab.click();
  } else {
    document.body.classList.remove('is-logged-in');

    // Optional: activate default public tab
    const defaultTab = document.querySelector('#public-tabs .is-active');
    if (defaultTab) defaultTab.click();
  }
}

*/

function checkLoginAndConnect() {
  const token = document.cookie.match(/ordo_token=([^;]+)/)?.[1];
  
  if (token) {
    document.body.classList.add('is-logged-in');
    console.log("DEBUG: Logged IN → added 'is-logged-in' class");
    connectWS(token);
  } else {
    document.body.classList.remove('is-logged-in');
    console.log("DEBUG: Logged OUT → removed 'is-logged-in' class");
  }

  // No more debug logging of display styles — they're not reliable
  // Instead, let initTabSwitching() handle default activation
}

  function connectWS(token) {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/websocket`);
    ws.addEventListener("open", () => {
      console.log("WS connected");
      ws.send(JSON.stringify({ command: "login_user", token }));
    });
    ws.onmessage = (e) => {
      console.log("WS message:", e.data);
      try {
        const data = JSON.parse(e.data);
        if (data.command_reply === "login_user" && data.success) {
          console.log("Login success - requesting initial loads");
          ws.send(JSON.stringify({ command: "read_user" }));
          ws.send(JSON.stringify({ command: "read_org" }));
          ws.send(JSON.stringify({ command: "find_cluster", name: "/root" }));
          ws.send(JSON.stringify({ command: "find_cal" }));
          ws.send(JSON.stringify({ command: "find_monitor" }));
        }
        if (data.command_reply === "read_user") updateAccount(data);
        if (data.command_reply === "read_org") updateOrgAndTeam(data);
        if (data.command_reply === "read_log") updateLog(data);
        if (data.command_reply === "find_log") updateLogHistory(data);
        if (data.command_reply === "find_cluster") updateJobsClusters(data);
        if (data.command_reply === "find_cal") updateCalendars(data);
        if (data.command_reply === "find_monitor") updateServers(data);
        if (data.broadcast === "clusters_changed") applyClusterBroadcast(data);
        if (data.broadcast === "jobs_changed") applyJobBroadcast(data);
        if (data.broadcast === "cals_changed") applyCalBroadcast(data);
        if (data.broadcast === "servers_changed") applyServerBroadcast(data);
        if (data.broadcast === "org_changed") updateOrgAndTeam(data);
        if (data.command_reply && data.message) {
          showToast(data.message, data.success ? "success" : "danger");
        }
      } catch (err) {
        console.error("Parse error:", err);
      }
    };
    ws.onclose = () => {
      console.log("WS closed");
      setTimeout(checkLoginAndConnect, 5000);
    };
  }

  function showLoading(containerId) {
    const loading = document.getElementById(containerId);
    if (loading) loading.style.display = "block";
  }
  function hideLoading(containerId) {
    const loading = document.getElementById(containerId);
    if (loading) loading.style.display = "none";
  }

  function showToast(message, type = "info") {
    const toast = document.createElement("div");
    toast.className = `notification is-${type}`;
    toast.innerHTML = `<button class="delete"></button><span>${message}</span>`;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 4000);
  }

  function formatDate(epoch) {
    if (!epoch) return "—";
    return new Date(epoch * 1000).toLocaleString();
  }

  function formatTplus(epoch) {
    if (!epoch || isNaN(epoch)) return "—";
    const diff = Math.floor(Date.now() / 1000) - epoch;
    if (diff <= 0) return "T+0";
    const h = Math.floor(diff / 3600)
      .toString()
      .padStart(2, "0");
    const m = Math.floor((diff % 3600) / 60)
      .toString()
      .padStart(2, "0");
    const s = (diff % 60).toString().padStart(2, "0");
    return `T+${h}:${m}:${s}`;
  }

  function formatTminus(epoch) {
    if (!epoch || isNaN(epoch)) return "—";
    const diff = epoch - Math.floor(Date.now() / 1000);
    if (diff <= 0) return "Overdue";
    const h = Math.floor(diff / 3600)
      .toString()
      .padStart(2, "0");
    const m = Math.floor((diff % 3600) / 60)
      .toString()
      .padStart(2, "0");
    const s = (diff % 60).toString().padStart(2, "0");
    return `T-${h}:${m}:${s}`;
  }

  function formatDuration(start, end) {
    if (!start) return "—";
    const endTime = end || Math.floor(Date.now() / 1000);
    const diff = endTime - start;
    if (diff <= 0) return "—";
    const h = Math.floor(diff / 3600)
      .toString()
      .padStart(2, "0");
    const m = Math.floor((diff % 3600) / 60)
      .toString()
      .padStart(2, "0");
    const s = (diff % 60).toString().padStart(2, "0");
    return `${h}:${m}:${s}`;
  }

  function stateClass(state) {
    if (!state) return "ordo-default";
    const lowerState = state.toLowerCase();
    if (["complete"].includes(lowerState)) return "ordo-complete";
    if (["immutable", "ice", "pruned"].includes(lowerState))
      return "ordo-immutable";
    if (lowerState === "running") return "ordo-running";
    if (["failed", "hold", "zombie", "killed"].includes(lowerState))
      return "ordo-failed";
    if (["ready", "waiting", "looping", "retrying"].includes(lowerState))
      return "ordo-ready";
    return "ordo-default";
  }

  function updateAccount(data) {
    accountData = data;
    hideLoading("account-loading");
    document.getElementById("account-content").style.display = "block";
    renderUserProfile();
  }

  function renderUserProfile() {
    if (!accountData || !accountData.success) return;
    document.getElementById("account-email").textContent =
      accountData.email || "—";
    document.getElementById("account-id").textContent = accountData.id || "—";
    document.getElementById("account-level").textContent =
      accountData.level || "—";
    document.getElementById("edit-name").value = accountData.name || "";
    document.getElementById("edit-mode").value = accountData.mode || "";
    document.getElementById("account-creation").textContent =
      formatDate(accountData.creation_time) || "—";
    document.getElementById("account-update").textContent =
      formatDate(accountData.update_time) || "—";
    document.getElementById("account-remote").textContent =
      accountData.remote_address || "—";
    document.getElementById("account-token").value = accountData.token || "—";
  }

  function updateOrgAndTeam(data) {
    orgData = data;
    renderOrgTeam();
    hideLoading("account-loading");
    document.getElementById("account-content").style.display = "block";
  }

  function renderOrgTeam() {
    if (!orgData) return;
    document.getElementById("org-id").textContent = orgData.id || "—";
    document.getElementById("edit-org-name").value = orgData.name || "";
    document.getElementById("edit-org-desc").value = orgData.description || "";
    document.getElementById("org-creation").textContent =
      formatDate(orgData.creation_time) || "—";

    const teamBody = document.getElementById("team-body");
    teamBody.innerHTML = "";
    if (orgData.members?.length) {
      orgData.members.forEach((member) => {
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

  function updateLog(data) {
    document.getElementById("log-content").textContent = data.out;
  }

  function updateLogHistory(data) {
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
        ws.send(
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

  function updateJobsClusters(data) {
    hideLoading("monitor-loading");
    document.getElementById("monitor-content").style.display = "block";
    if (data.success) {
      monitorData.tree = buildTree(data);
      renderJobsTable();
    }
  }

  function buildTree(data) {
    const nodes = new Map();
    const root = { id: "root", children: [], depth: 0 };
    data.clusters.forEach((c) => {
      const node = {
        ...c,
        id: Number(c.id),
        type: "cluster",
        is_cluster: true,
        children:
          c.jobs?.map((j) => ({
            ...j,
            id: Number(j.id),
            type: "job",
            is_cluster: false,
            depth: 0,
          })) || [],
        depth: 0,
      };
      nodes.set(node.id, node);
    });
    data.clusters.forEach((c) => {
      const node = nodes.get(Number(c.id));
      if (c.parent_id == null) {
        root.children.push(node);
        node.depth = 0;
      } else {
        const parent = nodes.get(Number(c.parent_id));
        if (parent) {
          parent.children.push(node);
          node.depth = parent.depth + 1;
        } else {
          root.children.push(node);
          node.depth = 0;
        }
      }
      node.children.forEach((job) => (job.depth = node.depth + 1));
    });
    return root.children;
  }

  function updateCalendars(data) {
    hideLoading("calendars-loading");
    document.getElementById("calendars-content").style.display = "block";
    if (data.success) {
      calendarsData = data.cals || [];
      renderCalendarsTable();
    }
  }

  function renderCalendarsTable() {
    const tbody = document.getElementById("calendars-body");
    tbody.innerHTML = "";
    calendarsData.forEach((cal) => {
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

  function updateServers(data) {
    hideLoading("servers-loading");
    document.getElementById("servers-content").style.display = "block";
    if (data.success) {
      serversData = data.servers || [];
      renderServersTable();
    }
  }

  function renderServersTable() {
    const tbody = document.getElementById("servers-body");
    tbody.innerHTML = "";
    serversData.forEach((server) => {
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

  function renderJobsTable() {
    const tbody = document.getElementById("tree-body");
    tbody.innerHTML = "";
    buildRows(monitorData.tree, tbody);

    document.querySelectorAll(".ordo-cluster-row.collapsed").forEach((row) => {
      toggleSubtree(row.dataset.id, true);
    });
  }

  function buildRows(items, tbody, depth = 0, parentId = null) {
    const collapsedSet = getCollapsedIds();

    items.forEach((item) => {
      const isCluster = item.is_cluster;
      const hasChildren = isCluster && item.children?.length > 0;
      const state = item.jobstate?.toLowerCase() || "";
      const isRoot = item.name === "root" && item.parent_id == null;

      // Context-sensitive enabling
      const runDisabled = ["running", "immutable", "ice", "hold"].includes(
        state,
      )
        ? "disabled"
        : "";
      const killDisabled = state === "running" ? "" : "disabled";
      const holdDisabled = ["hold", "immutable", "ice"].includes(state)
        ? "disabled"
        : "";
      const releaseDisabled = state === "hold" ? "" : "disabled";
      const iceDisabled = ["ice", "immutable"].includes(state)
        ? "disabled"
        : "";
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

      // === DEPS BADGE + TOOLTIP ===
      let depsCount = 0;
      let depsTooltipLines = [];

      function resolveDepName(id) {
        id = Number(id);
        let node;
        if (isCluster) {
          // Cluster deps are always clusters
          node = findClusterById(monitorData.tree, id);
        } else {
          // Job deps are always jobs
          node = findJobById(monitorData.tree, id);
        }
        return node ? getFullPath(node) : `ID:${id} (missing)`;
      }

      // Needs (blocking)
      if (item.needs_ids?.length) {
        depsCount += item.needs_ids.length;
        const lines = item.needs_ids.map((id) => `• ${resolveDepName(id)}`);
        depsTooltipLines.push(`Needs (blocking):\n${lines.join("\n")}`);
      }

      // Needs Any (flexible)
      if (item.needs_any_ids?.length) {
        depsCount += item.needs_any_ids.length;
        const lines = item.needs_any_ids.map((id) => `• ${resolveDepName(id)}`);
        depsTooltipLines.push(`Needs Any (flexible):\n${lines.join("\n")}`);
      }

      // On Fail — always cluster
      if (item.on_fail_id) {
        depsCount += 1;
        const node = findClusterById(monitorData.tree, item.on_fail_id);
        const path = node
          ? getFullPath(node)
          : `ID:${item.on_fail_id} (missing)`;
        depsTooltipLines.push(`On Fail:\n• ${path}`);
      }

      const depsDisplay = depsCount > 0 ? depsCount : "—";
      const depsTitle = depsTooltipLines.length
        ? depsTooltipLines.join("\n\n")
        : "";

      // === STATS BADGE + TOOLTIP ===
      // === STATS BADGE + TOOLTIP (Safe & Improved) ===
      let statsDisplay = "—";
      let statsTooltipLines = [];

      if (item.pid || item.pctcpu != null || item.pctmem != null) {
        const cpu = item.pctcpu ?? 0;

        let cpuClass = "is-cpu-low";
        if (cpu > 80) cpuClass = "is-cpu-high";
        else if (cpu > 50) cpuClass = "is-cpu-medium";

        statsDisplay = `<span class="tag ${cpuClass}">${cpu.toFixed(1)}%</span>`;

        statsTooltipLines.push(`Process (PID ${item.pid || "—"}):`);
        statsTooltipLines.push(`• CPU: ${cpu.toFixed(1)}%`);
        if (item.pctmem != null)
          statsTooltipLines.push(`• Memory: ${item.pctmem.toFixed(1)}%`);
        if (item.rss != null) {
          const rssMB = Math.round(item.rss / 1024 / 1024);
          statsTooltipLines.push(`• RSS: ${rssMB} MB`);
        }
        if (item.ppid) statsTooltipLines.push(`• Parent PID: ${item.ppid}`);
        if (item.fname) statsTooltipLines.push(`• Command: ${item.fname}`);
      } else if (item.jobstate === "running") {
        statsTooltipLines.push("Stats collection not enabled.");
        statsTooltipLines.push(
          "Run update_stats.pl periodically to see real-time stats.",
        );
      }

      const statsTitle = statsTooltipLines.length
        ? statsTooltipLines.join("\n")
        : "";

      // Only add title if there's content and tag exists
      if (statsTitle && statsDisplay.includes("tag")) {
        const tempDiv = document.createElement("div");
        tempDiv.innerHTML = statsDisplay;
        const tag = tempDiv.querySelector(".tag");
        if (tag) tag.setAttribute("title", statsTitle);
        statsDisplay = tempDiv.innerHTML;
      }

      // === ACTIONS ===
      let actionsHtml = "";

      if (isRoot) {
        actionsHtml = `
        <div class="dropdown">
          <div class="dropdown-trigger">
            <button class="button is-small is-light">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item">New Cluster</a>
            </div>
          </div>
        </div>
      `;
      } else if (isCluster) {
        actionsHtml = `
        <div class="dropdown">
          <div class="dropdown-trigger">
            <button class="button is-small is-light">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item">Edit</a>
<a href="#" class="dropdown-item">View Graph</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${newClusterDisabled}">New Cluster</a>
              <a href="#" class="dropdown-item ${newJobDisabled}">New Job</a>
              <a href="#" class="dropdown-item">Attach Calendar</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${runDisabled}">Run</a>
              <a href="#" class="dropdown-item ${killDisabled}">Kill</a>
              <a href="#" class="dropdown-item ${holdDisabled}">Hold</a>
              <a href="#" class="dropdown-item ${releaseDisabled}">Release</a>
              <a href="#" class="dropdown-item ${iceDisabled}">Ice</a>
              <a href="#" class="dropdown-item ${meltDisabled}">Melt</a>
              <a href="#" class="dropdown-item ${completeDisabled}">Complete</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${resetDisabled}">Reset</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item is-danger">Delete</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${viewLogDisabled}">View Log</a>
            </div>
          </div>
        </div>
      `;
      } else {
        actionsHtml = `
        <div class="dropdown">
          <div class="dropdown-trigger">
            <button class="button is-small is-light">
              <i class="fas fa-ellipsis-v"></i>
            </button>
          </div>
          <div class="dropdown-menu" role="menu">
            <div class="dropdown-content">
              <a href="#" class="dropdown-item">Edit</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${runDisabled}">Run</a>
              <a href="#" class="dropdown-item ${killDisabled}">Kill</a>
              <a href="#" class="dropdown-item ${holdDisabled}">Hold</a>
              <a href="#" class="dropdown-item ${releaseDisabled}">Release</a>
              <a href="#" class="dropdown-item ${iceDisabled}">Ice</a>
              <a href="#" class="dropdown-item ${meltDisabled}">Melt</a>
              <a href="#" class="dropdown-item ${completeDisabled}">Complete</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item is-danger">Delete</a>
              <hr class="dropdown-divider">
              <a href="#" class="dropdown-item ${viewLogDisabled}">View Log</a>
            </div>
          </div>
        </div>
      `;
      }

      row.innerHTML = `
      <td>${nameHtml}</td>
      <td><span class="ordo-state ${stateClass(item.jobstate)}">${item.jobstate || "—"}</span></td>
      <td>${item.server_name || "—"}</td>
      <td title="${depsTitle}">${depsDisplay}</td>
      <td title="${statsTitle}">${statsDisplay}</td>
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
  }

  function toggleSubtree(parentId, hide) {
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

  function forceExpandDescendants(startId) {
    const children = document.querySelectorAll(`tr[data-parent="${startId}"]`);
    children.forEach((childRow) => {
      if (childRow.classList.contains("ordo-cluster-row")) {
        childRow.classList.remove("collapsed");
        forceExpandDescendants(childRow.dataset.id);
      }
    });
  }

  function findClusterById(items, id) {
    id = Number(id);
    for (let item of items) {
      if (item.id === id && item.is_cluster) return item;
      if (item.children) {
        const found = findClusterById(item.children, id);
        if (found) return found;
      }
    }
    return null;
  }

  function findJobById(items, id) {
    id = Number(id);
    for (let item of items) {
      if (item.id === id && !item.is_cluster) return item;
      if (item.children) {
        const found = findJobById(item.children, id);
        if (found) return found;
      }
    }
    return null;
  }

  function removeClusterById(items, id) {
    id = Number(id);
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === id && items[i].is_cluster) {
        items.splice(i, 1);
        return true;
      }
      if (items[i].children) {
        if (removeClusterById(items[i].children, id)) return true;
      }
    }
    return false;
  }

  function removeJobById(items, id) {
    id = Number(id);
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === id && !items[i].is_cluster) {
        items.splice(i, 1);
        return true;
      }
      if (items[i].children) {
        if (removeJobById(items[i].children, id)) return true;
      }
    }
    return false;
  }

  function applyClusterBroadcast(data) {
    if (data.updates) {
      data.updates.forEach((update) => {
        let node = findClusterById(monitorData.tree, update.id);
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
            const parent = findClusterById(monitorData.tree, update.parent_id);
            if (parent) parent.children.push(newNode);
            else monitorData.tree.push(newNode);
          } else {
            monitorData.tree.push(newNode);
          }
        }
      });
    }
    if (data.deletes) {
      const uniqueDeletes = [
        ...new Set(data.deletes.map((d) => Number(d.id || d))),
      ];
      uniqueDeletes.forEach((id) => removeClusterById(monitorData.tree, id));
    }
    renderJobsTable();
  }

  function applyJobBroadcast(data) {
    if (data.updates) {
      data.updates.forEach((update) => {
        let node = findJobById(monitorData.tree, update.id);
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
            const parent = findClusterById(monitorData.tree, update.cluster_id);
            if (parent) parent.children.push(newNode);
            else monitorData.tree.push(newNode);
          } else {
            monitorData.tree.push(newNode);
          }
        }
      });
    }
    if (data.deletes) {
      const uniqueDeletes = [
        ...new Set(data.deletes.map((d) => Number(d.id || d))),
      ];
      uniqueDeletes.forEach((id) => removeJobById(monitorData.tree, id));
    }
    renderJobsTable();
  }

  function applyCalBroadcast(data) {
    if (data.updates) {
      data.updates.forEach((update) => {
        const id = Number(update.id);
        const index = calendarsData.findIndex((cal) => Number(cal.id) === id);
        if (index !== -1) {
          calendarsData[index] = { ...calendarsData[index], ...update };
        } else {
          calendarsData.push({ ...update, id });
        }
      });
    }
    if (data.deletes) {
      const uniqueDeletes = [
        ...new Set(data.deletes.map((d) => Number(d.id || d))),
      ];
      uniqueDeletes.forEach((id) => {
        const index = calendarsData.findIndex((cal) => Number(cal.id) === id);
        if (index !== -1) calendarsData.splice(index, 1);
      });
    }
    renderCalendarsTable();
  }

  function applyServerBroadcast(data) {
    if (data.updates) {
      data.updates.forEach((update) => {
        const id = Number(update.id);
        const index = serversData.findIndex((s) => Number(s.id) === id);
        if (index !== -1) {
          serversData[index] = { ...serversData[index], ...update };
        } else {
          serversData.push({ ...update, id });
        }
      });
    }
    if (data.deletes) {
      const uniqueDeletes = [
        ...new Set(data.deletes.map((d) => Number(d.id || d))),
      ];
      uniqueDeletes.forEach((id) => {
        const index = serversData.findIndex((s) => Number(s.id) === id);
        if (index !== -1) serversData.splice(index, 1);
      });
    }
    renderServersTable();
  }

  function loadDoc(file) {
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

  // new custom js

function initTabSwitching() {
  const allTabLinks = document.querySelectorAll('.nav-link[data-tab]');
  
  console.log(`Found ${allTabLinks.length} tab links`);

  allTabLinks.forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      
      const tabId = link.dataset.tab;
      console.log(`Tab clicked: ${tabId}`);
      
      // Deactivate all tabs
      allTabLinks.forEach(l => l.classList.remove('is-active'));
      link.classList.add('is-active');
      
      // Hide all content
      document.querySelectorAll('.tab-content').forEach(section => {
        section.classList.remove('active');
        console.log(`Hid section: #${section.id}`);
      });
      
      // Show target
      const target = document.getElementById(tabId);
      if (target) {
        target.classList.add('active');
        console.log(`Activated section: #${tabId}`);
      } else {
        console.error(`Section not found: #${tabId}`);
      }
    });
  });

  // Auto-activate default
  function activateDefault() {
    const isLoggedIn = document.body.classList.contains('is-logged-in');
    const defaultTab = isLoggedIn 
      ? 'monitor' 
      : 'about';
    
    const defaultLink = document.querySelector(`[data-tab="${defaultTab}"]`);
    if (defaultLink) {
      console.log(`Auto-activating default tab: ${defaultTab}`);
      defaultLink.click();
    } else {
      console.warn(`Default tab link not found for: ${defaultTab}`);
    }
  }

  activateDefault();
}

// Final init
checkLoginAndConnect();
initTabSwitching();

});
