// tabs.js – tab navigation + default activation
import {
  loadDoc,
  refreshSettings,
  showPricingModal,
  renderDashboard,
  startDashboardLiveTimer,
  stopDashboardLiveTimer,
  loadDashboardStats,
} from "./ui-handlers.js";
import { startLiveTimings, stopLiveTimings } from "./tree/tree-table.js";
import { appState } from "./state.js";

// ==================== UNIFIED TAB ACTIVATION ====================
export function activateTab() {
  const hash = window.location.hash.replace("#", "").trim();
  console.log(`[ACTIVATE TAB] Raw hash = "${hash}"`);

  if (hash) {
    const parts = hash.split("/");
    const tabName = parts[0];
    let docSlug = parts[1];

    console.log(`[ACTIVATE TAB] tab=${tabName}, slug=${docSlug}`);

    // Activate main Docs tab
    const tabLink = document.querySelector(`.nav-tab[data-tab="${tabName}"]`);
    if (tabLink) tabLink.click();

    if (tabName === "docs" && docSlug) {
      // Normalize slug to filename
      let filename = docSlug.endsWith(".md") ? docSlug : `${docSlug}.md`;

      // Special mappings
      if (docSlug === "rest-api" || docSlug === "rest")
        filename = "rest-api.md";
      if (docSlug === "video-tutorials") filename = "video-tutorials.md";

      console.log(`[ACTIVATE TAB] Attempting to load: ${filename}`);

      setTimeout(() => {
        const link = document.querySelector(`a[data-file="${filename}"]`);
        if (link) {
          console.log(`[ACTIVATE TAB] ✅ SUCCESS: Clicking ${filename}`);
          link.click();
        } else {
          console.error(`[ACTIVATE TAB] ❌ Link not found for ${filename}`);
          // Fallback
          const fallback = document.querySelector('a[data-file="overview.md"]');
          if (fallback) fallback.click();
        }
      }, 450);
    }
    return;
  }

  // Default for returning users
  const isLoggedIn = document.body.classList.contains("is-logged-in");
  if (isLoggedIn) {
    document.querySelector('.nav-tab[data-tab="dashboard"]')?.click();
  } else {
    document.querySelector('.nav-tab[data-tab="about"]')?.click();
  }
}

export function attachTabListeners() {
  const tabLinks = document.querySelectorAll(".nav-tab[data-tab]");
  console.log(`Found ${tabLinks.length} tab links`);

  let currentTabId = null;

  tabLinks.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();

      const tabId = link.dataset.tab;
      const oldTabId = currentTabId;
      currentTabId = tabId;

      console.log("[DEBUG] Tab clicked:", tabId, "(previous:", oldTabId, ")");

      // Special cases
      if (tabId === "pricing") {
        showPricingModal();
        return;
      }

      // ==================== DASHBOARD ====================
      if (tabId === "dashboard") {
        console.log("[DEBUG] Activating dashboard tab");

        renderDashboard();

        // Force initial stats load on first visit
        if (!appState.dashboardStatsLoaded) {
          appState.dashboardStatsLoaded = true;
          loadDashboardStats();
        }

        startDashboardLiveTimer();
      } else if (oldTabId === "dashboard") {
        appState.dashboardStatsLoaded = false;
        stopDashboardLiveTimer();
      }

      // Other tabs
      if (tabId === "docs") {
        const docsContent = document.getElementById("docs-content");
        if (
          docsContent &&
          (!docsContent.innerHTML || docsContent.innerHTML.trim() === "")
        ) {
          loadDoc("overview.md");
        }
      }

      if (tabId === "settings") {
        console.log("[DEBUG] Activating Settings tab");

        const loading = document.getElementById("settings-loading");
        const content = document.getElementById("settings-content");

        if (loading) loading.style.display = "none";
        if (content) content.style.display = "block";

        // Force refresh data
        refreshSettings();
      }

      // Live timings
      if (tabId === "monitor" || tabId === "servers" || tabId === "calendars") {
        startLiveTimings();
      } else {
        stopLiveTimings();
      }

      // Switch active tab
      tabLinks.forEach((l) => l.classList.remove("active"));
      link.classList.add("active");

      // Switch content
      document
        .querySelectorAll(".tab-content")
        .forEach((s) => s.classList.remove("active"));
      let target =
        document.getElementById(tabId) ||
        document.querySelector(`section[id="${tabId}"]`);
      if (target) target.classList.add("active");
    });
  });
}
