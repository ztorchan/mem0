import { defineConfig } from "tsup";

const external = [
  // dependencies
  "openai",
  "uuid",
  "zod",
  "axios",
  // peerDependencies
  "@anthropic-ai/sdk",
  "@azure/identity",
  "@azure/search-documents",
  "@cloudflare/workers-types",
  "@google/genai",
  "@langchain/core",
  "@mistralai/mistralai",
  "@qdrant/js-client-rest",
  "@supabase/supabase-js",
  "better-sqlite3",
  "cloudflare",
  "groq-sdk",
  "neo4j-driver",
  "ollama",
  "pg",
  "redis",
];

export default defineConfig([
  {
    entry: ["src/client/index.ts"],
    format: ["cjs", "esm"],
    dts: true,
    sourcemap: true,
    external,
  },
  {
    entry: ["src/oss/src/index.ts"],
    outDir: "dist/oss",
    format: ["cjs", "esm"],
    dts: true,
    sourcemap: true,
    external,
  },
]);
