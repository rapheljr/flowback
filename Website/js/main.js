// Flowback Website Client Logic

// Centralized external URL configuration
const FLOWBACK_LINKS = {
  buyMeACoffee: "https://buymeacoffee.com/flowback",
  github: "https://github.com/rapheljr/flowback",
  githubIssues: "https://github.com/rapheljr/flowback/issues",
  securityAdvisories: "https://github.com/rapheljr/flowback/security/advisories/new",
  license: "https://github.com/rapheljr/flowback/blob/main/LICENSE"
};

document.addEventListener("DOMContentLoaded", () => {
  initTheme();
  initMobileMenu();
  initFAQ();
  initCopyButtons();
  initDownloadManifest();
  initExternalLinks();
});

function initExternalLinks() {
  document.querySelectorAll("[data-bmc-link]").forEach(el => {
    el.setAttribute("href", FLOWBACK_LINKS.buyMeACoffee);
  });
}

// Theme Management
function initTheme() {
  const toggleBtn = document.getElementById("themeToggle");
  const currentTheme = localStorage.getItem("flowback-theme") || 
    (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");

  document.documentElement.setAttribute("data-theme", currentTheme);
  updateThemeIcon(currentTheme);

  if (toggleBtn) {
    toggleBtn.addEventListener("click", () => {
      const active = document.documentElement.getAttribute("data-theme");
      const next = active === "light" ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", next);
      localStorage.setItem("flowback-theme", next);
      updateThemeIcon(next);
    });
  }
}

function updateThemeIcon(theme) {
  const toggleBtn = document.getElementById("themeToggle");
  if (toggleBtn) {
    toggleBtn.textContent = theme === "light" ? "🌙" : "☀️";
    toggleBtn.setAttribute("aria-label", `Switch to ${theme === "light" ? "Dark" : "Light"} mode`);
  }
}

// Accessible Mobile Menu with Touch & Keyboard Escape Support
function initMobileMenu() {
  const menuBtn = document.getElementById("mobileMenuBtn");
  const navLinks = document.getElementById("navLinks");
  if (!menuBtn || !navLinks) return;

  function setMenuState(open) {
    navLinks.classList.toggle("open", open);
    menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
    menuBtn.textContent = open ? "✕" : "☰";
    menuBtn.setAttribute("aria-label", open ? "Close navigation menu" : "Open navigation menu");
    document.body.classList.toggle("nav-open", open);
  }

  menuBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    const isOpen = navLinks.classList.contains("open");
    setMenuState(!isOpen);
  });

  // Close menu on Escape key press and restore focus to menu button
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && navLinks.classList.contains("open")) {
      setMenuState(false);
      menuBtn.focus();
    }
  });

  // Close menu when clicking outside
  document.addEventListener("click", (e) => {
    if (navLinks.classList.contains("open") && !navLinks.contains(e.target) && e.target !== menuBtn) {
      setMenuState(false);
    }
  });

  // Close menu when clicking any link inside it
  navLinks.querySelectorAll("a").forEach(link => {
    link.addEventListener("click", () => {
      if (navLinks.classList.contains("open")) {
        setMenuState(false);
      }
    });
  });

  // Auto-close menu if resizing above tablet breakpoint (1024px)
  window.addEventListener("resize", () => {
    if (window.innerWidth > 1024 && navLinks.classList.contains("open")) {
      setMenuState(false);
    }
  });
}

// FAQ Accordion
function initFAQ() {
  const faqItems = document.querySelectorAll(".faq-item");
  faqItems.forEach(item => {
    const question = item.querySelector(".faq-question");
    if (question) {
      question.setAttribute("tabindex", "0");
      question.setAttribute("role", "button");
      question.setAttribute("aria-expanded", "false");

      const toggleItem = () => {
        const wasActive = item.classList.contains("active");
        faqItems.forEach(i => {
          i.classList.remove("active");
          const q = i.querySelector(".faq-question");
          if (q) q.setAttribute("aria-expanded", "false");
        });
        if (!wasActive) {
          item.classList.add("active");
          question.setAttribute("aria-expanded", "true");
        }
      };

      question.addEventListener("click", toggleItem);
      question.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          toggleItem();
        }
      });
    }
  });
}

