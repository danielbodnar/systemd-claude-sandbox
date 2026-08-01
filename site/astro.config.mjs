// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

export default defineConfig({
  site: "https://danielbodnar.github.io",
  base: "/systemd-claude-sandbox",
  integrations: [
    starlight({
      title: "systemd-claude-sandbox",
      description:
        "A self-hosted code-execution sandbox for Claude, built on docker compose and systemd.",
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/danielbodnar/systemd-claude-sandbox",
        },
      ],
      editLink: {
        baseUrl:
          "https://github.com/danielbodnar/systemd-claude-sandbox/edit/main/site/",
      },
      sidebar: [
        {
          label: "Tutorials",
          items: [{ label: "Getting started", slug: "tutorials/getting-started" }],
        },
        {
          label: "How-to guides",
          items: [
            { label: "Deploy to your own host", slug: "how-to/deploy" },
            { label: "Enable the Cloudflare Tunnel publisher", slug: "how-to/cloudflared" },
            { label: "Add an agent to the dev image", slug: "how-to/add-agent" },
          ],
        },
        {
          label: "Reference",
          items: [
            { label: "justfile recipes", slug: "reference/justfile" },
            { label: "Environment variables", slug: "reference/environment" },
            { label: "Compose services", slug: "reference/compose" },
            { label: "Tunnel configuration", slug: "reference/tunnel-config" },
          ],
        },
        {
          label: "Explanation",
          items: [
            { label: "Architecture", slug: "explanation/architecture" },
            { label: "The sandbox contract", slug: "explanation/sandbox-contract" },
            { label: "Transports and the open decision", slug: "explanation/transports" },
          ],
        },
      ],
    }),
  ],
});
