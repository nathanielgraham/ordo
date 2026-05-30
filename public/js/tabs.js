// tabs.js – Clean tab system
import {
  loadDoc,
  refreshSettings,
  showPricingModal,
  renderDashboard,
  startDashboardLiveTimer,
  stopDashboardLiveTimer,
} from "./ui-handlers.js";
import { startLiveTimings, stopLiveTimings } from "./tree/tree-table.js";

// ==================== CORE ACTIVATION ====================
export function activateTab(tabId = null) {
  let targetTab = tabId;
  const hash = window.location.hash.replace("#", "").trim();

  if (!targetTab) {
    targetTab = hash ? hash.split("/")[0] : 
      (document.body.classList.contains("is-logged-in") ? "dashboard" : "docs");
  }

  console.log(`[ACTIVATE TAB] → "${targetTab}"`);

  // Visual nav
  document.querySelectorAll(".nav-tab").forEach(l => 
    l.classList.toggle("active", l.dataset.tab === targetTab)
  );

  // Special handling
  if (["monitor", "servers", "calendars"].includes(targetTab)) {
    startLiveTimings();
  } else {
    stopLiveTimings();
  }

  if (targetTab === "dashboard") {
      renderDashboard();
      startDashboardLiveTimer();
  }
  else {
      stopDashboardLiveTimer();
  }

  if (targetTab === "settings") {
    const loading = document.getElementById("settings-loading");
    const content = document.getElementById("settings-content");

    if (loading) loading.style.display = "none";
    if (content) content.style.display = "block";

    // Force refresh data
    refreshSettings();
  }
  else if (targetTab === "docs") {
    const slug = hash.split("/")[1];
    const file = slug ? (slug.endsWith(".md") ? slug : `${slug}.md`) : "overview.md";
    setTimeout(() => loadDoc(file), 100);
  }

  // Content switch
  document.querySelectorAll(".tab-content").forEach(el => el.classList.remove("active"));
  const content = document.getElementById(targetTab);
  if (content) content.classList.add("active");

}

// ==================== CLICK HANDLER ====================
function handleTabClick(e) {
  e.preventDefault();
  const tabId = e.currentTarget.dataset.tab;

  if (tabId === "pricing") {
    showPricingModal();
    return;
  }

  // Only update hash for docs deep links
  if (tabId === "docs") {
    window.location.hash = "docs";
  } else if (window.location.hash) {
    history.replaceState(null, null, window.location.pathname);
  }

  activateTab(tabId);
}

// ==================== INITIALIZATION ====================
export function initTabSystem() {
  document.querySelectorAll(".nav-tab[data-tab]").forEach(link => {
    link.addEventListener("click", handleTabClick);
  });

  // Initial activation
  setTimeout(activateTab, 150);
}
