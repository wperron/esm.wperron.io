import { S3Bucket } from "https://deno.land/x/s3@0.3.0/mod.ts";

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
    await handleRequest(event.request)
  );
});

async function handleRequest(req: Request): Promise<Response> {
  const res = new Response();
  const obj = await bucket.getObject(req.url);
  if (obj) {
    return new Response(obj.body);
  }

  const path = leftTrim(new URL(req.url).pathname, "/");
  const ls = await bucket.listObjects({
    prefix: path.endsWith("/") ? path : path + "/",
  });

  const contents = new Set()
  ls?.contents?.forEach((obj) => {
    if (obj.key === undefined) return;
    const key = leftTrim(obj.key, path.endsWith("/") ? path : path + "/");
    contents.add(key.split("/")[0]);
  });

  return new Response(html`
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
                    <a href="${path}/${k}">${k}</a>
                  </li>
                `;
              })
            }
          </ul>
        </section>
      </body>
    </html>
  `)
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