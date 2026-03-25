import { Tick } from "./tick_engine";

export function loadTicksFromJson(raw: Array<{ price: number; volume: number; ts: number }>): Tick[] {
  return raw.map((item) => ({ ...item }));
}
