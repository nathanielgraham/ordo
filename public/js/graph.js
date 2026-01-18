// graph.js – dependency graph visualization (Cytoscape + Dagre)

import { appState } from "./state.js";
import { findClusterById, findJobById } from "./utils.js";

export function openDependencyGraph(clusterId, clusterName) {
  // Update title
  document.getElementById("graph-title").textContent =
    `${clusterName || "Cluster"}`;

  // Show modal
  const modal = document.getElementById("graph-modal");
  modal.classList.add("is-active");

  const container = document.getElementById("graph-container");

  // Show loading spinner
  container.innerHTML =
    '<div class="has-text-centered p-6"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';

  // Force container to take full available height
  container.style.height = "100%";
  container.style.minHeight = "calc(100vh - 200px)"; // subtract header + padding/margins

  // Force browser to reflow layout immediately (critical!)
  void container.offsetHeight;

  // Log initial size (should already be better after reflow)
  console.log(
    "Initial container size after reflow:",
    container.clientWidth,
    container.clientHeight,
  );

  // Delay Cytoscape init slightly — wait for modal CSS transitions to finish
  setTimeout(() => {
    console.log(
      "Delayed container size (before cy init):",
      container.clientWidth,
      container.clientHeight,
    );

    const rootNode = findClusterById(appState.monitorData.tree, clusterId);
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

      // Children recursion
      if (node.children) node.children.forEach(traverse);
      if (node.jobs)
        node.jobs.forEach((job) => traverse({ ...job, is_cluster: false }));

      // Blocking needs (AND)
      if (node.needs_ids?.length) {
        node.needs_ids.forEach((depId) => {
          const depIdNum = Number(depId);
          let depNode = null;

          if (!node.is_cluster) {
            depNode = findJobById(appState.monitorData.tree, depIdNum);
          }
          if (node.is_cluster) {
            depNode = findClusterById(appState.monitorData.tree, depIdNum);
          }

          if (depNode) {
            traverse(depNode);
            elements.push({
              data: { source: cyId, target: getCyId(depNode), label: "needs" },
              classes: "needs",
            });
          }
        });
      }

      // Needs any (OR)
      if (node.needs_any_ids?.length) {
        node.needs_any_ids.forEach((depId) => {
          const depIdNum = Number(depId);
          let depNode = null;

          if (!node.is_cluster) {
            depNode = findJobById(appState.monitorData.tree, depIdNum);
          }
          if (node.is_cluster) {
            depNode = findClusterById(appState.monitorData.tree, depIdNum);
          }

          if (depNode) {
            traverse(depNode);
            elements.push({
              data: {
                source: cyId,
                target: getCyId(depNode),
                label: "needs any",
              },
              classes: "needs_any",
            });
          }
        });
      }

      // On fail (recovery) — typically node → recovery (failed → fallback)
      if (node.on_fail_id) {
        const failIdNum = Number(node.on_fail_id);
        const failNode = findClusterById(appState.monitorData.tree, failIdNum);
        if (failNode && node.is_cluster) {
          traverse(failNode);
          elements.push({
            data: { source: cyId, target: getCyId(failNode), label: "on fail" },
            classes: "on_fail",
          });
        }
      }

      return cyId;
    }

    traverse(rootNode);

    // Final size check
    console.log(
      "Final container size before cy init:",
      container.clientWidth,
      container.clientHeight,
    );

    // Clean up previous graph
    if (container.cy) container.cy.destroy();

    // Safety timeout to stop layout if it hangs
    const layoutTimeout = setTimeout(() => {
      console.warn("Layout taking too long — stopping Cytoscape");
      container.cy?.stop();
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    }, 10000); // 10 seconds

    // Initialize Cytoscape
    container.cy = cytoscape({
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

        // Blocking needs (AND) → solid red, bold arrow
        {
          selector: ".needs",
          style: {
            width: 4,
            "line-color": "#ff3366", // strong red
            "target-arrow-color": "#ff3366",
            "target-arrow-shape": "triangle",
            "curve-style": "bezier",
            "arrow-scale": 1.8, // bigger arrow for emphasis
          },
        },

        // Needs any (OR) → dashed cyan (OR = permissive)
        {
          selector: ".needs_any",
          style: {
            width: 2,
            "line-color": "#00ffff",
            "target-arrow-color": "#00ffff",
            "target-arrow-shape": "vee",
            "line-style": "dashed",
            "arrow-scale": 1.3,
          },
        },

        // On fail (recovery) → solid yellow/orange with diamond arrow
        {
          selector: ".on_fail",
          style: {
            width: 3,
            "line-color": "#ffaa00", // bright orange/yellow for warning/recovery
            "target-arrow-color": "#ffaa00",
            "target-arrow-shape": "diamond",
            "curve-style": "bezier",
            "arrow-scale": 1.5,
            label: "data(label)", // keep label
            "font-size": 10,
            "text-background-color": "rgba(0,0,0,0.67)",
            "text-background-opacity": 0.7,
            "text-background-padding": "3px",
            color: "#ffaa00",
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

    // Clean up timeout and spinner on success
    container.cy.on("layoutstop", () => {
      clearTimeout(layoutTimeout);
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
      container.cy.fit(container.cy.elements(), 100);
      container.cy.center();
    });

    container.cy.ready(() => {
      clearTimeout(layoutTimeout);
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    });

    // Zoom controls (unchanged)
    document.getElementById("zoom-in")?.addEventListener("click", () => {
      container.cy.zoom(container.cy.zoom() * 1.2);
    });
    document.getElementById("zoom-out")?.addEventListener("click", () => {
      container.cy.zoom(container.cy.zoom() / 1.2);
    });
    document.getElementById("zoom-fit")?.addEventListener("click", () => {
      container.cy.fit(container.cy.elements(), 100);
      container.cy.center();
    });

    // Ultimate fallback (if everything fails)
    setTimeout(() => {
      const spinner = container.querySelector(".has-text-centered");
      if (spinner) spinner.remove();
    }, 12000);
  }, 150); // 150ms delay — enough for modal to expand
}

/*
// Opens the dependency graph modal for a given cluster
export function openDependencyGraph(clusterId, clusterName) {
  document.getElementById("graph-title").textContent = `${clusterName}`;
  document.getElementById("graph-modal").classList.add("is-active");

  const container = document.getElementById("graph-container");
  container.innerHTML = '<div class="has-text-centered p-6"><i class="fas fa-spinner fa-spin fa-3x"></i></div>';

  const rootNode = findClusterById(appState.monitorData.tree, clusterId);
  if (!rootNode) {
    container.innerHTML = '<p class="has-text-danger has-text-centered">Cluster not found</p>';
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

    // Children recursion
    if (node.children) node.children.forEach(traverse);
    if (node.jobs) node.jobs.forEach((job) => traverse({ ...job, is_cluster: false }));

    // Blocking needs (AND)
    if (node.needs_ids?.length) {
      node.needs_ids.forEach((depId) => {
        const dep = findClusterById(appState.monitorData.tree, depId);
        if (dep) {
          traverse(dep);
          const source = node.is_cluster ? getCyId(dep) : cyId;
          const target = node.is_cluster ? cyId : getCyId(dep);
          elements.push({
            data: { source, target, label: "needs" },
            classes: "needs",
          });
        }
      });
    }

    // Needs any (OR)
    if (node.needs_any_ids?.length) {
      node.needs_any_ids.forEach((depId) => {
        const dep = findClusterById(appState.monitorData.tree, depId);
        if (dep) {
          traverse(dep);
          const source = node.is_cluster ? getCyId(dep) : cyId;
          const target = node.is_cluster ? cyId : getCyId(dep);
          elements.push({
            data: { source, target, label: "needs any" },
            classes: "needs_any",
          });
        }
      });
    }

    // On fail (recovery cluster)
    if (node.on_fail_id) {
      const fail = findClusterById(appState.monitorData.tree, node.on_fail_id);
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

  // Clean up previous graph if exists
  if (container.cy) container.cy.destroy();

  // Initialize Cytoscape
  container.cy = cytoscape({
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

  // Fit to viewport after layout
  container.cy.on("layoutstop", () => {
    container.cy.fit(container.cy.elements(), 100);
    container.cy.center();
  });

  // Zoom controls (static buttons in modal)
  document.getElementById("zoom-in")?.addEventListener("click", () => {
    container.cy.zoom(container.cy.zoom() * 1.2);
  });

  document.getElementById("zoom-out")?.addEventListener("click", () => {
    container.cy.zoom(container.cy.zoom() / 1.2);
  });

  document.getElementById("zoom-fit")?.addEventListener("click", () => {
    container.cy.fit(container.cy.elements(), 100);
    container.cy.center();
  });

  // Remove spinner after layout (with fallback)
  const removeSpinner = () => {
    const spinner = container.querySelector(".has-text-centered");
    if (spinner) spinner.remove();
  };
  container.cy.on("layoutstop", removeSpinner);
  container.cy.ready(removeSpinner);
  setTimeout(removeSpinner, 3000); // safety fallback
}

*/
