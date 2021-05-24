import { S3Bucket } from "https://deno.land/x/s3@0.4.1/mod.ts";
import { withLogging, withFirehose } from "./utils.ts";

const bucket = new S3Bucket(
  {
    bucket: "deno.wperron.io",
    region: "ca-central-1",
    accessKeyID: Deno.env.get("AWS_ACCESS_KEY_ID")!,
    secretKey: Deno.env.get("AWS_SECRET_ACCESS_KEY")!,
  },
);

// deno-lint-ignore no-explicit-any
addEventListener("fetch", async (event: any) => {
  event.respondWith(
    await withFirehose(
      withLogging(handleRequest),
      {
        region: "ca-central-1",
        credrentials: {
          accessKeyId: Deno.env.get("AWS_ACCESS_KEY_ID")!,
          secretAccessKey: Deno.env.get("AWS_SECRET_ACCESS_KEY")!,
        },
      },
      Deno.env.get("FIREHOSE_STREAM")!,
    )(event.request),
  );
});

async function handleRequest(req: Request): Promise<Response> {
  const reqUrl = new URL(req.url);
  if (reqUrl.hostname != "esm.wperron.io") {
    reqUrl.hostname = "esm.wperron.io";
    return new Response(null, {
      status: 301,
      headers: {
        "Location": reqUrl.toString(),
      }
    } as ResponseInit);
  }

  try {
    let path = leftTrim(reqUrl.pathname, "/");
    const obj = await bucket.getObject(path);
    if (path !== "" && obj) {
      const res = new Response(obj.body, {
        headers: {
          "Content-Type": obj.contentType ?? "text-plain",
          "Etag": obj.etag ?? "",
          "Cache-Control": obj.cacheControl ?? "max-age=3600",
        },
      });

      const cve = obj.meta["x-deno-known-cve"];
      if (cve) {
        res.headers.set("X-Deno-Known-CVE", cve);
      }

      return res;
    }

    if (path !== "") {
      path = path.endsWith("/") ? path : path + "/";
    }
    const ls = await bucket.listObjects({
      prefix: path,
    });

    const contents = new Set();
    ls?.contents?.forEach((obj) => {
      if (obj.key === undefined) return;
      const key = leftTrim(obj.key, path.endsWith("/") ? path : path + "/");
      contents.add(key.split("/")[0]);
    });

    return new Response(
      html`
      <!DOCTYPE html>
      <html>
        <head>
          <meta charset="utf8" />
          <title>wperron.io | Deno Modules</title>
        </head>
        <body>
          <h1>Personal Deno Registry</h1>
          <section id="content">
            <ul>
              ${
        Array.from(contents).map((k) => {
          return html`
                    <li>
                      <a href="${path}${k}">${k}</a>
                    </li>
                  `;
        })
      }
            </ul>
          </section>
        </body>
      </html>
    `,
      { status: 200, statusText: "OK", headers: { "Content-Type": "text/html" } },
    );
  } catch (e) {
    console.error(`request failed: ${e}`);
    return new Response(e, { status: 500 });
  }
}

// The following code is copied from
// https://deno.land/std@0.84.0/http/file_server.ts, and is licensed under the
// MIT license as per https://github.com/denoland/deno/blob/master/LICENSE.md.
function html(strings: TemplateStringsArray, ...values: unknown[]): string {
  const l = strings.length - 1;
  let html = "";

  for (let i = 0; i < l; i++) {
    let v = values[i];
    if (v instanceof Array) {
      v = v.join("");
    }
    const s = strings[i] + v;
    html += s;
  }
  html += strings[l];
  return html;
}

function leftTrim(str: string, char = "\s"): string {
  if (char === "") return str;
  let offset = 0;
  while (str.indexOf(char, offset) === 0 && offset < str.length) {
    offset += char.length;
  }
  return str.slice(offset);
}
