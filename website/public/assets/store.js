(function () {
  "use strict";

  const revealStoreImage = (image) => {
    image.closest(".store-product-media")?.classList.add("is-loaded");
  };

  document.querySelectorAll(".store-product-image").forEach((image) => {
    if (image.complete) {
      revealStoreImage(image);
      return;
    }
    image.addEventListener("load", () => revealStoreImage(image), { once: true });
  });

  const dialog = document.getElementById("store-preview-dialog");
  if (!(dialog instanceof HTMLDialogElement)) {
    return;
  }

  const stage = dialog.querySelector("[data-store-preview-stage]");
  const title = dialog.querySelector("[data-store-preview-title]");
  const description = dialog.querySelector("[data-store-preview-description]");
  const closeButton = dialog.querySelector("[data-store-preview-close]");
  let closeTimer;

  const closeDialog = () => {
    if (!dialog.open || dialog.dataset.state === "closing") return;
    dialog.dataset.state = "closing";
    closeTimer = window.setTimeout(() => dialog.close(), 160);
  };

  const makeArt = (source, mode, role) => {
    const frame = document.createElement("span");
    frame.className = `store-dialog-art store-dialog-art-${mode}${role ? ` store-dialog-art-${role}` : ""}`;
    const image = document.createElement("img");
    image.src = source;
    image.alt = "";
    image.decoding = "async";
    frame.appendChild(image);
    return frame;
  };

  const makeActor = (role, actionSource, baseSource) => {
    const actor = document.createElement("span");
    actor.className = `store-preview-actor store-preview-actor-${role}`;
    const baseImage = document.createElement("img");
    baseImage.className = "store-preview-actor-base";
    baseImage.src = baseSource;
    baseImage.alt = "";
    baseImage.decoding = "async";
    const actionImage = document.createElement("img");
    actionImage.className = "store-preview-actor-action";
    actionImage.src = actionSource;
    actionImage.alt = "";
    actionImage.decoding = "async";
    actor.append(baseImage, actionImage);
    return actor;
  };

  const makeBubble = (theme, decoration, messageText) => {
    const scene = document.createElement("span");
    scene.className = "store-bubble-scene store-dialog-bubble-scene";
    const bubbleWrap = document.createElement("span");
    bubbleWrap.className = `store-bubble-wrap store-dialog-bubble-wrap store-bubble-wrap-${theme}`;
    const bubble = document.createElement("span");
    bubble.className = `store-bubble store-dialog-bubble store-bubble-${theme}`;
    const message = document.createElement("span");
    message.textContent = messageText;
    const actor = document.createElement("span");
    actor.className = "store-bubble-actor store-dialog-bubble-actor";
    const actorImage = document.createElement("img");
    actorImage.src = `${document.documentElement.dataset.baseUrl ?? "/SIDEY/"}assets/characters/pixel_hamster.png`;
    actorImage.alt = "";
    actorImage.decoding = "async";
    actor.append(actorImage);
    if (decoration) {
      const image = document.createElement("img");
      image.className = "store-bubble-decoration";
      image.src = decoration;
      image.alt = "";
      image.decoding = "async";
      bubbleWrap.append(image);
    }
    bubble.append(message);
    bubbleWrap.prepend(bubble);
    scene.append(bubbleWrap, actor);
    return scene;
  };

  document.querySelectorAll("[data-store-preview]").forEach((button) => {
    button.addEventListener("click", () => {
      const kind = button.dataset.previewKind ?? "character";
      const mode = button.dataset.previewMode ?? "character";
      const source = button.dataset.previewSrc;
      if ((!source && kind !== "bubble") || !stage || !title || !description) {
        return;
      }

      const base = document.documentElement.dataset.baseUrl ?? "/SIDEY/";
      const hamster = `${base}assets/characters/pixel_hamster.png`;
      const rabbit = `${base}assets/characters/pixel_rabbit.png`;
      const hamsterAction = `${base}assets/previewer/pixel_hamster_throw_hit.png`;
      const rabbitAction = `${base}assets/previewer/pixel_rabbit_throw_hit.png`;
      if (kind === "throwable") {
        const children = [makeActor("source", hamsterAction, hamster)];
        if (mode === "cannon" && button.dataset.previewEmitter) {
          children.push(makeArt(button.dataset.previewEmitter, "emitter", "emitter"));
        }
        children.push(makeArt(source, "projectile", "projectile"));
        children.push(makeArt(source, "impact", "impact"));
        children.push(makeActor("target", rabbitAction, rabbit));
        stage.replaceChildren(...children);
      } else if (kind === "bubble") {
        const decoration = button.dataset.previewDecoration;
        const theme = button.dataset.previewTheme;
        if (!theme) return;
        stage.replaceChildren(makeBubble(theme, decoration, button.dataset.previewMessage ?? ""));
      } else {
        const character = makeArt(source, "character");
        character.classList.toggle("store-dialog-art-mirrors", button.dataset.previewMirrors === "true");
        stage.replaceChildren(character);
      }
      stage.dataset.previewKind = kind;
      stage.dataset.previewMode = mode;
      title.textContent = button.dataset.previewTitle ?? "";
      description.textContent = button.dataset.previewDescription ?? "";
      dialog.showModal();
      dialog.dataset.state = "open";
      closeButton?.focus();
    });
  });

  closeButton?.addEventListener("click", closeDialog);
  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    closeDialog();
  });
  dialog.addEventListener("close", () => {
    window.clearTimeout(closeTimer);
    delete dialog.dataset.state;
    stage?.replaceChildren();
  });
  dialog.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    const inside = event.clientX >= bounds.left && event.clientX <= bounds.right
      && event.clientY >= bounds.top && event.clientY <= bounds.bottom;
    if (!inside) {
      closeDialog();
    }
  });
})();
