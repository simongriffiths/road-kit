// Generates skills/hello_world/SKILL.md and reference.md from the demo's contract:
//   node scripts/generate-skill.mjs skills/hello_world/skill.config.mjs          write them
//   node scripts/generate-skill.mjs skills/hello_world/skill.config.mjs --check  fail if stale
// The agent's permissions are read from deploy/create/97_demo.sql, so the skill names only what the
// todo_agent role may do. The commands are tools/road-cli/commands.js.
export default {
  name: 'road-kit-todos',
  title: 'road-kit todo demo',
  description: "Work the road-kit demo's todo list with the todos command: list open todos, add one, mark it done or reopen it. Use when asked to manage todos in the road-kit demo.",
  cli: 'road-cli',
  contract: 'contract/hello_world.gsc.json',
  commands: 'tools/road-cli/commands.js',
  roleData: { file: 'deploy/create/97_demo.sql', role: 'todo_agent' },
  workflow: `## Work

1. \`road-cli todos\` lists your open todos, one per line: the id, then the title.
2. \`road-cli todo-add TITLE\` adds one. Add \`--notes TEXT\` for notes, or \`--notes -\` to read them from standard input.
3. \`road-cli todo-done ID\` marks one done; \`road-cli todo-reopen ID\` makes a done one open again.

You only ever see and change your own todos. A todo that is someone else's, or deleted, is reported as not existing.`,
};
