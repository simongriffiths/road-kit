'use strict';
// The todo demo's commands for road-cli (spec-patch-15 section 4.7, rebuilt for the governed
// surface in spec-patch-16): the worked example of what an application puts here. Each command is
// one step of the work, prints one line per answer, and uses the core's kit for calls, fresh reads
// and refusals. road-tracker's rt is a fuller example.

module.exports = {
  app: 'road-kit-demo',
  acceptVersion: '0',
  help: `  todos                            your open todos, one line each
  todo-add TITLE [--notes TEXT|-]  add a todo
  todo-done ID                     mark a todo done
  todo-reopen ID                   make a done todo open again`,

  // Each command and the API resources it calls: scripts/generate-skill.mjs checks these against the
  // contract and against this file, so the skill never names a path the tool does not use.
  calls: {
    todos: ['GET /todos/'],
    'todo-add': ['POST /todos/'],
    'todo-done': ['GET /todos/{id}/', 'POST /todos/{id}/completions/'],
    'todo-reopen': ['GET /todos/{id}/', 'POST /todos/{id}/reopenings/'],
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
      // A governed action answers 200 with its decision: settle gives the result, or throws the
      // refusal (exit 3), such as TITLE_TAKEN.
      const t = kit.settle(await kit.call('POST', '/todos/', { body, key: kit.newKey() }));
      console.log(`added ${t.todo_id}: ${t.title}`);
    },

    'todo-done': async (args, kit) => {
      kit.need(args, 1, 'todo-done ID');
      const id = Number(args[0]);
      // onRecord reads the todo for a fresh read token, acts on it, and reads again once if it
      // changed meanwhile.
      const { rec } = await kit.onRecord(
        () => kit.call('GET', `/todos/${id}/`),
        (r) => kit.call('POST', `/todos/${id}/completions/`, { body: { read_token: r.read_token } }),
      );
      console.log(`${rec.todo.todo_id} done: ${rec.todo.title}`);
    },

    'todo-reopen': async (args, kit) => {
      kit.need(args, 1, 'todo-reopen ID');
      const id = Number(args[0]);
      const { rec } = await kit.onRecord(
        () => kit.call('GET', `/todos/${id}/`),
        (r) => kit.call('POST', `/todos/${id}/reopenings/`, { body: { read_token: r.read_token } }),
      );
      console.log(`${rec.todo.todo_id} open again: ${rec.todo.title}`);
    },
  },
};
