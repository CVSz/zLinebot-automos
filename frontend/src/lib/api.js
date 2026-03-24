const jsonHeaders = {
  "Content-Type": "application/json"
};

const REQUEST_TIMEOUT_MS = 15000;

function tenantHeader(tenantId) {
  return tenantId ? { "X-Tenant-Id": tenantId } : {};
}

async function parseResponse(response) {
  const text = await response.text();
  let data = {};

  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { detail: text };
    }
  }

  if (!response.ok) {
    const message = data?.detail || response.statusText || `Request failed (${response.status})`;
    throw new Error(message);
  }

  return data;
}

async function apiRequest(path, options = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(path, {
      ...options,
      signal: controller.signal
    });

    return parseResponse(response);
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error("Request timed out. Please try again.");
    }

    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function apiPost(path, payload, options = {}) {
  return apiRequest(path, {
    method: "POST",
    headers: {
      ...jsonHeaders,
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...tenantHeader(options.tenantId)
    },
    body: JSON.stringify(payload)
  });
}

async function apiGet(path, options = {}) {
  return apiRequest(path, {
    headers: {
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...tenantHeader(options.tenantId)
    }
  });
}

async function apiPatch(path, payload, options = {}) {
  return apiRequest(path, {
    method: "PATCH",
    headers: {
      ...jsonHeaders,
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...tenantHeader(options.tenantId)
    },
    body: JSON.stringify(payload)
  });
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

export function getMe(token) {
  return apiGet("/api/me", { token });
}

export function getStats(token, tenantId) {
  return apiGet("/api/stats", { token, tenantId });
}

export function getLeads(token, tenantId, status = "") {
  const suffix = status ? `?status=${encodeURIComponent(status)}` : "";
  return apiGet(`/api/leads${suffix}`, { token, tenantId });
}

export function patchLead(token, tenantId, leadId, payload) {
  return apiPatch(`/api/leads/${leadId}`, payload, { token, tenantId });
}

export function getRevenueDaily(token, tenantId) {
  return apiGet("/api/revenue/daily", { token, tenantId });
}

export function getTemplates(token, tenantId) {
  return apiGet("/api/templates", { token, tenantId });
}

export function createTemplate(token, tenantId, payload) {
  return apiPost("/api/templates", payload, { token, tenantId });
}

export function getCampaigns(token, tenantId) {
  return apiGet("/api/campaigns", { token, tenantId });
}

export function createBroadcast(token, tenantId, payload) {
  return apiPost("/api/broadcast", payload, { token, tenantId });
}

export function createCheckout(token, payload) {
  return apiPost("/api/billing/checkout", payload, { token });
}
