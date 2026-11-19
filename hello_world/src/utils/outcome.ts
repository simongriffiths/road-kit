import type { GovernedOutcome } from '../types/api';

// Reading a governed answer, written once (spec-patch-17 section 3.5). A refusal is an answer to
// what the person asked, not an error. Its text comes from the database; the page holds no rules.

export const isAccepted = (o: GovernedOutcome) => o.decision === 'accepted';

export const isStale = (o: GovernedOutcome) =>
  o.decision === 'rejected' && o.rejections.some((r) => r.rule_id === 'STALE_TOKEN');

export const refusalText = (o: GovernedOutcome): string | null =>
  o.decision === 'rejected' ? o.rejections.map((r) => r.message).join(' ') : null;
