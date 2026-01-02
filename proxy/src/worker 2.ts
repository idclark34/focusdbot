export interface Env {
  OPENAI_API_KEY: string;
  CLIENT_SECRET?: string; // optional shared secret
  SUMMARIES: KVNamespace; // KV namespace for job state
}

type SummaryJob = {
  id: string;
  status: "queued" | "running" | "done" | "error";
  createdAt: string;
  updatedAt: string;
  summary?: string;
  error?: string;
};

type Payload = {
  sessionId: number;
  startedAt: string;
  endedAt: string;
  durationMin: number;
  events: { t: string; kind: string; title: string; detail?: string | null }[];
  apps: { bundleId: string; seconds: number }[];
};

function json(data: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(data), {
    headers: { "content-type": "application/json", ...init.headers },
    ...init,
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    // Simple auth
    if (env.CLIENT_SECRET) {
      const secretHeader = request.headers.get("x-client-secret");
      if (secretHeader !== env.CLIENT_SECRET) {
        return json({ error: "unauthorized" }, { status: 401 });
      }
    }

    if (request.method === "POST" && pathname === "/v1/summary") {
      let payload: Payload;
      try {
        payload = (await request.json()) as Payload;
      } catch {
        return json({ error: "invalid_json" }, { status: 400 });
      }

      const id = crypto.randomUUID();
      const now = new Date().toISOString();
      const job: SummaryJob = { id, status: "running", createdAt: now, updatedAt: now };
      await env.SUMMARIES.put(`job:${id}`, JSON.stringify(job), { expirationTtl: 60 * 60 * 24 * 30 });

      // Run async
      ctx.waitUntil(runOpenAIJob(id, payload, env));
      return json({ jobId: id }, { status: 202 });
    }

    if (request.method === "GET" && pathname.startsWith("/v1/summary/")) {
      const id = pathname.split("/").pop() as string;
      const raw = await env.SUMMARIES.get(`job:${id}`);
      if (!raw) return json({ error: "not_found" }, { status: 404 });
      return new Response(raw, { headers: { "content-type": "application/json" } });
    }

    return json({ error: "not_found" }, { status: 404 });
  },
};

async function runOpenAIJob(id: string, payload: Payload, env: Env) {
  const update = async (patch: Partial<SummaryJob>) => {
    const currentRaw = await env.SUMMARIES.get(`job:${id}`);
    const current = currentRaw ? (JSON.parse(currentRaw) as SummaryJob) : ({ id } as SummaryJob);
    const next: SummaryJob = {
      ...current,
      ...patch,
      id,
      updatedAt: new Date().toISOString(),
    };
    await env.SUMMARIES.put(`job:${id}`, JSON.stringify(next), { expirationTtl: 60 * 60 * 24 * 30 });
  };

  try {
    // Build a compact prompt
    const lines: string[] = [];
    lines.push(`Session ${payload.sessionId} from ${payload.startedAt} to ${payload.endedAt} (planned ${payload.durationMin}m).`);
    if (payload.apps.length) {
      const top = payload.apps
        .slice(0, 8)
        .map((a) => `${a.bundleId}:${Math.round(a.seconds / 60)}m`)
        .join(", ");
      lines.push(`Top apps: ${top}.`);
    }
    if (payload.events.length) {
      const evs = payload.events
        .slice(0, 50)
        .map((e) => `${e.kind}:${e.title}${e.detail ? ` (${e.detail})` : ""}`)
        .join(" | ");
      lines.push(`Events: ${evs}`);
    }

    const prompt = `Summarize the user's focus session in 3-5 sentences. Include what they worked on, notable media played, and likely distractions. Be concise and helpful.\n\nContext:\n${lines.join("\n")}`;

    const body = {
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: "You are a succinct productivity session summarizer." },
        { role: "user", content: prompt },
      ],
      temperature: 0.4,
      max_tokens: 300,
    };

    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const err = await res.text();
      await update({ status: "error", error: `openai_failed:${res.status} ${err}` });
      return;
    }
    const data = (await res.json()) as any;
    const text: string | undefined = data?.choices?.[0]?.message?.content;
    if (!text) {
      await update({ status: "error", error: "no_content" });
      return;
    }
    await update({ status: "done", summary: text });
  } catch (e: any) {
    await update({ status: "error", error: String(e?.message ?? e) });
  }
}


