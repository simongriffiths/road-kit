// Enforces ADR 01's one styling rule: tokens.css is the only place a colour, radius or
// font-family literal may appear.
//
// This is what ui-theme-standards-v1.md section 6 specified as bin/check-theme-parity.sh and what
// nobody ever wrote in any repository -- which is precisely why quorate's styles.css grew to 497
// lines against road-kit's 259 while the standard said the file was byte-identical. The ADR keeps
// the half of that design that addresses the failure which actually occurs.
//
// TWO CHECKS, and the second is the one with teeth.
//
// 1. PARITY. tokens.css matches road-kit's canonical copy, byte for byte. Skipped with a notice
//    when road-kit cannot be found beside this repository, so a checkout on its own still runs.
//
// 2. NO STRAY LITERALS IN WHAT SHIPS. Every colour in the built stylesheet must be a tokens.css
//    value. This reads dist/ rather than src/ on purpose: source-grepping is defeated by anything
//    that computes a colour, and it cannot see what a dependency contributes. The built file is
//    the artefact the rule is actually about. Run `npm run build` first.
//
// Colours are compared as normalised 8-digit hex, because the minifier rewrites #ffffff to #fff
// and rgba(25, 44, 36, 0.04) to #192c240a -- three spellings of a value that must count as one.
//
// WHAT THIS CANNOT SEE, in the spirit of bin/check-road-kit-parity.sh's own header: it checks
// colour only. A radius or font-family literal in a component will not be caught here, and
// src/components/ui/ is vendored upstream shadcn source that genuinely does carry radius literals
// in its arbitrary variants -- `rounded-[min(var(--radius-md),10px)]` is upstream's, not ours.
// Catching those means a source rule with a vendored-code exemption, which is a separate decision
// from this one.

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const appRoot = process.cwd();
const tokensFile = path.join(appRoot, 'src', 'tokens.css');
const distDir = path.join(appRoot, 'dist', 'assets');

const failures = [];
const notices = [];

// #rgb, #rgba, #rrggbb and #rrggbbaa all normalise to eight lowercase digits, so the same colour
// spelled three ways compares equal.
function normaliseHex(raw) {
  let hex = raw.replace('#', '').toLowerCase();

  if (hex.length === 3 || hex.length === 4) {
    hex = [...hex].map((digit) => digit + digit).join('');
  }

  return hex.length === 6 ? `${hex}ff` : hex;
}

function rgbaToHex(raw) {
  const parts = raw
    .slice(raw.indexOf('(') + 1, raw.lastIndexOf(')'))
    .split(/[,/]/)
    .map((part) => part.trim())
    .filter(Boolean);

  if (parts.length < 3) {
    return null;
  }

  const channels = parts.slice(0, 3).map((part) => Number.parseInt(part, 10));

  if (channels.some(Number.isNaN)) {
    return null;
  }

  const alpha = parts.length > 3 ? Number.parseFloat(parts[3]) : 1;
  const bytes = [...channels, Math.round((Number.isNaN(alpha) ? 1 : alpha) * 255)];

  return bytes.map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function coloursIn(css) {
  const found = new Set();

  for (const match of css.matchAll(/#[0-9a-fA-F]{3,8}\b/g)) {
    found.add(normaliseHex(match[0]));
  }

  for (const match of css.matchAll(/rgba?\([^)]*\)/g)) {
    const hex = rgbaToHex(match[0]);

    if (hex) {
      found.add(hex);
    }
  }

  return found;
}

function stripComments(css) {
  return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

// --- 1. Parity with road-kit's canonical tokens.css --------------------------------------------

if (!fs.existsSync(tokensFile)) {
  failures.push('src/tokens.css is missing. It is tier 1 and every other rule depends on it.');
}

const canonicalCandidates = [
  path.join(appRoot, '..', '..', 'road-kit', 'hello_world', 'src', 'tokens.css'),
  path.join(appRoot, '..', 'road-kit', 'hello_world', 'src', 'tokens.css')
];
const canonicalFile = canonicalCandidates.find((candidate) => fs.existsSync(candidate));

if (!fs.existsSync(tokensFile)) {
  // Nothing further to compare.
} else if (!canonicalFile) {
  notices.push('road-kit not found beside this repository, so tokens.css parity was not checked.');
} else if (fs.realpathSync(canonicalFile) === fs.realpathSync(tokensFile)) {
  notices.push('This IS road-kit, so tokens.css is canonical by definition and parity is trivial.');
} else if (fs.readFileSync(canonicalFile, 'utf8') !== fs.readFileSync(tokensFile, 'utf8')) {
  failures.push(
    `src/tokens.css differs from road-kit's canonical copy.\n` +
      `  Compare: diff ${path.relative(appRoot, canonicalFile)} src/tokens.css\n` +
      '  Tier 1 is byte-identical across every road-* application. If the change is genuinely\n' +
      '  wanted, make it in road-kit and copy it out, rather than letting one repo drift.'
  );
}

// --- 2. No colour in the built stylesheet that tokens.css does not define -----------------------

if (!fs.existsSync(distDir)) {
  failures.push('dist/assets is missing. Run `npm run build` before this check.');
} else if (fs.existsSync(tokensFile)) {
  const tokenColours = coloursIn(stripComments(fs.readFileSync(tokensFile, 'utf8')));
  // Fully transparent is a keyword, not a palette choice.
  tokenColours.add('00000000');

  const builtStylesheets = fs
    .readdirSync(distDir)
    .filter((entry) => entry.endsWith('.css'))
    .map((entry) => path.join(distDir, entry));

  if (builtStylesheets.length === 0) {
    failures.push('No stylesheet in dist/assets. Run `npm run build` before this check.');
  }

  for (const stylesheet of builtStylesheets) {
    const css = fs.readFileSync(stylesheet, 'utf8');
    const strays = [...coloursIn(css)].filter((colour) => !tokenColours.has(colour)).sort();

    // oklch is how upstream shadcn ships its default palette. Finding any means the theme preset
    // has stopped displacing it -- the exact regression theme.css exists to prevent.
    const oklchCount = [...css.matchAll(/oklch\(/g)].length;

    if (oklchCount > 0) {
      failures.push(
        `${path.relative(appRoot, stylesheet)} ships ${oklchCount} oklch() colour(s).\n` +
          "  That is upstream shadcn's own palette leaking past src/theme.css. Check that the\n" +
          '  :root block there still defines every shadcn variable in terms of a tier-1 token.'
      );
    }

    if (strays.length > 0) {
      failures.push(
        `${path.relative(appRoot, stylesheet)} ships ${strays.length} colour(s) absent from ` +
          `tokens.css:\n${strays.map((colour) => `  - #${colour}`).join('\n')}\n` +
          '  Add the colour to tokens.css as a role-named token, or express it in one.'
      );
    }
  }
}

// --- Report -------------------------------------------------------------------------------------

for (const notice of notices) {
  console.log(`[INFO] ${notice}`);
}

if (failures.length > 0) {
  console.error('\n[FAIL] Theme token check failed.\n');
  for (const failure of failures) {
    console.error(`- ${failure}\n`);
  }
  process.exit(1);
}

console.log('[INFO] Theme token check passed: every shipped colour is a tokens.css value.');
