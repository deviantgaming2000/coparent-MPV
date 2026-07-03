import {
  AIProvider,
  documentationDisclaimer,
  normalizeAIResponse,
  normalizeFinalDocumentationResponse
} from "./AIProvider.js";

export class MockAIProvider extends AIProvider {
  async generateIncidentSummary(request) {
    const combinedText = [
      request.incidentText,
      request.peopleInvolved,
      request.location,
      request.evidenceNotes,
      ...(request.existingFollowUpAnswers ?? []).map((answer) => `${answer.question} ${answer.answer}`)
    ].join(" ");
    const suggestedCategory = suggestCategory(combinedText, request.currentCategory);
    const patternTags = suggestPatternTags(combinedText, suggestedCategory, request.evidenceNotes);

    return normalizeAIResponse({
      understandingSummary: [
        `This appears to be a ${suggestedCategory}-related incident.`,
        "The notes were reviewed for timing, people, location, child impact, evidence, and pattern context.",
        ...(patternTags.includes("evidence_available") ? ["Evidence or records were mentioned."] : []),
        ...(patternTags.some((tag) => tag.includes("exchange")) ? ["The notes may include exchange timing or recurrence details."] : [])
      ],
      suggestedCategory,
      categoryReason: `${suggestedCategory} was suggested based on the main details and keywords in the incident notes.`,
      neutralSummary: [
        `Category: ${suggestedCategory}`,
        `People Involved: ${displayValue(request.peopleInvolved)}`,
        `Location: ${displayValue(request.location)}`,
        `Summary: ${displayValue(request.incidentText)}`,
        `Evidence Mentioned: ${displayValue(request.evidenceNotes)}`,
        `Child Involved: ${request.childInvolved ? "Yes" : "No"}`,
        `Disclaimer: ${documentationDisclaimer}`
      ].join("\n"),
      followUpQuestions: contextualQuestions(combinedText, suggestedCategory),
      missingInformation: missingFields(request),
      evidenceMentioned: evidenceMentioned(combinedText, request),
      patternTags,
      disclaimer: documentationDisclaimer
    });
  }

  async generateFinalDocumentationSummary(request) {
    const answeredFollowUps = (request.followUpAnswers ?? [])
      .filter((answer) => answer.answer?.trim())
      .map((answer) => answer.answer.trim());
    const paragraphs = [];
    const dateText = request.incidentDate
      ? new Date(request.incidentDate).toLocaleString("en-US", { dateStyle: "medium", timeStyle: "short" })
      : "the documented date";

    paragraphs.push(`On ${dateText}, the reporting parent documented a ${request.category || "parenting"} incident.`);

    if (request.originalNotes?.trim()) {
      paragraphs.push(`The original notes state: ${request.originalNotes.trim()}`);
    }

    if (answeredFollowUps.length > 0) {
      paragraphs.push(`Additional context gathered through follow-up questions includes: ${answeredFollowUps.join(" ")}`);
    }

    if (request.evidenceNotes?.trim()) {
      paragraphs.push(`Supporting evidence referenced includes ${request.evidenceNotes.trim()}.`);
    }

    if ((request.patternTags ?? []).length > 0) {
      paragraphs.push(`Possible organization tags include ${(request.patternTags ?? []).join(", ")}.`);
    }

    return normalizeFinalDocumentationResponse({ summary: paragraphs.join("\n\n") }, request);
  }
}

function suggestCategory(text, currentCategory) {
  const lower = text.toLowerCase();

  if (lower.includes("school") || lower.includes("teacher") || lower.includes("attendance")) return "School";
  if (lower.includes("doctor") || lower.includes("medical") || lower.includes("appointment") || lower.includes("medicine")) return "Medical";
  if (lower.includes("paid") || lower.includes("payment") || lower.includes("receipt") || lower.includes("expense")) return "Financial";
  if (lower.includes("late") || lower.includes("exchange") || lower.includes("pickup") || lower.includes("drop off")) return "Exchange";
  if (lower.includes("text") || lower.includes("call") || lower.includes("email") || lower.includes("message")) return "Communication";
  if (lower.includes("schedule") || lower.includes("time") || lower.includes("date")) return "Schedule";
  if (lower.includes("safe") || lower.includes("danger") || lower.includes("injury") || lower.includes("threat")) return "Safety";
  if (lower.includes("child") || lower.includes("upset") || lower.includes("wellbeing")) return "Child Wellbeing";

  return currentCategory || "Other";
}

