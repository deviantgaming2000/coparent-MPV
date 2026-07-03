import {
  AIProvider,
  normalizeAIResponse,
  normalizeFinalDocumentationResponse,
  parseJSONContent
} from "./AIProvider.js";
import { finalDocumentationPrompt, systemPrompt } from "./ProviderPrompts.js";

export class OpenAIProvider extends AIProvider {
  constructor({
    apiKey = process.env.OPENAI_API_KEY,
    baseURL = process.env.OPENAI_BASE_URL ?? "https://api.openai.com/v1",
    model = process.env.OPENAI_MODEL ?? "gpt-5.5"
  } = {}) {
    super();
    this.apiKey = apiKey;
    this.baseURL = baseURL.replace(/\/$/, "");
    this.model = model;
  }

  async generateIncidentSummary(request) {
    if (!this.apiKey) {
      throw new Error("OPENAI_API_KEY is not configured");
    }

    const response = await fetch(`${this.baseURL}/responses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        instructions: systemPrompt(),
        input: [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: JSON.stringify(request)
              }
            ]
          }
        ]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`OpenAI request failed with ${response.status}: ${errorBody}`);
    }

    const body = await response.json();
    const content = extractOutputText(body);

    if (!content) {
      throw new Error("OpenAI response did not include text output");
    }

    return normalizeAIResponse(parseJSONContent(content));
  }

  async generateFinalDocumentationSummary(request) {
    if (!this.apiKey) {
      throw new Error("OPENAI_API_KEY is not configured");
    }

    const response = await fetch(`${this.baseURL}/responses`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: this.model,
        instructions: finalDocumentationPrompt(),
        input: [
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text: JSON.stringify(request)
              }
            ]
          }
        ]
      })
    });

    if (!response.ok) {
      const errorBody = await response.text();
      throw new Error(`OpenAI final documentation request failed with ${response.status}: ${errorBody}`);
    }

    const body = await response.json();
    const content = extractOutputText(body);

    if (!content) {
      throw new Error("OpenAI final documentation response did not include text output");
    }

    return normalizeFinalDocumentationResponse(parseJSONContent(content), request);
  }
}

function extractOutputText(body) {
  if (typeof body?.output_text === "string") {
    return body.output_text;
  }

  const output = Array.isArray(body?.output) ? body.output : [];
  const textParts = [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];

    for (const part of content) {
      if (typeof part?.text === "string") {
        textParts.push(part.text);
      }
    }
  }

  return textParts.join("\n").trim();
}
