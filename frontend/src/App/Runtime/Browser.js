let googleScriptPromise = null;
let googleCredentialHandler = null;
let googleErrorHandler = null;
let initializedGoogleClientId = null;

const ensureRoot = () => {
  const existing = document.getElementById("app");

  if (existing) {
    return existing;
  }

  const root = document.createElement("div");
  root.id = "app";
  document.body.appendChild(root);
  return root;
};

const loadGoogleIdentityServices = () => {
  if (googleScriptPromise) {
    return googleScriptPromise;
  }

  googleScriptPromise = new Promise((resolve, reject) => {
    const existing = document.querySelector("script[data-google-gsi='true']");

    if (existing && window.google?.accounts?.id) {
      resolve(window.google);
      return;
    }

    const script = existing || document.createElement("script");
    script.src = "https://accounts.google.com/gsi/client";
    script.async = true;
    script.defer = true;
    script.dataset.googleGsi = "true";
    script.onload = () => resolve(window.google);
    script.onerror = () => reject(new Error("Failed to load Google Identity Services."));

    if (!existing) {
      document.head.appendChild(script);
    }
  });

  return googleScriptPromise;
};

const ensureGoogleInitialized = (clientId) => {
  if (!window.google?.accounts?.id) {
    throw new Error("Google Identity Services is unavailable in this browser.");
  }

  if (initializedGoogleClientId === clientId) {
    return;
  }

  window.google.accounts.id.initialize({
    client_id: clientId,
    callback: (response) => {
      const credential = response?.credential;

      if (credential && googleCredentialHandler) {
        googleCredentialHandler(credential)();
        return;
      }

      if (googleErrorHandler) {
        googleErrorHandler("Google sign-in did not return a credential.")();
      }
    },
    auto_select: false,
    cancel_on_tap_outside: true,
    context: "signin",
    ux_mode: "popup",
    use_fedcm_for_button: false,
    button_auto_select: false,
  });

  initializedGoogleClientId = clientId;
};

export const createBrowser = () => {
  const root = ensureRoot();

  return {
    render: (html) => () => {
      root.innerHTML = html;
    },
    subscribe: (handler) => () => {
      const clickListener = (event) => {
        const target = event.target instanceof Element ? event.target.closest("[data-action]") : null;

        if (!target) {
          return;
        }

        event.preventDefault();
        handler(target.getAttribute("data-action") || "")(target.getAttribute("data-value") || "")();
      };

      const submitListener = (event) => {
        const form = event.target instanceof HTMLFormElement ? event.target : null;

        if (!form || !form.hasAttribute("data-submit")) {
          return;
        }

        event.preventDefault();
        const input = form.querySelector("[name='answerText']");
        const value = input instanceof HTMLInputElement ? input.value : "";
        handler(form.getAttribute("data-submit") || "")(value)();
      };

      root.addEventListener("click", clickListener);
      root.addEventListener("submit", submitListener);

      return () => {
        root.removeEventListener("click", clickListener);
        root.removeEventListener("submit", submitListener);
      };
    },
    mountGoogleSignIn: (clientId) => (onCredential) => (onError) => () => {
      const container = document.getElementById("google-signin-button");

      if (!container) {
        return;
      }

      googleCredentialHandler = onCredential;
      googleErrorHandler = onError;
      container.innerHTML = "";

      loadGoogleIdentityServices()
        .then(() => {
          ensureGoogleInitialized(clientId);
          const buttonWidth = Math.min(
            360,
            Math.max(240, Math.floor(container.getBoundingClientRect().width || 320)),
          );
          container.innerHTML = "";
          window.google.accounts.id.renderButton(container, {
            theme: "filled_blue",
            size: "large",
            shape: "pill",
            text: "signin_with",
            width: buttonWidth,
          });
        })
        .catch((error) => {
          onError(error instanceof Error ? error.message : String(error))();
        });
    },
    disableGoogleAutoSelect: () => {
      if (window.google?.accounts?.id?.disableAutoSelect) {
        window.google.accounts.id.disableAutoSelect();
      }
    },
  };
};
