import bcrypt from "bcrypt";
import { query } from "../db.js";

export async function register(req, res, next) {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: "email_and_password_required" });

    const hash = await bcrypt.hash(password, 10);
    const created = await query(
      "INSERT INTO users(email, password) VALUES($1,$2) RETURNING id, email, role, balance",
      [email, hash],
    );

    return res.status(201).json(created.rows[0]);
  } catch (error) {
    if (String(error.message).includes("duplicate") || error.code === "23505") {
      return res.status(409).json({ error: "email_exists" });
    }

    return next(error);
  }
}
