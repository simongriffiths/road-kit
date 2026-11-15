# road-cli

The command-line core for a road-kit application's agents (spec-patch-15). An agent, such as
Claude Code, uses it to work the application through its REST API as its own identity.

## For an application

1. Copy this folder into the application and rename `road-cli` to the application's command
   (road-tracker's is `rt`).
2. Replace `commands.js` with the application's task commands: one per step of the work, each
   printing one short line. Export `app` (the settings folder name), `help`, `calls` (each command's
   `METHOD /path` resources, for the skill generator) and `commands`.
3. Write `skills/<app>/skill.config.mjs` and run `node scripts/generate-skill.mjs` on it; add
   `--check` to the release checks.
4. Set `road_config` `agents.role` to the application's agent role (include `session.me.read`), and
   grant `road.agent.self_serve` and `road.agents.rw` to the roles whose holders may make agents.

## For a person

1. On the My agents page, make an agent and a key for it, named for where it will run.
2. Where the agent runs: `road-cli login --url <host>/ords/<alias>/api/v1`, and paste the key when it
   asks. It is kept in `~/.config/<app>/` (mode 600), never on the command line.
3. `road-cli whoami` shows the agent it signs in as. Revoke the key on the My agents page to stop it.

Exit codes: 0 done, 1 error, 2 usage, 3 refused by a rule, 4 and up the application's own.
