// graph.js – dependency graph visualization (Cytoscape + Dagre)
import { appState } from "./state.js";
import { findClusterById, findJobById } from "./utils.js";
import { openJobModal, openClusterModal } from "./modals.js";

let currentCy = null;

export function openDependencyGraph(clusterId, clusterName) {
  const modal = document.getElementById("graph-modal");
  const titleEl = document.getElementById("graph-title");
  const container = document.getElementById("graph-container");

  if (!modal || !container) return;

  titleEl.textContent = clusterName || `Cluster #${clusterId}`;
  modal.classList.add("active");

  if (currentCy) {
    currentCy.destroy();
    currentCy = null;
  }

  container.innerHTML = '<div class="has-text-centered p-6"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';
  // container.style.height = "calc(100vh - 180px)";
  // container.style.minHeight = "600px";
  container.style.height = "100%";   // Let CSS handle it
  container.style.minHeight = "30rem";


  setTimeout(() => {
    const rootNode = findClusterById(appState.monitorData.tree, clusterId);
    if (!rootNode) {
      container.innerHTML = '<p class="has-text-danger has-text-centered">Cluster not found</p>';
      return;
    }

    const elements = buildGraphElements(rootNode);

    currentCy = cytoscape({
      container: container,
      elements: elements,
      style: getGraphStyle(),
      layout: {
        name: "dagre",
        rankDir: "LR",
        spacingFactor: 1.4,
        nodeSep: 60,
        edgeSep: 30,
        rankSep: 120
      },
      zoomingEnabled: true,
      panningEnabled: true,
      boxSelectionEnabled: false,
      minZoom: 0.2,
      maxZoom: 5,
    });

    // Click to edit - More robust lookup
    // Click to edit - FIXED ID EXTRACTION
    currentCy.on('tap', 'node', (evt) => {
      const node = evt.target;
      let rawId = node.data('id');                    // e.g. "j123" or "c456"

      // Extract numeric ID
      const idStr = String(rawId).replace(/^[jc]/, '');   // remove 'j' or 'c' prefix
      const id = Number(idStr);

      const isCluster = node.data('is_cluster') === true || rawId.toString().startsWith('c');

      console.log(`[Graph Click] rawId=${rawId}, extracted id=${id}, isCluster=${isCluster}`);

      modal.classList.remove("active");

      if (isCluster) {
        openClusterModal("edit", id);
      } else {
        openJobModal("edit", id);
      }
    });

    currentCy.on('mouseover', 'node', (evt) => evt.target.addClass('highlight'));
    currentCy.on('mouseout', 'node', (evt) => evt.target.removeClass('highlight'));

    // Zoom controls (unchanged)
    document.getElementById("graph-fit-btn").onclick = () => currentCy.fit();
    document.getElementById("graph-zoom-in").onclick = () => currentCy.zoom(currentCy.zoom() * 1.2);
    document.getElementById("graph-zoom-out").onclick = () => currentCy.zoom(currentCy.zoom() * 0.8);
    document.getElementById("graph-reset").onclick = () => { currentCy.fit(); currentCy.center(); };

    // Better spinner cleanup
    const removeSpinner = () => {
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    };

    currentCy.on("layoutstop", removeSpinner);
    currentCy.ready(removeSpinner);


  }, 180);
}

// ==================== BUILD WITH COMPOUND NODES ====================
function buildGraphElements(rootNode) {
  const elements = [];
  const added = new Set();

  function traverse(node, parentCyId = null) {
    if (!node) return;
    const cyId = node.is_cluster ? `c${node.id}` : `j${node.id}`;
    if (added.has(cyId)) return;
    added.add(cyId);

    elements.push({
      data: { 
        id: cyId, 
        label: node.is_cluster ? `${node.name}/` : node.name,
        is_cluster: !!node.is_cluster,
        parent: parentCyId
      },
      classes: node.is_cluster ? "cluster" : "job"
    });

    // Recurse children
    if (node.children) node.children.forEach(child => traverse(child, cyId));
    if (node.jobs) node.jobs.forEach(job => traverse({ ...job, is_cluster: false }, cyId));

    // Edges (needs, needs_any, on_fail)
    if (node.needs_ids?.length) {
      node.needs_ids.forEach(depId => addEdge(cyId, depId, "needs"));
    }
    if (node.needs_any_ids?.length) {
      node.needs_any_ids.forEach(depId => addEdge(cyId, depId, "needs_any"));
    }
    if (node.on_fail_id) {
      addEdge(cyId, node.on_fail_id, "on_fail");
    }
  }

  function addEdge(sourceId, targetIdRaw, type) {
    const targetId = Number(targetIdRaw);
    let targetNode = null;
    if (type === "on_fail") {
      targetNode = findClusterById(appState.monitorData.tree, targetId);
    } else {
      targetNode = findJobById(appState.monitorData.tree, targetId) || 
                   findClusterById(appState.monitorData.tree, targetId);
    }
    if (targetNode) {
      const targetCyId = targetNode.is_cluster ? `c${targetNode.id}` : `j${targetNode.id}`;
      elements.push({
        data: { source: sourceId, target: targetCyId },
        classes: type
      });
    }
  }

  traverse(rootNode);
  return elements;
}

// ==================== STYLES ====================
function getGraphStyle() {
  return [
    {
      selector: "node",
      style: {
        label: "data(label)",
        "text-valign": "center",
        color: "#fff",
        "text-outline-width": 2,
        "text-outline-color": "#111",
        "font-size": 14,
        "font-weight": "500",
      }
    },
    {
      selector: ".cluster",
      style: {
        "background-color": "#1e3a8a",
        "background-opacity": 0.4,
        "border-color": "#60a5fa",
        "border-width": 6,
        shape: "roundrectangle",
        padding: 70,
        "text-valign": "top",
        "text-margin-y": -35,
        "font-weight": "bold",
        "font-size": 18,
      }
    },
    // Job colors by state
    {
      selector: ".job",
      style: {
        shape: "rectangle",
        width: 140,
        height: 60,
        "background-color": "#166534",   // default complete
      }
    },
    { selector: ".job[state-id='1']", style: { "background-color": "#ca8a04" } }, // pending
    { selector: ".job[state-id='2']", style: { "background-color": "#eab308" } }, // starting
    { selector: ".job[state-id='3']", style: { "background-color": "#22c55e" } }, // running
    { selector: ".job[state-id='4']", style: { "background-color": "#ef4444" } }, // failed
    { selector: ".job[state-id='5']", style: { "background-color": "#8b5cf6" } }, // cancelled
    { selector: ".job[state-id='6']", style: { "background-color": "#166534" } }, // complete

    {
      selector: ".highlight",
      style: {
        "border-color": "#67e8f9",
        "border-width": 8,
        "text-outline-color": "#67e8f9"
      }
    },

    // Edges
    { selector: ".needs", style: { width: 4, "line-color": "#f87171", "target-arrow-color": "#f87171", "target-arrow-shape": "triangle" }},
    { selector: ".needs_any", style: { width: 3, "line-color": "#4ade80", "target-arrow-color": "#4ade80", "target-arrow-shape": "vee", "line-style": "dashed" }},
    { selector: ".on_fail", style: { width: 3, "line-color": "#fbbf24", "target-arrow-color": "#fbbf24", "target-arrow-shape": "diamond" }}
  ];
}
