export interface SubscriptionEnv {
  SUBSCRIPTION_TOKEN_HASH?: string;
  SUBSCRIPTION_BODY?: string;
}

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const HASH_PATTERN = /^[0-9a-f]{64}$/;
const encoder = new TextEncoder();

const privateHeaders = Object.freeze({
  "Cache-Control": "private, no-store, max-age=0",
  "Content-Type": "text/plain; charset=utf-8",
  Expires: "0",
  Pragma: "no-cache",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
});

function textResponse(body: string | null, status: number, extra: HeadersInit = {}): Response {
  return new Response(body, {
    status,
    headers: { ...privateHeaders, ...extra },
  });
}

function fromHex(value: string): Uint8Array {
  const bytes = new Uint8Array(value.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(value.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

async function tokenMatches(token: string, expectedHash: string): Promise<boolean> {
  const actual = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(token)));
  const expected = fromHex(expectedHash);
  return crypto.subtle.timingSafeEqual(actual, expected);
}

export default {
  async fetch(request: Request, env: SubscriptionEnv): Promise<Response> {
    const url = new URL(request.url);
    const match = /^\/s\/([^/]+)$/.exec(url.pathname);
    if (!match || !TOKEN_PATTERN.test(match[1])) {
      return textResponse("Not Found\n", 404);
    }

    const expectedHash = env.SUBSCRIPTION_TOKEN_HASH ?? "";
    const body = env.SUBSCRIPTION_BODY ?? "";
    if (!HASH_PATTERN.test(expectedHash) || body.length === 0) {
      return textResponse("Service Unavailable\n", 503);
    }
    if (!(await tokenMatches(match[1], expectedHash))) {
      return textResponse("Not Found\n", 404);
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return textResponse("Method Not Allowed\n", 405, { Allow: "GET, HEAD" });
    }

    return textResponse(request.method === "HEAD" ? null : body, 200);
  },
} satisfies ExportedHandler<SubscriptionEnv>;
