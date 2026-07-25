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

async function withLocalizedHtmlLang(request: Request, response: Response) {
  const htmlLang = htmlLangForRequest(request);
  const contentType = response.headers.get("content-type") ?? "";

  if (!htmlLang || !/^text\/html\b/i.test(contentType)) {
    return response;
  }

  const html = await response.text();
  const headers = new Headers(response.headers);
  headers.delete("content-length");

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
