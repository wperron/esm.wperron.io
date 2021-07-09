export type Handler = (r: Request) => Promise<Response>;

export function withLogging(f: Handler): Handler {
  return async (req: Request) => {
    const res = await f(req);
    console.log(`${res.status} ${res.statusText} ${new URL(req.url).pathname}`);
    return res;
  }
}

