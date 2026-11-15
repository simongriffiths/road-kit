whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback

prompt === drop indexes ===
@db/indexes/road_decisions_idempotency.drop.sql
@db/indexes/road_agents_owner.drop.sql
@db/indexes/road_api_keys_agent.drop.sql
