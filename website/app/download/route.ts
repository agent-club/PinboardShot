import currentRelease from "@/content/current-release.json";

export function GET() {
  return new Response(null, {
    status: 302,
    headers: {
      Location: currentRelease.downloads.dmg.url,
      "Cache-Control": "no-store",
    },
  });
}

export const HEAD = GET;
