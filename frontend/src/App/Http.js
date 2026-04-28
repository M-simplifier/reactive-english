export const requestJsonImpl = (method) => (url) => (body) => (onSuccess) => (onError) => () => {
  const headers = { Accept: "application/json" };
  const options = { method, headers, credentials: "same-origin" };

  if (body !== "") {
    headers["Content-Type"] = "application/json";
    options.body = body;
  }

  fetch(url, options)
    .then(async (response) => {
      const text = await response.text();

      if (!response.ok) {
        const detail = text === "" ? response.statusText : text;
        throw new Error(`${response.status} ${detail}`.trim());
      }

      return text;
    })
    .then((text) => {
      onSuccess(text)();
    })
    .catch((error) => {
      onError(error instanceof Error ? error.message : String(error))();
    });
};
