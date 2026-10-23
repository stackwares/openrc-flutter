import { env } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { isAllowedOrigin } from "../src/cors";
import worker from "../src/index";

const APP = "https://openrc-app.pages.dev";

// Requests as the Worker receives them, with Cloudflare's incoming metadata.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

// The production list, whatever a local .dev.vars says.
const testEnv: Env = {
  ...env,
  ALLOWED_ORIGINS: "https://openrc-app.pages.dev,https://*.openrc-app.pages.dev",
};

function call(
  path: string,
  init: RequestInit<IncomingRequestCfProperties> = {},
): Promise<Response> {
  return worker.fetch(
    new IncomingRequest(`https://openrc-relay.example.workers.dev${path}`, init),
    testEnv,
  );
}

function mockUpstream(response: Response) {
  return vi.spyOn(globalThis, "fetch").mockResolvedValue(response);
}

afterEach(() => vi.restoreAllMocks());

describe("origins", () => {
  it("allows the app, its previews and configured local ports", () => {
    const list = "https://openrc-app.pages.dev,https://*.openrc-app.pages.dev,http://localhost:*";
    expect(isAllowedOrigin("https://openrc-app.pages.dev", list)).toBe(true);
    expect(isAllowedOrigin("https://feature-x.openrc-app.pages.dev", list)).toBe(true);
    expect(isAllowedOrigin("http://localhost:61234", list)).toBe(true);
  });

  it("refuses lookalikes, other schemes and non-origins", () => {
    const list = "https://openrc-app.pages.dev,https://*.openrc-app.pages.dev";
    for (const origin of [
      null,
      "null",
      "https://openrc-app.pages.dev.evil.com",
      "https://evilopenrc-app.pages.dev",
      "http://openrc-app.pages.dev",
      "https://openrc-app.pages.dev:8443",
      "https://openrc-app.pages.dev/path",
      "http://localhost:3000",
    ]) {
      expect(isAllowedOrigin(origin, list), String(origin)).toBe(false);
    }
  });

  it("answers preflights only for allowed origins", async () => {
    const ok = await call("/v1/developers/me", {
      method: "OPTIONS",
      headers: { Origin: APP, "Access-Control-Request-Method": "GET" },
    });
    expect(ok.status).toBe(204);
    expect(ok.headers.get("Access-Control-Allow-Origin")).toBe(APP);
    expect(ok.headers.get("Access-Control-Allow-Headers")).toContain("Authorization");

    const denied = await call("/v1/developers/me", {
      method: "OPTIONS",
      headers: { Origin: "https://evil.example" },
    });
    expect(denied.status).toBe(403);
    expect(denied.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("refuses requests without an Origin, so it is no open proxy", async () => {
    const fetchSpy = mockUpstream(new Response("{}"));
    const res = await call("/v1/developers/me");
    expect(res.status).toBe(403);
    expect(fetchSpy).not.toHaveBeenCalled();
  });
});

describe("RevenueCat API", () => {
  it("forwards the developer API with only the needed headers", async () => {
    const fetchSpy = mockUpstream(
      new Response('{"email":"ada@example.com"}', {
        headers: {
          "Content-Type": "application/json",
          "Set-Cookie": "session=abc",
          "Access-Control-Allow-Origin": "https://app.revenuecat.com",
        },
      }),
    );
    const res = await call("/v1/developers/me?expand=projects", {
      headers: {
        Origin: APP,
        Authorization: "Bearer token-123",
        "X-Requested-With": "XMLHttpRequest",
        Cookie: "tracking=1",
      },
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ email: "ada@example.com" });
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(APP);
    expect(res.headers.get("Set-Cookie")).toBeNull();

    const [target, init] = fetchSpy.mock.calls[0];
    expect(String(target)).toBe("https://api.revenuecat.com/v1/developers/me?expand=projects");
    const sent = new Headers(init?.headers);
    expect(sent.get("authorization")).toBe("Bearer token-123");
    expect(sent.get("x-requested-with")).toBe("XMLHttpRequest");
    expect(sent.get("cookie")).toBeNull();
    expect(sent.get("origin")).toBeNull();
  });

  it("forwards the internal developer API and request bodies", async () => {
    const fetchSpy = mockUpstream(new Response("{}", { status: 201 }));
    const res = await call("/internal/v1/developers/login", {
      method: "POST",
      headers: { Origin: APP, "Content-Type": "application/json" },
      body: '{"email":"ada@example.com"}',
    });
    expect(res.status).toBe(201);
    const [target, init] = fetchSpy.mock.calls[0];
    expect(String(target)).toBe("https://api.revenuecat.com/internal/v1/developers/login");
    expect(init?.method).toBe("POST");
    expect(await new Response(init?.body).text()).toBe('{"email":"ada@example.com"}');
  });

  it("passes nothing else through", async () => {
    const fetchSpy = mockUpstream(new Response("{}"));
    for (const path of [
      "/v1/subscribers/abc",
      "/v2/projects",
      "/v1/developersx",
      "/v1/developers/../../v1/subscribers/abc",
      "/internal/v2/anything",
    ]) {
      const res = await call(path, { headers: { Origin: APP } });
      expect(res.status, path).toBe(404);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("reports an unreachable RevenueCat as a gateway error", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("connection reset"));
    vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await call("/v1/developers/me", { headers: { Origin: APP } });
    expect(res.status).toBe(502);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe(APP);
  });
});

describe("icons", () => {
  it("rejects anything but a reverse-DNS id", async () => {
    const fetchSpy = mockUpstream(new Response("{}"));
    const res = await call("/icon?bundleId=https://evil.example", { headers: { Origin: APP } });
    expect(res.status).toBe(400);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("returns the App Store artwork", async () => {
    mockUpstream(
      new Response(
        JSON.stringify({ results: [{ artworkUrl512: "https://is1-ssl.mzstatic.com/icon.png" }] }),
      ),
    );
    const res = await call("/icon?bundleId=com.example.app&hint=apple", { headers: { Origin: APP } });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ url: "https://is1-ssl.mzstatic.com/icon.png" });
    expect(res.headers.get("Cache-Control")).toContain("max-age=86400");
  });
});

it("has a health check for uptime monitors", async () => {
  const res = await call("/");
  expect(res.status).toBe(200);
  expect(await res.json()).toEqual({ service: "openrc-relay", ok: true });
});
