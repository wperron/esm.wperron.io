import { FirehoseClient, PutRecordCommand } from "https://cdn.skypack.dev/@aws-sdk/client-firehose@v3.13.0?dts";

export type handler = (r: Request) => Promise<Response>;

export function withLogging(f: handler): handler {
  return async (req: Request) => {
    const res = await f(req);
    console.log(`${res.status} ${res.statusText} ${new URL(req.url).pathname}`);
    return res;
  }
}

export type AWSConfiguration = {
  region: string,
  credrentials: AWSCredentials
}

export type AWSCredentials = {
  accessKeyId: string,
  secretAccessKey: string,
}

export type DeliveryStreamName = string;

export function withFirehose(f: handler, c: AWSConfiguration, s: DeliveryStreamName): handler {
  // @ts-ignore
  const client = new FirehoseClient(c);
  return async (req: Request) => {
    const res = await f(req);
    // async/await.
    try {
      const {
        $metadata: { httpStatusCode },
        // @ts-ignore
      } = await client.send(new PutRecordCommand({
        DeliveryStreamName: s,
        Record: {
          status: res.status,
          statusText: res.statusText,
          path: new URL(req.url).pathname,
        }
      }));

      if (httpStatusCode && httpStatusCode >= 400) {
        throw new Error(`DynamoDB error ${httpStatusCode}`);
      }
    } catch (error) {
      console.error(`failed to send data to Firehose: ${error}`);
    }
    return res;
  }
}