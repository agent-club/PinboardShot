export function GET(request: Request) {
  return new Response(null, {
    status: 308,
    headers: {
      Location: new URL("/og.png", request.url).toString(),
      "Cache-Control": "public, max-age=3600, s-maxage=86400",
    },
  });
}

export const HEAD = GET;
