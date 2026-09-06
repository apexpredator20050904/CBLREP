import { AUTH_APIS } from "./community";

export async function postToAuthApis(path, body) {
  let lastError = new Error("Unable to reach the CBLREP server.");

  for (const base of AUTH_APIS) {
    try {
      const response = await fetch(`${base}${path}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify(body),
      });

      const result = await response.json().catch(() => ({}));
      if (!response.ok) {
        lastError = new Error(result.message || "Request failed.");
        if (response.status >= 400 && response.status < 500) {
          throw lastError;
        }
        continue;
      }
      return result;
    } catch (err) {
      lastError = err;
      if (err instanceof TypeError) continue;
      throw err;
    }
  }

  throw lastError;
}
