(function () {
  "use strict";

  const copyButtons = document.querySelectorAll("[data-copy-target]");

  async function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();

    const copied = document.execCommand("copy");
    textarea.remove();

    if (!copied) {
      throw new Error("Copy command failed");
    }
  }

  copyButtons.forEach((button) => {
    let resetTimer;

    button.addEventListener("click", async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      const status = document.getElementById(button.dataset.copyStatus);

      if (!target) {
        return;
      }

      window.clearTimeout(resetTimer);
      button.dataset.copyState = "idle";
      if (status) {
        status.textContent = "";
      }

      try {
        await copyText(target.textContent.trim());
        button.dataset.copyState = "success";
        if (status) {
          status.textContent = button.dataset.copyAnnouncement;
        }
      } catch (_error) {
        button.dataset.copyState = "failure";
        if (status) {
          status.textContent = button.dataset.copyFailureAnnouncement;
        }
      }

      resetTimer = window.setTimeout(() => {
        button.dataset.copyState = "idle";
        if (status) {
          status.textContent = "";
        }
      }, 2000);
    });
  });
})();
