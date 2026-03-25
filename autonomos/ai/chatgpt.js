import OpenAI from "openai";

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

export async function askAI(input) {
  const response = await client.responses.create({
    model: process.env.OPENAI_MODEL || "gpt-5.3",
    input,
  });

  return response.output_text || "";
}