// Copy Code Snippets with Enhanced Touch Targets & Feedback
function initCopyButtons() {
  const codeBlocks = document.querySelectorAll("pre");
  codeBlocks.forEach(block => {
    // Avoid duplicate buttons
    if (block.querySelector(".copy-btn")) return;

    const btn = document.createElement("button");
    btn.className = "copy-btn";
    btn.textContent = "Copy";
    btn.setAttribute("aria-label", "Copy code snippet");

    block.style.position = "relative";
    block.appendChild(btn);

    btn.addEventListener("click", async () => {
      const code = block.querySelector("code")?.innerText || block.innerText;
      try {
        await navigator.clipboard.writeText(code.replace(/Copy$/, "").trim());
        btn.textContent = "Copied!";
        btn.setAttribute("aria-label", "Copied to clipboard");
        setTimeout(() => {
          btn.textContent = "Copy";
          btn.setAttribute("aria-label", "Copy code snippet");
        }, 2000);
      } catch (err) {
        btn.textContent = "Failed";
      }
    });
  });
}

// Dynamic Release Manifest Loader on /download/
async function initDownloadManifest() {
  const container = document.getElementById("manifestContainer");
  if (!container) return;

  const manifestPath = container.dataset.manifestSrc || "../release-manifest.json";

  try {
    const response = await fetch(manifestPath);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    renderManifest(data);
  } catch (err) {
    console.warn("Could not load release-manifest.json dynamically, fallback active:", err);
  }
}

function renderManifest(manifest) {
  const versionEl = document.getElementById("manifestVersion");
  const dateEl = document.getElementById("manifestDate");
  const dmgBtn = document.getElementById("dmgDownloadBtn");
  const zipBtn = document.getElementById("zipDownloadBtn");
  const checksumsList = document.getElementById("checksumsList");
  const signStatus = document.getElementById("signatureStatusBadge");

  if (versionEl) versionEl.textContent = `v${manifest.version}`;
  if (dateEl) dateEl.textContent = manifest.releaseDate;

  if (signStatus) {
    if (manifest.signatureStatus === "signed-developer-id") {
      signStatus.textContent = "Apple Developer ID Signed";
      signStatus.className = "badge badge-supported";
    } else {
      signStatus.textContent = "Development Build (Ad-hoc Signed)";
      signStatus.className = "badge badge-partial";
    }
  }

  const dmgArtifact = manifest.artifacts.find(a => a.name.endsWith(".dmg"));
  const zipArtifact = manifest.artifacts.find(a => a.name.endsWith(".zip"));

  if (dmgBtn && dmgArtifact) {
    dmgBtn.href = dmgArtifact.downloadURL;
    dmgBtn.innerHTML = `⬇️ Download DMG <span style="font-size: 0.8em; opacity: 0.8;">(${dmgArtifact.architecture})</span>`;
  }

  if (zipBtn && zipArtifact) {
    zipBtn.href = zipArtifact.downloadURL;
    zipBtn.innerHTML = `⬇️ Download ZIP <span style="font-size: 0.8em; opacity: 0.8;">(${zipArtifact.architecture})</span>`;
  }

  if (checksumsList && manifest.artifacts.length > 0) {
    checksumsList.innerHTML = manifest.artifacts.map(a => `
      <div style="margin-bottom: 0.75rem; padding: 0.75rem; background: var(--bg-secondary); border-radius: var(--radius-sm); border: 1px solid var(--border-subtle);">
        <div style="font-weight: 600; font-size: 0.85rem; margin-bottom: 0.25rem;">${a.name} (${a.architecture})</div>
        <code style="word-break: break-all; overflow-wrap: anywhere; font-size: 0.8rem; display: block;">${a.sha256}</code>
      </div>
    `).join("");
  }
}
