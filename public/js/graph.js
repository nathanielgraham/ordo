// public/js/graph.js – Clean & Reliable Dependency Graph (Final)
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
  container.style.height = "100%";
  container.style.minHeight = "32rem";

  setTimeout(() => {
    const rootNode = findClusterById(appState.monitorData?.tree, clusterId);
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
        rankDir: "LR",           // Left → Right (best for dependency flows)
        spacingFactor: 1.4,
        nodeSep: 60,
        edgeSep: 25,
        rankSep: 110,
        fit: true,
        padding: 50,
        animate: false
      },
      zoomingEnabled: true,
      panningEnabled: true,
      boxSelectionEnabled: false,
      minZoom: 0.25,
      maxZoom: 6,
    });

    // Click to edit
    currentCy.on('tap', 'node', (evt) => {
      const node = evt.target;
      const rawId = node.data('id');
      const idStr = String(rawId).replace(/^[jc]/, '');
      const numericId = Number(idStr);
      const isCluster = rawId.toString().startsWith('c');

      modal.classList.remove("active");
      if (isCluster) openClusterModal("edit", numericId);
      else openJobModal("edit", numericId);
    });

    currentCy.on('mouseover', 'node', (evt) => evt.target.addClass('highlight'));
    currentCy.on('mouseout', 'node', (evt) => evt.target.removeClass('highlight'));

    // Controls
    document.getElementById("graph-fit-btn").onclick = () => currentCy.fit();
    document.getElementById("graph-zoom-in").onclick = () => currentCy.zoom(currentCy.zoom() * 1.25);
    document.getElementById("graph-zoom-out").onclick = () => currentCy.zoom(currentCy.zoom() * 0.8);
    document.getElementById("graph-reset").onclick = () => { currentCy.fit(); currentCy.center(); };

    const removeSpinner = () => {
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    };
    currentCy.on("layoutstop", removeSpinner);
    currentCy.ready(removeSpinner);
  }, 150);
}

// ==================== BUILD FUNCTION ====================
function buildGraphElements(rootNode) {
  const elements = [];
  const nodeMap = new Map();
  const includedIds = new Set();

  const addNode = (item, parentPrefix = null, viaOnFail = false) => {
    if (!item?.id) return null;
    const isCluster = !!item.is_cluster || item.children?.length > 0;
    const prefix = isCluster ? 'c' : 'j';
    const pid = `${prefix}${item.id}`;

    if (nodeMap.has(pid)) {
      if (viaOnFail) {
        const existing = nodeMap.get(pid);
        if (existing) existing.classes.push('on-fail-target');
      }
      return pid;
    }

    const nodeEl = {
      data: {
        id: pid,
        label: isCluster ? `${item.name}/` : item.name,
        is_cluster: isCluster,
        originalId: Number(item.id)
      },
      classes: [
        isCluster ? 'cluster-node' : 'job-node',
        viaOnFail ? 'on-fail-target' : ''
      ]
    };

    if (parentPrefix) nodeEl.data.parent = parentPrefix;

    elements.push(nodeEl);
    nodeMap.set(pid, nodeEl);
    includedIds.add(Number(item.id));
    return pid;
  };

  const findAny = (originalId) => {
    const id = Number(originalId);
    if (appState.clustersMap?.has(id)) return { ...appState.clustersMap.get(id), is_cluster: true };
    if (appState.jobsMap?.has(id)) return { ...appState.jobsMap.get(id), is_cluster: false };
    return findClusterById(rootNode, id) || findJobById(rootNode, id);
  };

  const traverse = (node, parentPrefix = null) => {
    if (!node) return;
    const myPrefix = addNode(node, parentPrefix);

    // Children for compound nodes
    if (node.is_cluster) {
      [...(node.children || []), ...(node.jobs || [])].forEach(child => {
        traverse(child, myPrefix);
      });
    }

    // Dependencies (needs / needs_any) — supports external clusters
    ['needs_ids', 'needs_any_ids'].forEach(key => {
      if (!Array.isArray(node[key])) return;
      node[key].forEach(depId => {
        const dep = findAny(depId);
        if (dep) {
          const depPrefix = addNode(dep);
          elements.push({
            data: { id: `e${myPrefix}-${depPrefix}`, source: myPrefix, target: depPrefix },
            classes: [key === 'needs_ids' ? 'needs' : 'needs-any']
          });
        }
      });
    });

    // On Fail — special styling
    if (node.on_fail_id) {
      const fail = findAny(node.on_fail_id);
      if (fail) {
        const failPrefix = addNode(fail, null, true); // mark for orange border
        elements.push({
          data: { id: `of${myPrefix}-${failPrefix}`, source: myPrefix, target: failPrefix },
          classes: ['on-fail']
        });
      }
    }
  };

  traverse(rootNode);
  console.log(`[Graph] Built ${elements.length} elements for ${rootNode.name}`);
  return elements;
}

// ==================== STYLES ====================
function getGraphStyle() {
  return [
    { selector: 'node', style: {
      'label': 'data(label)',
      'text-valign': 'center',
      'color': '#fff',
      'text-outline-width': 2,
      'text-outline-color': '#0a0a0a',
      'font-size': 13,
      'font-weight': 500
    }},
    { selector: '.cluster-node', style: {
      'background-color': '#1e3a8a',
      'background-opacity': 0.35,
      'border-color': '#60a5fa',
      'border-width': 5,
      'shape': 'roundrectangle',
      'padding': 45,
      'text-valign': 'top',
      'text-margin-y': -32,
      'font-size': 16,
      'font-weight': 700
    }},
    { selector: '.job-node', style: {
      'shape': 'rectangle',
      'width': 135,
      'height': 54,
      'background-color': '#166534'
    }},
    { selector: '.on-fail-target', style: {
      'border-style': 'dashed',
      'border-color': '#f59e0b',
      'border-width': 4,
      'background-color': '#312e81',
      'background-opacity': 0.8
    }},
    { selector: '.highlight', style: {
      'border-color': '#67e8f9',
      'border-width': 6
    }},

    // Edges
    { selector: '.needs', style: {
      'width': 3.5,
      'line-color': '#f87171',
      'target-arrow-color': '#f87171',
      'target-arrow-shape': 'triangle',
      'curve-style': 'bezier'
    }},
    { selector: '.needs-any', style: {
      'width': 3,
      'line-color': '#4ade80',
      'target-arrow-color': '#4ade80',
      'target-arrow-shape': 'vee',
      'line-style': 'dashed',
      'curve-style': 'bezier'
    }},
    { selector: '.on-fail', style: {
      'width': 3,
      'line-color': '#fbbf24',
      'target-arrow-color': '#fbbf24',
      'target-arrow-shape': 'diamond',
      'curve-style': 'bezier'
    }}
  ];
}
