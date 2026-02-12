// tree/tree-listeners.js
import { appState, updateCollapsedClusters } from "../state.js";

export function attachTreeListeners() {
  const treeBody = document.getElementById("tree-body");
  if (!treeBody) return;
  treeBody.addEventListener("click", (e) => {
    const toggle = e.target.closest(".ordo-toggle");
    if (toggle) {
      const row = toggle.closest("tr");
      const clusterId = row.dataset.id;

      const isCollapsed = row.classList.toggle("collapsed");

      if (isCollapsed) {
        appState.collapsedClusters.add(clusterId);
      } else {
        appState.collapsedClusters.delete(clusterId);
      }
      updateCollapsedClusters();

      toggleSubtree(clusterId, isCollapsed);
      row.setAttribute("aria-expanded", (!isCollapsed).toString());
      return;
    }
  });
}

// Recursive subtree hide/show with nested respect
export function toggleSubtree(parentId, hideParent) {
  const children = document.querySelectorAll(`tr[data-parent="${parentId}"]`);

  children.forEach((child) => {
    const isCluster = child.classList.contains("ordo-cluster-row");
    const childCollapsed = isCluster && child.classList.contains("collapsed");

    if (hideParent) {
      child.classList.add("hidden");
      if (isCluster) toggleSubtree(child.dataset.id, true);  // force hide descendants
    } else {
      child.classList.remove("hidden");
      if (isCluster) toggleSubtree(child.dataset.id, childCollapsed);  // respect child's state
    }
  });
}

export function forceExpandDescendants(startId) {
  const children = document.querySelectorAll(`tr[data-parent="${startId}"]`);
  children.forEach((childRow) => {
    if (childRow.classList.contains("ordo-cluster-row")) {
      childRow.classList.remove("collapsed");
      forceExpandDescendants(childRow.dataset.id);
    }
  });
}
