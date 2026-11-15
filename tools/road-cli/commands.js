'use strict';
// The todo demo's commands for road-cli (spec-patch-15 section 4.7): the worked example of what an
// application puts here. Each command is one step of the work, prints one line per answer, and
// uses the core's kit for calls, fresh reads and refusals. road-tracker's rt is a fuller example.

module.exports = {
  app: 'road-kit-demo',
  acceptVersion: '0',
  help: `  todos                            your open todos, one line each
  todo-add TITLE [--notes TEXT|-]  add a todo
  todo-done ID                     mark a todo done`,

  // Each command and the API resources it calls: scripts/generate-skill.mjs checks these against the
  // contract and against this file, so the skill never names a path the tool does not use.
  calls: {
    todos: ['GET /todos/'],
    'todo-add': ['POST /todos/'],
    'todo-done': ['GET /todos/{id}/', 'PATCH /todos/{id}/'],
  },

  commands: {
    todos: async (args, kit) => {
      const out = await kit.call('GET', '/todos/?status=OPEN');
      if (!out.items.length) return console.log('nothing open');
      for (const t of out.items) console.log(`${String(t.todo_id).padEnd(6)} ${t.title}`);
      if (out.hasMore) console.log('... more');
    },

    'todo-add': async (args, kit) => {
      const { opts, rest } = kit.options(args, ['notes']);
      kit.need(rest, 1, 'todo-add TITLE [--notes TEXT|-]');
      const body = { title: rest.join(' '), ...(opts.notes ? { notes: await kit.textArg(opts.notes) } : {}) };
      const t = await kit.call('POST', '/todos/', { body });
      console.log(`added ${t.todo_id}: ${t.title}`);
    },

    'todo-done': async (args, kit) => {
      kit.need(args, 1, 'todo-done ID');
      const id = Number(args[0]);
      const { rec } = await kit.onRecord(
        () => kit.call('GET', `/todos/${id}/`),
        (r) => kit.call('PATCH', `/todos/${id}/`, { body: { read_token: r.read_token, status: 'DONE' } }),
      );
      console.log(`${rec.todo.todo_id} done: ${rec.todo.title}`);
    },
  },
};
