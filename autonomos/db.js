import pg from "pg";

const { Pool } = pg;

let pool;

function getPool() {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      throw new Error("DATABASE_URL is required");
    }

    pool = new Pool({ connectionString });
  }

  return pool;
}

export async function query(text, params = []) {
  const client = getPool();
  return client.query(text, params);
}

export async function closeDb() {
  if (pool) await pool.end();
}
