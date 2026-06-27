import { betaZodTool } from "@anthropic-ai/sdk/helpers/beta/zod";
import { z } from "zod";
import type { RunContext } from "./types.ts";

/**
 * The agent's tool surface. These are mocks today, but each is shaped exactly
 * like its production counterpart (Twilio, a flights API, a calendar API), so
 * swapping in a real implementation is a one-function change.
 *
 * Every tool records what it did into ctx.actions so the result can be returned
 * to the phone and written to episodic memory.
 */
export function makeTools(ctx: RunContext) {
  const log = (tool: string, detail: string, result: unknown) => {
    ctx.actions.push({ tool, detail, result });
    return result;
  };

  const getContacts = betaZodTool({
    name: "get_contacts",
    description:
      "Resolve a person's alias or name to a contact. Use before sending any message. " +
      "Returns the contact's full name and phone, or not_found.",
    inputSchema: z.object({
      who: z.string().describe("Alias or name as the user said it, e.g. 'g' or 'Greg'."),
    }),
    run: async ({ who }) => {
      const key = who.toLowerCase();
      const byAlias = ctx.profile.contacts[key];
      const byName = Object.values(ctx.profile.contacts).find(
        (c) => c.name.toLowerCase() === key,
      );
      const contact = byAlias ?? byName ?? null;
      return JSON.stringify(log("get_contacts", `who=${who}`, contact ?? { not_found: who }));
    },
  });

  const getCalendar = betaZodTool({
    name: "get_calendar",
    description:
      "Look up the user's upcoming calendar events, optionally filtered by who is attending. " +
      "Use this to ground references like 'our meeting' to a real time.",
    inputSchema: z.object({
      attendee: z
        .string()
        .optional()
        .describe("Filter to events including this person, e.g. 'Greg'. Omit for all events."),
    }),
    run: async ({ attendee }) => {
      const events = ctx.profile.calendar.filter(
        (e) => !attendee || (e.with ?? []).some((p) => p.toLowerCase() === attendee.toLowerCase()),
      );
      return JSON.stringify(log("get_calendar", `attendee=${attendee ?? "*"}`, events));
    },
  });

  const draftMessage = betaZodTool({
    name: "draft_message",
    description:
      "Draft a text message for the user to review and send from their phone. " +
      "iOS presents the native Messages sheet pre-filled — you do NOT send it yourself. " +
      "Resolve the recipient's name and phone first.",
    inputSchema: z.object({
      toPhone: z.string().describe("E.164 phone number, e.g. +15551234567."),
      toName: z.string().describe("Display name."),
      body: z.string().describe("The exact message text to pre-fill."),
    }),
    run: async ({ toPhone, toName, body }) => {
      const draft = { toName, toPhone, body };
      log("draft_message", `to=${toName}`, draft);
      return JSON.stringify({
        drafted: true,
        ...draft,
        note: "Pre-filled in the user's Messages app; they tap Send.",
      });
    },
  });

  const searchTravel = betaZodTool({
    name: "search_travel",
    description:
      "Search round-trip itineraries (flights + hotel). Returns options sorted by total price. " +
      "Use the user's home airport as the origin unless told otherwise.",
    inputSchema: z.object({
      origin: z.string().describe("Origin airport code, e.g. JFK."),
      destination: z.string().describe("Destination city or region, e.g. 'Florida' or 'MIA'."),
      timeframe: z.string().describe("When, in the user's words, e.g. 'this weekend'."),
      optimizeFor: z.enum(["price", "time"]).describe("What to optimize. Usually 'price'."),
    }),
    run: async ({ origin, destination, timeframe, optimizeFor }) => {
      // PRODUCTION: call a flights+hotels aggregator API here.
      const options = [
        { airline: "Spirit", hotel: "Budget Inn", nights: 2, totalUSD: 248, note: "red-eye out" },
        { airline: "JetBlue", hotel: "Comfort Suites", nights: 2, totalUSD: 412, note: "daytime" },
        { airline: "Delta", hotel: "Marriott", nights: 2, totalUSD: 690, note: "nonstop" },
      ].sort((a, b) => (optimizeFor === "price" ? a.totalUSD - b.totalUSD : 0));
      const result = { origin, destination, timeframe, options };
      return JSON.stringify(log("search_travel", `${origin}->${destination}`, result));
    },
  });

  return [getContacts, getCalendar, draftMessage, searchTravel];
}
