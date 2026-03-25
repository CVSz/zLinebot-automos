const ALLOWED_DOCS = new Set(["passport", "id_card", "drivers_license", "proof_of_address"]);

export function submitKYC(user, docs = []) {
  const normalizedDocs = docs
    .map((doc) => String(doc || "").toLowerCase().trim())
    .filter((doc) => ALLOWED_DOCS.has(doc));

  const missingDocs = ["passport", "proof_of_address"].filter((required) => !normalizedDocs.includes(required));

  return {
    status: missingDocs.length ? "pending_missing_documents" : "pending_review",
    user,
    docs: normalizedDocs,
    missingDocs,
    submittedAt: new Date().toISOString(),
  };
}

export function logAction(user, action, metadata = {}) {
  const record = {
    ts: new Date().toISOString(),
    user,
    action,
    metadata,
  };

  console.log(`[AUDIT] ${JSON.stringify(record)}`);
  return record;
}
