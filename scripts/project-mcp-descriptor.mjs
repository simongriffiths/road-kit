#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

// Deterministically projects a Governed State Contract (W1 schema, v0.1.0) into an
// MCP tool descriptor: { name, description, inputSchema }, the shape `tools/list`
// returns per the Model Context Protocol spec. See planning/action-w2-mcp-descriptor-
// projection.md for what is preserved, transformed, or deliberately excluded and why.
export function projectMcpDescriptor(contract) {
  const name = contract.capability_id.replace(/[.-]/g, '_');
  const description = contract.title ?? contract.action_resource.intent;

  const body = contract.request.body;
  const properties = {};
  for (const [propName, propSchema] of Object.entries(body.properties ?? {})) {
    if (propSchema && propSchema['x-mcp-exclude'] === true) continue;
    properties[propName] = propSchema;
  }
  const required = (body.required ?? []).filter((propName) => propName in properties);

  const inputSchema = { type: body.type };
  if (body.additionalProperties !== undefined) {
    inputSchema.additionalProperties = body.additionalProperties;
  }
  inputSchema.properties = properties;
  inputSchema.required = required;

  return { name, description, inputSchema };
}

async function main() {
  const inputArg = process.argv[2];
  const inputPath = inputArg
    ? new URL(inputArg, `file://${process.cwd()}/`)
    : new URL('../test/contract/fixtures/governed-state-contract.valid.json', import.meta.url);
  const contract = JSON.parse(await readFile(fileURLToPath(inputPath), 'utf8'));
  process.stdout.write(`${JSON.stringify(projectMcpDescriptor(contract), null, 2)}\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}
