/** Cloudflare Worker entry point for the PinboardShot website. */
import handler from "vinext/server/app-router-entry";

const appHandler = handler as {
  fetch(request: Request, env: unknown, context: unknown): Promise<Response> | Response;
};

const htmlLangByPath: Record<string, string> = {
  "/en": "en",
  "/privacy": "en",
  "/zh": "zh-CN",
};

function htmlLangForRequest(request: Request) {
  const { pathname } = new URL(request.url);
  return htmlLangByPath[pathname];
}

function addNoTransform(headers: Headers) {
  const cacheControl = headers.get("cache-control");

  if (!cacheControl) {
    headers.set("cache-control", "no-transform");
    return;
  }

  if (!/(^|,\s*)no-transform(\s*,|$)/i.test(cacheControl)) {
    headers.set("cache-control", `${cacheControl}, no-transform`);
  }
}

async function withLocalizedHtmlLang(request: Request, response: Response) {
  const htmlLang = htmlLangForRequest(request);
  const contentType = response.headers.get("content-type") ?? "";

  if (!/^text\/html\b/i.test(contentType)) {
    return response;
  }

  if (!htmlLang) {
    const headers = new Headers(response.headers);
    addNoTransform(headers);

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  }

  const html = await response.text();
  const headers = new Headers(response.headers);
  headers.delete("content-length");
  addNoTransform(headers);

  return new Response(html.replace(/<html lang="[^"]*"/i, `<html lang="${htmlLang}"`), {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

const worker = {
  async fetch(request: Request, env: unknown, context: unknown) {
    const response = await appHandler.fetch(request, env, context);
    return withLocalizedHtmlLang(request, response);
  },
};

export default worker;
