export class AIProvider {
  async generateIncidentSummary(_request) {
    throw new Error("AIProvider.generateIncidentSummary must be implemented");
  }

  async generateFinalDocumentationSummary(_request) {
    throw new Error("AIProvider.generateFinalDocumentationSummary must be implemented");
  }
}

export const allowedCategories = [
  "Exchange",
  "Communication",
  "School",
  "Medical",
  "Schedule",
  "Financial",
  "Safety",
  "Child Wellbeing",
  "Other"
];

export const allowedPatternTags = [
  "late_exchange",
  "missed_exchange",
  "early_return",
  "communication_issue",
  "school_issue",
  "medical_issue",
  "schedule_issue",
  "financial_issue",
  "safety_concern",
  "child_wellbeing",
  "evidence_available"
];

export const documentationDisclaimer =
  "This is not legal advice. This is only for documentation and organization.";

export function normalizeAIResponse(value) {
  const suggestedCategory = allowedCategories.includes(value?.suggestedCategory)
    ? value.suggestedCategory
    : "Other";

  return {
    understandingSummary: stringArray(value?.understandingSummary),
    suggestedCategory,
    categoryReason: stringValue(value?.categoryReason || value?.categoryRationale),
    neutralSummary: stringValue(value?.neutralSummary),
    followUpQuestions: questionArray(value?.followUpQuestions).slice(0, 6),
    missingInformation: stringArray(value?.missingInformation || value?.missingInformationFields),
    evidenceMentioned: stringArray(value?.evidenceMentioned),
    patternTags: stringArray(value?.patternTags).filter((tag) => allowedPatternTags.includes(tag)),
    disclaimer: documentationDisclaimer
  };
}

export function normalizeFinalDocumentationResponse(value, fallbackRequest) {
  const summary = stringValue(value?.summary) || fallbackFinalSummary(fallbackRequest);

  return {
    summary,
    completeness: calculateCompleteness(fallbackRequest, summary)
  };
}

export function parseJSONContent(content) {
  const trimmed = stringValue(content);

  if (!trimmed) {
    throw new Error("AI response was empty");
  }

  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const jsonText = fencedMatch ? fencedMatch[1].trim() : trimmed;

  return JSON.parse(jsonText);
}

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function stringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function questionArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (typeof item === "string") {
        return {
          priority: "Helpful Context",
          question: item.trim(),
          whyItMatters: "This may help make the documentation more complete and specific."
        };
      }

      return {
        priority: stringValue(item?.priority) || "Helpful Context",
        question: stringValue(item?.question),
        whyItMatters: stringValue(item?.whyItMatters) || "This may help make the documentation more complete and specific."
      };
    })
    .filter((item) => item.question);
}

function calculateCompleteness(request, summary) {
  const completedItems = [];
  const missingItems = [];
  const followUpAnswers = Array.isArray(request?.followUpAnswers) ? request.followUpAnswers : [];
  const evidenceTypes = Array.isArray(request?.evidenceTypes) ? request.evidenceTypes : [];
  const patternTags = Array.isArray(request?.patternTags) ? request.patternTags : [];

  addCompletenessItem(hasValue(request?.originalNotes), "Original notes", completedItems, missingItems);
  addCompletenessItem(hasValue(request?.incidentDate), "Date", completedItems, missingItems);
  addCompletenessItem(hasSpecificTime(request), "Specific time", completedItems, missingItems);
  addCompletenessItem(hasValue(request?.category), "Category", completedItems, missingItems);
  addCompletenessItem(hasValue(summary), "Chronological final summary", completedItems, missingItems);
  addCompletenessItem(hasEvidence(request, evidenceTypes), "Evidence referenced", completedItems, missingItems);
  addCompletenessItem(Boolean(request?.childInvolved) || mentionsChild(request), "Child observations, if applicable", completedItems, missingItems);
  addCompletenessItem(followUpAnswers.some((answer) => hasValue(answer?.answer)), "Follow-up responses", completedItems, missingItems);
  addCompletenessItem(hasValue(request?.peopleInvolved) || textBlob(request).includes("parent"), "People involved", completedItems, missingItems);
  addCompletenessItem(hasValue(request?.location) || textBlob(request).includes(" at "), "Location", completedItems, missingItems);
  addCompletenessItem(patternTags.length > 0, "Pattern tags", completedItems, missingItems);

  const total = completedItems.length + missingItems.length;
  const score = total === 0 ? 0 : Math.round((completedItems.length / total) * 100);

  return {
    score: Math.max(0, Math.min(100, score)),
    completedItems,
    missingItems
  };
}

function addCompletenessItem(condition, label, completedItems, missingItems) {
  if (condition) {
    completedItems.push(label);
  } else {
    missingItems.push(label);
  }
}

function hasValue(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function hasSpecificTime(request) {
  const text = textBlob(request);
  return /\b\d{1,2}:\d{2}\b/.test(text) || /\b(?:am|pm)\b/.test(text);
}

function hasEvidence(request, evidenceTypes) {
  const text = textBlob(request);
  return hasValue(request?.evidenceNotes)
    || evidenceTypes.length > 0
    || text.includes("text")
    || text.includes("screenshot")
    || text.includes("email")
    || text.includes("photo")
    || text.includes("record")
    || text.includes("call log");
}

function mentionsChild(request) {
  const text = textBlob(request);
  return text.includes("child") || text.includes("son") || text.includes("daughter") || text.includes("kid");
}

function textBlob(request) {
  return [
    request?.originalNotes,
    request?.peopleInvolved,
    request?.location,
    request?.evidenceNotes,
    ...(Array.isArray(request?.followUpAnswers) ? request.followUpAnswers.map((answer) => answer?.answer) : [])
  ]
    .filter((value) => typeof value === "string")
    .join(" ")
    .toLowerCase();
}

function fallbackFinalSummary(request) {
  const parts = [];

  if (hasValue(request?.incidentDate)) {
    parts.push(`On ${request.incidentDate}, the reporting parent documented a ${request?.category || "parenting"} incident.`);
  } else {
    parts.push(`The reporting parent documented a ${request?.category || "parenting"} incident.`);
  }

  if (hasValue(request?.originalNotes)) {
    parts.push(request.originalNotes.trim());
  }

  const answered = Array.isArray(request?.followUpAnswers)
    ? request.followUpAnswers.filter((answer) => hasValue(answer?.answer))
    : [];

  if (answered.length > 0) {
    parts.push(`Additional context provided through follow-up questions: ${answered.map((answer) => answer.answer.trim()).join(" ")}`);
  }

  if (hasValue(request?.evidenceNotes)) {
    parts.push(`Supporting evidence referenced: ${request.evidenceNotes.trim()}.`);
  }

  return parts.join("\n\n");
}
