// Flowback Website Client Logic

document.addEventListener("DOMContentLoaded", () => {
  initTheme();
  initMobileMenu();
  initFAQ();
  initCopyButtons();
  initDownloadManifest();
});

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

// Mobile Menu
function initMobileMenu() {
  const menuBtn = document.getElementById("mobileMenuBtn");
  const navLinks = document.getElementById("navLinks");
  if (menuBtn && navLinks) {
    menuBtn.addEventListener("click", () => {
      navLinks.classList.toggle("open");
      const isOpen = navLinks.classList.contains("open");
      menuBtn.setAttribute("aria-expanded", isOpen);
    });
  }
}

// FAQ Accordion
function initFAQ() {
  const faqItems = document.querySelectorAll(".faq-item");
  faqItems.forEach(item => {
    const question = item.querySelector(".faq-question");
    if (question) {
      question.addEventListener("click", () => {
        const wasActive = item.classList.contains("active");
        faqItems.forEach(i => i.classList.remove("active"));
        if (!wasActive) {
          item.classList.add("active");
        }
      });
    }
  });
}

// Copy Code Snippets
function initCopyButtons() {
  const codeBlocks = document.querySelectorAll("pre");
  codeBlocks.forEach(block => {
    const btn = document.createElement("button");
    btn.className = "copy-btn";
    btn.textContent = "Copy";
    btn.setAttribute("aria-label", "Copy code snippet");
    btn.style.cssText = "position: absolute; right: 10px; top: 10px; font-size: 11px; padding: 4px 8px; background: var(--bg-card); color: var(--text-secondary); border: 1px solid var(--border-subtle); border-radius: 4px; cursor: pointer;";

    block.style.position = "relative";
    block.appendChild(btn);

    btn.addEventListener("click", async () => {
      const code = block.querySelector("code")?.innerText || block.innerText;
      try {
        await navigator.clipboard.writeText(code.replace(/Copy$/, "").trim());
        btn.textContent = "Copied!";
        setTimeout(() => { btn.textContent = "Copy"; }, 2000);
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
    // Keep server-rendered static fallback visible
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
        <code style="word-break: break-all; font-size: 0.8rem;">${a.sha256}</code>
      </div>
    `).join("");
  }
}