function questionsForCategory(category) {
  const questions = {
    Exchange: [
      "What was the agreed exchange time and location?",
      "What time did each person arrive or leave?",
      "Who was present during the exchange?",
      "Were there any messages or records related to the exchange?"
    ],
    Communication: [
      "What communication method was used?",
      "What was the main topic of the communication?",
      "When did the communication occur?",
      "Is there a record of the communication?"
    ],
    School: [
      "What school-related event or record is involved?",
      "Who from the school was involved or notified?",
      "What date or school period does this relate to?",
      "Are there emails, forms, attendance records, or other school records?"
    ],
    Medical: [
      "What medical appointment, concern, or record is involved?",
      "Who provided or received the medical information?",
      "What date did the appointment or communication occur?",
      "Are there visit notes, messages, prescriptions, or medical records?"
    ],
    Schedule: [
      "What was the agreed schedule or expectation?",
      "What date and time did the schedule issue occur?",
      "How was the schedule discussed or confirmed?",
      "Were any alternatives proposed or documented?"
    ],
    Financial: [
      "What expense, payment, or financial record is involved?",
      "What amount or document is relevant, if known?",
      "When was the expense or communication created?",
      "Are there receipts, invoices, statements, or messages?"
    ],
    Safety: [
      "What happened that raised a safety concern?",
      "Who was present or directly involved?",
      "Was anyone injured or in immediate danger?",
      "Are there photos, messages, reports, or witness notes?"
    ],
    "Child Wellbeing": [
      "What did you observe about the child's wellbeing?",
      "When and where did you observe it?",
      "Did the child say anything relevant in their own words?",
      "Were any caregivers, teachers, or professionals notified?"
    ],
    Other: [
      "What happened in neutral, factual terms?",
      "When and where did it occur?",
      "Who was involved or present?",
      "What records or evidence may help document it?"
    ]
  };

  return questions[category] ?? questions.Other;
}

function contextualQuestions(text, category) {
  const lower = text.toLowerCase();
  const questions = [];

  if (lower.includes("scheduled") || lower.includes("supposed to") || lower.includes("agreed") || lower.includes("time")) {
    questions.push({
      priority: "High",
      question: "You mentioned an expected or scheduled time. What was the agreed time for this event?",
      whyItMatters: "This helps document the planned timing before comparing it with what occurred."
    });
  }

  if (lower.includes("late") || lower.includes("arrived") || lower.includes("delay") || lower.includes("traffic")) {
    questions.push({
      priority: "High",
      question: "Approximately what time did each person actually arrive or respond?",
      whyItMatters: "This helps accurately document the timeline of the event."
    });
  }

  if (lower.includes("child") || lower.includes("upset") || lower.includes("waiting")) {
    questions.push({
      priority: "High",
      question: "You mentioned your child or an observable reaction. What did you personally observe?",
      whyItMatters: "This keeps the record focused on direct observations rather than conclusions."
    });
  }

  if (lower.includes("happened before") || lower.includes("again") || lower.includes("always") || lower.includes("multiple times") || lower.includes("few times")) {
    questions.push({
      priority: "Helpful Context",
      question: "You mentioned this may have happened before. About how many previous occurrences do you remember?",
      whyItMatters: "This helps separate a one-time event from possible recurring context without needing exact dates yet."
    });
  }

  if (lower.includes("text") || lower.includes("message") || lower.includes("screenshot") || lower.includes("email")) {
    questions.push({
      priority: "Helpful Context",
      question: "You mentioned records such as messages, screenshots, or emails. Would you like to attach them or note where they are saved?",
      whyItMatters: "This helps preserve the connection between the written summary and the original records."
    });
  }

  if (questions.length === 0) {
    return questionsForCategory(category).map((question) => ({
      priority: "Helpful Context",
      question,
      whyItMatters: "This may help make the documentation more complete and specific."
    }));
  }

  return questions.slice(0, 6);
}

function suggestPatternTags(text, category, evidenceNotes) {
  const lower = text.toLowerCase();
  const tags = new Set();

  if (category === "Communication") tags.add("communication_issue");
  if (category === "School") tags.add("school_issue");
  if (category === "Medical") tags.add("medical_issue");
  if (category === "Schedule") tags.add("schedule_issue");
  if (category === "Financial") tags.add("financial_issue");
  if (category === "Safety") tags.add("safety_concern");
  if (category === "Child Wellbeing") tags.add("child_wellbeing");
  if (lower.includes("late")) tags.add("late_exchange");
  if (lower.includes("missed") || lower.includes("no show") || lower.includes("did not arrive")) tags.add("missed_exchange");
  if (lower.includes("early")) tags.add("early_return");
  if (evidenceNotes?.trim()) tags.add("evidence_available");

  return [...tags];
}

function evidenceMentioned(text, request) {
  const lower = text.toLowerCase();
  const evidence = new Set();

  if (lower.includes("text") || lower.includes("message")) evidence.add("text messages");
  if (lower.includes("screenshot")) evidence.add("screenshots");
  if (lower.includes("email")) evidence.add("emails");
  if (lower.includes("photo")) evidence.add("photos");
  if (lower.includes("call log")) evidence.add("call logs");
  if (request.evidenceNotes?.trim()) evidence.add("evidence notes");

  return [...evidence].sort();
}

function missingFields(request) {
  const fields = [];

  if (!request.incidentText?.trim()) fields.push("What happened");
  if (!request.peopleInvolved?.trim()) fields.push("People involved");
  if (!request.location?.trim()) fields.push("Location");
  if (!request.evidenceNotes?.trim()) fields.push("Evidence or records");
  if (!request.existingFollowUpAnswers?.some((answer) => answer.answer?.trim())) {
    fields.push("Clarifying question answers");
  }

  return fields;
}

function displayValue(value) {
  return value?.trim() || "Not specified";
}
