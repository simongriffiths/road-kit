-- INTENT:
-- Purpose: Verify the configured SQLcl connection can run a basic query.
-- Approach: Select the current database user and timestamp from DUAL.
-- Reason: Provides a low-risk smoke test for a new sql-runner setup.
-- Expected objects:
--   None
-- Risk: Low
-- Prior history checked: Not applicable for a new repository.
-- END INTENT

select
    user as connected_user,
    systimestamp as checked_at
from dual;
