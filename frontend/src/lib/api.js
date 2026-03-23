const jsonHeaders = {
  "Content-Type": "application/json"
};

async function apiPost(path, payload) {
  const response = await fetch(path, {
    method: "POST",
    headers: jsonHeaders,
    body: JSON.stringify(payload)
  });

  const data = await response.json();

  if (!response.ok) {
    const message = data?.detail || `Request failed (${response.status})`;
    throw new Error(message);
  }

  return data;
}

export function postRegister(payload) {
  return apiPost("/api/register", payload);
}

export function postLogin(payload) {
  return apiPost("/api/login", payload);
}

export function postChat(payload) {
  return apiPost("/api/chat", payload);
}
