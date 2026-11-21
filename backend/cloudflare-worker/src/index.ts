/**
 * DriveTime AMap proxy
 *
 * Keeps the AMap Web Service Key on the server, validates requests, applies a
 * per-client rate limit, and returns only the AMap fields DriveTime needs.
 * Deploy on Cloudflare Workers. The iOS app never receives the AMap key.
 */

export interface Env {
  AMAP_KEY: string;
  PROXY_ACCESS_TOKEN?: string;
  DRIVETIME_KV?: KVNamespace;
  RATE_LIMIT_PER_MINUTE?: string;
}

const AMAP_BASE = "https://restapi.amap.com";
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 12_000;
const ALLOWED_STRATEGIES = new Set([32, 33, 34, 35, 36, 38]);
const DEFAULT_RATE_LIMIT = 20;

const memoryRateLimit = new Map<string, { count: number; window: number }>();

class ProxyError extends Error {
  readonly status: number;
  readonly code: string;
  readonly retryAfter?: number;

  constructor(status: number, code: string, message: string, retryAfter?: number) {
    super(message);
    this.name = "ProxyError";
    this.status = status;
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

type JsonRecord = Record<string, unknown>;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders(request, env) });
      }
      if (request.method !== "GET") {
        throw new ProxyError(405, "METHOD_NOT_ALLOWED", "Only GET is supported.");
      }

      const url = new URL(request.url);
      authenticate(request, env);
      await enforceRateLimit(request, env, url.pathname);

      if (url.pathname === "/v1/health") {
        return healthResponse(env, request);
      }
      if (url.pathname === "/v1/route/driving") {
        return await proxyDriving(url, env, request);
      }
      if (url.pathname === "/v1/places/text") {
        return await proxyPlaces(url, env, request);
      }
      throw new ProxyError(404, "NOT_FOUND", "Unknown endpoint.");
    } catch (error) {
      return errorResponse(error, request, env);
    }
  },
};

function healthResponse(env: Env, request: Request): Response {
  const configured = Boolean(env.AMAP_KEY?.trim());
  return jsonResponse(
    {
      ok: configured,
      configured,
      provider_reachable: false,
      message: configured
        ? "Proxy is reachable. AMap connectivity is verified when a route is requested."
        : "AMAP_KEY is not configured on this Worker.",
      service: "drivetime-amap-proxy",
    },
    200,
    request,
    env,
  );
}

async function proxyDriving(url: URL, env: Env, request: Request): Promise<Response> {
  const origin = parseCoordinateParam(url.searchParams.get("origin"), "origin");
  const destination = parseCoordinateParam(url.searchParams.get("destination"), "destination");
  const strategyText = url.searchParams.get("strategy") ?? "32";
  const strategy = Number(strategyText);
  if (!Number.isInteger(strategy) || !ALLOWED_STRATEGIES.has(strategy)) {
    throw new ProxyError(400, "BAD_REQUEST", "Unsupported driving strategy.");
  }
  const originId = optionalID(url.searchParams.get("origin_id"));
  const destinationId = optionalID(url.searchParams.get("destination_id"));

  const upstream = new URL(`${AMAP_BASE}/v5/direction/driving`);
  upstream.searchParams.set("key", requireAMapKey(env));
  upstream.searchParams.set("origin", origin);
  upstream.searchParams.set("destination", destination);
  upstream.searchParams.set("strategy", String(strategy));
  // Fixed server-side field selection. Clients cannot request arbitrary fields
  // or smuggle a key.
  upstream.searchParams.set("show_fields", "cost,tmcs,polyline,navi,cities");
  upstream.searchParams.set("output", "json");
  if (originId) upstream.searchParams.set("origin_id", originId);
  if (destinationId) upstream.searchParams.set("destination_id", destinationId);

  const payload = await fetchAMapJSON(upstream);
  if (String(payload.status) !== "1") {
    throw amapError(payload);
  }
  return jsonResponse(
    {
      status: payload.status,
      info: payload.info,
      infocode: payload.infocode,
      count: payload.count,
      route: payload.route,
    },
    200,
    request,
    env,
  );
}

