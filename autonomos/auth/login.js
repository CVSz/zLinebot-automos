import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import { query } from "../db.js";

export async function login(req, res, next) {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) return res.status(400).json({ error: "email_and_password_required" });

    const found = await query("SELECT id, email, password, role FROM users WHERE email=$1", [email]);
    if (!found.rows.length) return res.status(401).json({ error: "invalid_credentials" });

    const user = found.rows[0];
    const valid = await bcrypt.compare(password, user.password);
    if (!valid) return res.status(401).json({ error: "invalid_credentials" });

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || "1h" },
    );

    return res.json({ token });
  } catch (error) {
    return next(error);
  }
}
