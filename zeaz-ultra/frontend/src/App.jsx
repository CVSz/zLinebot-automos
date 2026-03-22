import { useState } from "react";
import axios from "axios";

export default function App() {
  const [msg, setMsg] = useState("");
  const [res, setRes] = useState("");

  const send = async () => {
    const r = await axios.post(
      "/api/chat",
      { message: msg },
      {
        headers: { Authorization: "Bearer " + localStorage.token },
      }
    );
    setRes(r.data.reply);
  };

  return (
    <div className="p-10">
      <input
        onChange={(e) => setMsg(e.target.value)}
        className="border p-2"
      />
      <button onClick={send} className="ml-2 bg-blue-500 text-white p-2">
        Send
      </button>
      <div className="mt-4">{res}</div>
    </div>
  );
}