async function proxyPlaces(url: URL, env: Env, request: Request): Promise<Response> {
  const keywords = (url.searchParams.get("keywords") ?? "").trim();
  if (keywords.length < 1 || keywords.length > 80) {
    throw new ProxyError(400, "BAD_REQUEST", "keywords must be between 1 and 80 characters.");
  }
  const region = (url.searchParams.get("region") ?? "").trim().slice(0, 64);

  const upstream = new URL(`${AMAP_BASE}/v5/place/text`);
  upstream.searchParams.set("key", requireAMapKey(env));
  upstream.searchParams.set("keywords", keywords);
  upstream.searchParams.set("page_size", "10");
  upstream.searchParams.set("page_num", "1");
  upstream.searchParams.set("output", "json");
  if (region) {
    upstream.searchParams.set("region", region);
    upstream.searchParams.set("city_limit", "false");
  }

  const payload = await fetchAMapJSON(upstream);
  if (String(payload.status) !== "1") {
    throw amapError(payload);
  }
  const rawPois = Array.isArray(payload.pois) ? payload.pois : [];
  const pois = rawPois.slice(0, 20).map((raw) => {
    const poi = asRecord(raw);
    return {
      name: safeString(poi.name),
      id: safeString(poi.id),
      location: safeString(poi.location),
      type: safeString(poi.type),
      typecode: safeString(poi.typecode),
      pname: safeString(poi.pname),
      cityname: safeString(poi.cityname),
      adname: safeString(poi.adname),
      address: safeString(poi.address),
      adcode: safeString(poi.adcode),
      citycode: safeString(poi.citycode),
    };
  });
  return jsonResponse(
    {
      status: payload.status,
      info: payload.info,
      infocode: payload.infocode,
      count: String(pois.length),
      pois,
    },
    200,
    request,
    env,
  );
}

async function fetchAMapJSON(url: URL): Promise<JsonRecord> {
  let response: Response;
  try {
    response = await fetch(url.toString(), {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (error) {
    const timedOut = error instanceof Error && error.name === "TimeoutError";
    throw new ProxyError(
      502,
      timedOut ? "UPSTREAM_TIMEOUT" : "UPSTREAM_UNAVAILABLE",
      "AMap service could not be reached.",
    );
  }

  if (!response.ok) {
    throw new ProxyError(502, "UPSTREAM_UNAVAILABLE", "AMap returned an HTTP error.");
  }
  const declaredLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
    throw new ProxyError(502, "UPSTREAM_TOO_LARGE", "AMap response exceeded the proxy limit.");
  }
  const buffer = await response.arrayBuffer();
  if (buffer.byteLength > MAX_RESPONSE_BYTES) {
    throw new ProxyError(502, "UPSTREAM_TOO_LARGE", "AMap response exceeded the proxy limit.");
  }
  const text = new TextDecoder("utf-8", { fatal: false }).decode(buffer);
  try {
    return asRecord(JSON.parse(text));
  } catch {
    throw new ProxyError(502, "UPSTREAM_INVALID_JSON", "AMap returned malformed JSON.");
  }
}

function amapError(payload: JsonRecord): ProxyError {
  const infocode = safeString(payload.infocode) || "unknown";
  const info = safeString(payload.info);
  // Do not echo the raw AMap message when it could contain internals. It is
  // retained only as a documented provider field for server-side debugging.
  const messages: Record<string, string> = {
    "10001": "AMap rejected the server API key.",
    "10003": "AMap daily quota is exhausted.",
    "10044": "AMap account daily quota is exhausted.",
    "10021": "AMap request rate limit was exceeded.",
  };
  const status = infocode.startsWith("208") ? 422 : infocode.startsWith("1000") ? 502 : 502;
  const code = infocode.startsWith("208") ? "AMAP_NO_ROUTE" : `AMAP_${infocode}`;
  return new ProxyError(
    status,
    code,
    messages[infocode] ?? `AMap could not complete the request (${info || "provider error"}).`,
  );
}

function parseCoordinateParam(value: string | null, label: string): string {
  if (!value) {
    throw new ProxyError(400, "BAD_REQUEST", `${label} is required.`);
  }
  const match = value.trim().match(/^(-?\d{1,3}(?:\.\d{1,6})?),\s*(-?\d{1,2}(?:\.\d{1,6})?)$/);
  if (!match) {
    throw new ProxyError(400, "BAD_REQUEST", `${label} must be "longitude,latitude" with at most 6 decimals.`);
  }
  const longitude = Number(match[1]);
  const latitude = Number(match[2]);
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)
      || longitude < -180 || longitude > 180
      || latitude < -90 || latitude > 90) {
    throw new ProxyError(400, "BAD_REQUEST", `${label} is outside the valid coordinate range.`);
  }
  return `${longitude.toFixed(6)},${latitude.toFixed(6)}`;
}

function optionalID(value: string | null): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!/^[A-Za-z0-9_]{1,64}$/.test(trimmed)) {
    throw new ProxyError(400, "BAD_REQUEST", "Invalid POI identifier.");
  }
  return trimmed;
}

