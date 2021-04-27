/**
 * Copyright 2020 William Perron. All rights reserved. MIT license.
 *
 * This program syncs a directory to a destination S3 bucket, much like the
 * `aws s3 sync --delete` command does, but additionnaly adds Content-Type
 * headers based on the extension of each file.
 *
 * The arguments parsing is heavily inspired by Deno's [file_server](https://deno.land/std/http/file_server.ts).
 * Some functions or classes are taken verbatim from that module.
 */

import { S3Bucket } from "https://deno.land/x/s3@0.4.1/mod.ts";
import { walk } from "https://deno.land/std@0.95.0/fs/walk.ts";
import {
  basename,
  extname,
  posix,
} from "https://deno.land/std@0.95.0/path/mod.ts";
import { pooledMap } from "https://deno.land/std@0.95.0/async/pool.ts";
import { parse } from "https://deno.land/std@0.95.0/flags/mod.ts";

export interface S3UploaderArgs {
  _: string[];
  // -b --bucket
  b: string;
  bucket: string;
  // -v --version
  v: string;
  version: string;
  // -h --help
  h?: boolean;
  help?: boolean;
}

const args = parse(Deno.args) as S3UploaderArgs;
const target = posix.resolve(args._[0] ?? "");
const modname = basename(target);
const version = args.v ?? args.version ?? "unstable";

const MEDIA_TYPES: Record<string, string> = {
  ".md": "text/markdown",
  ".html": "text/html",
  ".htm": "text/html",
  ".json": "application/json",
  ".map": "application/json",
  ".txt": "text/plain",
  ".ts": "text/typescript",
  ".tsx": "text/tsx",
  ".js": "application/javascript",
  ".jsx": "text/jsx",
  ".gz": "application/gzip",
  ".css": "text/css",
  ".wasm": "application/wasm",
  ".mjs": "application/javascript",
};

/**
 * yields tuple of entries in [key mime type] format
 */
async function* getFiles(
  target: string,
): AsyncGenerator<[string, string, string]> {
  for await (
    const entry of walk(target, {
      includeFiles: true,
      includeDirs: true,
      // common dirs to exclude
      skip: [/\.git\/*/, /\.terraform\/*/, /\.vscode\/*/],
    })
  ) {
    if (entry.isFile) {
      const relative = entry.path.slice(entry.path.indexOf(modname));
      const parts = relative.split("/");
      parts[0] = `${parts[0]}@${version}`;
      const key = parts.join("/");
      const mime = MEDIA_TYPES[extname(key)];
      yield [entry.path, key, mime];
    }
  }
}

async function main(): Promise<void> {
  if (args.h ?? args.help) {
    console.log(`Deno S3 module uploader
    uploads the content of a directory to S3

  INSTALL:
    deno install --allow-net --allow-read https://raw.githubusercontent.com/wperron/deno.wperron.io/1.0.2/s3-upload.ts

  USAGE:
    s3-upload [path] [options]

  OPTIONS:
    -h, --help              Prints help information
    -b, --bucket <BUCKET>   Set port
    -v, --version <VERSION> The version of the module being uploaded. defaults to \`unstable\`
`);
    Deno.exit();
  }

  const bucket = new S3Bucket({
    bucket: args.b ?? args.bucket,
    accessKeyID: Deno.env.get("AWS_ACCESS_KEY_ID") ?? "",
    secretKey: Deno.env.get("AWS_SECRET_ACCESS_KEY") ?? "",
    sessionToken: Deno.env.get("AWS_SESSION_TOKEN"),
    region: Deno.env.get("AWS_REGION") ?? "",
  });

  await pooledMap(20, getFiles(target), async ([path, key, contentType]) => {
    const res = await bucket.putObject(
      key,
      await (Deno.readAll(await Deno.open(path))),
      {
        contentType: contentType,
      },
    );
    console.log(`uploaded ${key} (${res.etag})`);
  });
}

if (import.meta.main) {
  main();
}
