// Mirrors the TaskSpec the iOS app emits (schema/taskspec.schema.json).
export interface TaskSpec {
  intent: "book_travel" | "send_message" | "reminder" | "search" | "unknown";
  summary: string;
  recipient?: string;
  messageBody?: string;
  destination?: string;
  timeframe?: string;
  needsClarification: boolean;
  clarifyingQuestion?: string;
  confidence: number;
}

// The full envelope POSTed by the phone (matches iOS EmittedTask).
export interface EmittedTask {
  spec: TaskSpec;
  resolvedPhone?: string | null;
  createdAt: string;
}

export interface Contact {
  name: string;
  phone: string;
}

export interface CalendarEvent {
  title: string;
  startsAt: string;
  with?: string[];
}

export interface UserProfile {
  displayName: string;
  homeAirport: string;
  budgetTier: string;
  contacts: Record<string, Contact>;
  calendar: CalendarEvent[];
  preferences: Record<string, unknown>;
}

// Everything a tool did during a run — returned to the phone and written to memory.
export interface Action {
  tool: string;
  detail: string;
  result: unknown;
}

export interface RunContext {
  profile: UserProfile;
  actions: Action[];
}

// A message the agent drafted for the user to send via the phone's native
// Messages sheet (iOS can't send SMS silently — and shouldn't).
export interface Compose {
  toName: string;
  toPhone: string;
  body: string;
}

export interface TaskResult {
  reply: string;
  actions: Action[];
  compose?: Compose;
}
