// Resolves an application's Governed Surface Contract: the file, plus the framework fragments its
// x-road-include lists, merged into one document (spec-patch-16 section 3.6; road-atlas D-04: one
// surface, one contract). Fragments live in contract/fragments/ beside the contract file. A
// fragment holds actions (state.actions), views (publication.views) and public_entries, and any
// x-* annotation. The merged document has none of the x-* keys, so it validates against the
// schema, and it is what road_contract holds and GET /contract/ serves.
import fs from 'node:fs';
import path from 'node:path';

const without = (obj, test) => Object.fromEntries(Object.entries(obj).filter(([k]) => !test(k)));

export function resolveContract(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const includes = raw['x-road-include'] ?? [];
  const merged = without(raw, (k) => k.startsWith('x-'));
  merged.state = { ...(merged.state ?? {}), actions: [...(merged.state?.actions ?? [])] };
  merged.publication = { ...(merged.publication ?? {}), views: [...(merged.publication?.views ?? [])] };
  merged.envelope = { ...merged.envelope };
  const publicEntries = new Set(merged.envelope.public_entries ?? []);
  for (const name of includes) {
    const fragmentFile = path.join(path.dirname(file), 'fragments', `${name}.json`);
    if (!fs.existsSync(fragmentFile)) throw new Error(`x-road-include names "${name}", but ${fragmentFile} does not exist`);
    const fragment = JSON.parse(fs.readFileSync(fragmentFile, 'utf8'));
    merged.state.actions.push(...(fragment.state?.actions ?? []));
    merged.publication.views.push(...(fragment.publication?.views ?? []));
    for (const id of fragment.envelope?.public_entries ?? []) publicEntries.add(id);
  }
  merged.envelope.public_entries = [...publicEntries];
  if (merged.state.actions.length === 0) delete merged.state;
  if (merged.publication.views.length === 0 && merged.publication.provisional === undefined) delete merged.publication;
  return { contract: merged, includes };
}
