import { cpSync, existsSync, mkdirSync } from "node:fs";

mkdirSync(new URL("../dist", import.meta.url), { recursive: true });

if (existsSync(new URL("../public/index.html", import.meta.url))) {
  cpSync(
    new URL("../public/index.html", import.meta.url),
    new URL("../dist/index.html", import.meta.url)
  );
}

if (existsSync(new URL("../public/styles.css", import.meta.url))) {
  cpSync(
    new URL("../public/styles.css", import.meta.url),
    new URL("../dist/styles.css", import.meta.url)
  );
}
