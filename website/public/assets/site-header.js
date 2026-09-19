(() => {
  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
  const root = document.documentElement;

  const getResolvedTheme = () => {
    if (root.dataset.theme === "light" || root.dataset.theme === "dark") return root.dataset.theme;
    return colorScheme.matches ? "dark" : "light";
  };

  const updateThemeColor = (theme) => {
    document.querySelectorAll("[data-site-theme-color]").forEach((meta) => {
      meta.setAttribute("content", theme === "dark" ? "#12121a" : "#f7f7ff");
    });
  };

  const syncThemeButton = (button) => {
    const theme = getResolvedTheme();
    const icon = button.querySelector("[data-theme-icon]");
    button.setAttribute("aria-label", theme === "dark" ? button.dataset.lightLabel : button.dataset.darkLabel);
    if (icon) icon.textContent = theme === "dark" ? "light_mode" : "dark_mode";
    updateThemeColor(theme);
  };

  document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
    if (!(button instanceof HTMLButtonElement) || button.dataset.themeReady === "true") return;
    button.dataset.themeReady = "true";
    syncThemeButton(button);
    button.addEventListener("click", () => {
      if (root.classList.contains("theme-transitioning") || root.classList.contains("theme-transition-fallback")) return;
      const theme = getResolvedTheme() === "dark" ? "light" : "dark";
      const applyTheme = () => {
        root.dataset.theme = theme;
        try {
          localStorage.setItem("sidey-theme", theme);
        } catch {}
        syncThemeButton(button);
      };

      if (!reducedMotion.matches && typeof document.startViewTransition === "function") {
        root.classList.add("theme-transitioning");
        document.startViewTransition(applyTheme).finished.finally(() => root.classList.remove("theme-transitioning"));
        return;
      }

      if (!reducedMotion.matches) {
        root.classList.add("theme-transition-fallback");
        requestAnimationFrame(() => requestAnimationFrame(() => {
          applyTheme();
          window.setTimeout(() => root.classList.remove("theme-transition-fallback"), 280);
        }));
        return;
      }

      applyTheme();
    });
  });

  colorScheme.addEventListener("change", () => {
    if (root.dataset.theme) return;
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      if (button instanceof HTMLButtonElement) syncThemeButton(button);
    });
  });

  document.querySelectorAll("[data-site-header]").forEach((header) => {
    if (header.dataset.menuReady === "true") return;
    const toggle = header.querySelector("[data-nav-menu-toggle]");
    const menu = header.querySelector("[data-nav-menu]");
    if (!(toggle instanceof HTMLButtonElement) || !(menu instanceof HTMLElement)) return;
    header.dataset.menuReady = "true";

    const setOpen = (open, restoreFocus = false) => {
      header.classList.toggle("mobile-menu-open", open);
      document.documentElement.classList.toggle("site-menu-open", open);
      toggle.setAttribute("aria-expanded", String(open));
      toggle.setAttribute("aria-label", open ? toggle.dataset.closeLabel : toggle.dataset.openLabel);
      if (open) {
        menu.querySelector("a")?.focus();
      } else if (restoreFocus) {
        toggle.focus();
      }
    };

    toggle.addEventListener("click", () => setOpen(toggle.getAttribute("aria-expanded") !== "true", true));
    menu.addEventListener("click", (event) => {
      if (!(event.target instanceof Element)) return;
      const link = event.target.closest("a");
      if (!(link instanceof HTMLAnchorElement)) return;

      const destination = new URL(link.href, window.location.href);
      const current = new URL(window.location.href);
      const target = destination.hash ? document.getElementById(destination.hash.slice(1)) : null;
      const isCurrentDocument = destination.origin === current.origin && destination.pathname === current.pathname;

      if (isCurrentDocument && target) {
        event.preventDefault();
        setOpen(false);
        window.setTimeout(() => {
          const hashChanged = window.location.hash !== destination.hash;
          if (hashChanged) window.location.hash = destination.hash;
          target.scrollIntoView({ behavior: reducedMotion.matches ? "auto" : "smooth", block: "start" });
          if (!hashChanged) window.dispatchEvent(new HashChangeEvent("hashchange"));
        }, 0);
        return;
      }

      setOpen(false);
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") setOpen(false, true);
    });
    window.addEventListener("resize", () => {
      if (window.innerWidth > 700 && toggle.getAttribute("aria-expanded") === "true") setOpen(false);
    }, { passive: true });
    window.addEventListener("pagehide", () => document.documentElement.classList.remove("site-menu-open"));
  });
})();