function requireAMapKey(env: Env): string {
  const key = env.AMAP_KEY?.trim();
  if (!key) {
    throw new ProxyError(503, "PROXY_NOT_CONFIGURED", "AMAP_KEY is not configured on this Worker.");
  }
  return key;
}

async function authenticate(request: Request, env: Env): Promise<void> {
  const expected = env.PROXY_ACCESS_TOKEN?.trim();
  if (!expected) return;
  const header = request.headers.get("Authorization") ?? "";
  const prefix = "Bearer ";
  if (!header.startsWith(prefix) || !constantTimeEqual(header.slice(prefix.length), expected)) {
    throw new ProxyError(401, "UNAUTHORIZED", "Missing or invalid proxy access token.");
  }
}

async function enforceRateLimit(request: Request, env: Env, path: string): Promise<void> {
  if (path === "/v1/health") return;
  const limit = parseLimit(env.RATE_LIMIT_PER_MINUTE);
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const window = Math.floor(Date.now() / 60_000);
  const key = `${ip}:${window}`;
  let count: number;
  if (env.DRIVETIME_KV) {
    try {
      const existing = Number((await env.DRIVETIME_KV.get(key)) ?? "0");
      count = existing + 1;
      await env.DRIVETIME_KV.put(key, String(count), { expirationTtl: 120 });
    } catch {
      count = incrementMemory(key, window);
    }
  } else {
    count = incrementMemory(key, window);
  }
  if (count > limit) {
    throw new ProxyError(
      429,
      "RATE_LIMITED",
      "Too many requests. Try again shortly.",
      Math.max(1, 60 - (Math.floor(Date.now() / 1_000) % 60)),
    );
  }
}

function incrementMemory(key: string, window: number): number {
  const previous = memoryRateLimit.get(key);
  const count = previous && previous.window === window ? previous.count + 1 : 1;
  memoryRateLimit.set(key, { count, window });
  if (memoryRateLimit.size > 2_000) {
    for (const [storedKey, value] of memoryRateLimit) {
      if (value.window < window) memoryRateLimit.delete(storedKey);
    }
  }
  return count;
}

function parseLimit(value: string | undefined): number {
  const parsed = Number(value ?? "");
  if (!Number.isFinite(parsed)) return DEFAULT_RATE_LIMIT;
  return Math.min(120, Math.max(1, Math.trunc(parsed)));
}

function safeString(value: unknown): string {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return "";
}

function asRecord(value: unknown): JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonRecord)
    : {};
}

function constantTimeEqual(left: string, right: string): boolean {
  const length = Math.max(left.length, right.length);
  let difference = left.length ^ right.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (left.charCodeAt(index) || 0) ^ (right.charCodeAt(index) || 0);
  }
  return difference === 0;
}

function corsHeaders(request: Request, env: Env): Headers {
  const headers = new Headers();
  const allowed = (env as Env & { ALLOWED_ORIGINS?: string }).ALLOWED_ORIGINS?.split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
  const origin = request.headers.get("Origin");
  if (origin && allowed?.includes(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Vary", "Origin");
    headers.set("Access-Control-Allow-Headers", "Authorization, Accept, Content-Type");
    headers.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  }
  return headers;
}

function jsonResponse(
  body: JsonRecord,
  status: number,
  request: Request,
  env: Env,
): Response {
  const headers = new Headers(corsHeaders(request, env));
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("X-DriveTime-Proxy", "1");
  return new Response(JSON.stringify(body), { status, headers });
}

function errorResponse(error: unknown, request: Request, env: Env): Response {
  const proxyError = error instanceof ProxyError
    ? error
    : new ProxyError(500, "INTERNAL_ERROR", "The proxy encountered an unexpected error.");
  const headers = new Headers(corsHeaders(request, env));
  if (proxyError.retryAfter) headers.set("Retry-After", String(proxyError.retryAfter));
  const body: JsonRecord = {
    error: {
      code: proxyError.code,
      message: proxyError.message,
    },
  };
  return jsonResponse(body, proxyError.status, request, env);
}

// Re-export pure helpers for a possible local Node test harness. Cloudflare
// module workers ignore exports that are not the default handler.
export {
  constantTimeEqual,
  parseCoordinateParam,
  parseLimit,
  ensureWranglerCompatibility,
};

function ensureWranglerCompatibility(): void {
  // Symbolic export to keep pure helpers available to tests without relying on
  // a specific test runner. It intentionally has no runtime effect.
}
