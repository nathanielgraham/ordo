// tabs.js – tab navigation + default activation

export function attachTabListeners() {
  const tabLinks = document.querySelectorAll(".nav-link[data-tab]");
  console.log(`Found ${tabLinks.length} tab links`);

  tabLinks.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      const tabId = link.dataset.tab;

      if (tabId === "monitor") {
        import("./tree-table.js").then((m) => m.startTreeTimings());
      } else {
        import("./tree-table.js").then((m) => m.stopTreeTimings());
      }

      // Update active tab style
      tabLinks.forEach((l) => l.classList.remove("is-active"));
      link.classList.add("is-active");

      // Switch content visibility
      document.querySelectorAll(".tab-content").forEach((s) => {
        s.classList.remove("active");
      });

      const target = document.getElementById(tabId);
      if (target) {
        target.classList.add("active");
        console.log(`Switched to #${tabId}`);
      } else {
        console.error(`Tab content missing: #${tabId}`);
      }
    });
  });
}

export function activateDefaultTab() {
  const isLoggedIn = document.body.classList.contains("is-logged-in");
  const defaultTab = isLoggedIn ? "monitor" : "about";

  const link = document.querySelector(`.nav-link[data-tab="${defaultTab}"]`);
  if (link) {
    console.log(`Activating default tab: ${defaultTab}`);
    link.click();
  } else {
    console.warn(`Default tab link not found: ${defaultTab}`);
  }
}
