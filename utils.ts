import { FirehoseClient, PutRecordCommand } from "https://cdn.skypack.dev/@aws-sdk/client-firehose@v3.13.0?dts";

export type handler = (r: Request) => Promise<Response>;

export function withLogging(f: handler): handler {
  return async (req: Request) => {
    const res = await f(req);
    console.log(`${res.status} ${res.statusText} ${new URL(req.url).pathname}`);
    return res;
  }
}

