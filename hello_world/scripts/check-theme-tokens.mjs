// Enforces ADR 01's one styling rule: tokens.css is the only place a colour, radius or
// font-family literal may appear.
//
// This is what ui-theme-standards-v1.md section 6 specified as bin/check-theme-parity.sh and what
// nobody ever wrote in any repository -- which is precisely why quorate's styles.css grew to 497
// lines against road-kit's 259 while the standard said the file was byte-identical. The ADR keeps
// the half of that design that addresses the failure which actually occurs.
//
// ADR 02 adds src/brand.css (the app's own look) and a dark theme, so the checks are now:
//   - parity of tokens.css AND theme.css with road-kit's copies; brand.css is the app's and is not compared;
//   - brand.css may set only custom properties that tokens.css defines;
//   - colours in the built stylesheet must come from tokens.css or brand.css;
//   - contrast, in both themes, of the text, status and chart colours as this app sets them.
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
const themeFile = path.join(appRoot, 'src', 'theme.css');
const brandFile = path.join(appRoot, 'src', 'brand.css');
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

const canonicalDirs = [
  path.join(appRoot, '..', '..', 'road-kit', 'hello_world', 'src'),
  path.join(appRoot, '..', 'road-kit', 'hello_world', 'src')
];
const canonicalDir = canonicalDirs.find((candidate) => fs.existsSync(path.join(candidate, 'tokens.css')));

for (const [name, file] of [['tokens.css', tokensFile], ['theme.css', themeFile]]) {
  if (!fs.existsSync(file)) {
    if (name === 'theme.css') failures.push('src/theme.css is missing.');
    continue;
  }
  if (!canonicalDir) {
    notices.push(`road-kit not found beside this repository, so ${name} parity was not checked.`);
  } else if (fs.realpathSync(path.join(canonicalDir, name)) === fs.realpathSync(file)) {
    notices.push(`This IS road-kit, so ${name} is canonical by definition and parity is trivial.`);
  } else if (fs.readFileSync(path.join(canonicalDir, name), 'utf8') !== fs.readFileSync(file, 'utf8')) {
    failures.push(
      `src/${name} differs from road-kit's canonical copy.\n` +
        `  Compare: diff ${path.relative(appRoot, path.join(canonicalDir, name))} src/${name}\n` +
        '  This file is byte-identical across every road-* application. If the change is genuinely\n' +
        '  wanted, make it in road-kit and copy it out; an app changes its look in src/brand.css.'
    );
  }
}

// --- 1b. brand.css sets only tokens that tokens.css defines --------------------------------------

function declaredProperties(css) {
  return new Set([...stripComments(css).matchAll(/(--[a-z0-9-]+)\s*:/gi)].map((m) => m[1]));
}

if (fs.existsSync(brandFile) && fs.existsSync(tokensFile)) {
  const known = declaredProperties(fs.readFileSync(tokensFile, 'utf8'));
  const unknown = [...declaredProperties(fs.readFileSync(brandFile, 'utf8'))].filter((n) => !known.has(n));
  if (unknown.length > 0) {
    failures.push(
      `src/brand.css sets ${unknown.length} property(ies) that tokens.css does not define:\n` +
        `${unknown.map((n) => `  - ${n}`).join('\n')}\n` +
        '  brand.css may only change existing tokens. A new token belongs in road-kit\'s tokens.css.'
    );
  }
}

// --- 2. No colour in the built stylesheet that tokens.css does not define -----------------------

if (!fs.existsSync(distDir)) {
  failures.push('dist/assets is missing. Run `npm run build` before this check.');
} else if (fs.existsSync(tokensFile)) {
  const tokenColours = coloursIn(stripComments(fs.readFileSync(tokensFile, 'utf8')));
  if (fs.existsSync(brandFile)) {
    for (const colour of coloursIn(stripComments(fs.readFileSync(brandFile, 'utf8')))) tokenColours.add(colour);
  }
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
          `tokens.css and brand.css:\n${strays.map((colour) => `  - #${colour}`).join('\n')}\n` +
          '  Add the colour to tokens.css (or brand.css) as a role-named token, or express it in one.'
      );
    }
  }
}


// --- 3. Contrast, in both themes ----------------------------------------------------------------
// The tokens as this app sets them: tokens.css, then brand.css, for :root and for :root.dark. The
// derived tokens are color-mix() values; they are computed here in OKLab, as the browser does.

function blocks(css, selector) {
  const out = {};
  const re = new RegExp(`${selector.replace(/[.]/g, '\\.')}\\s*\\{([^}]*)\\}`, 'g');
  for (const m of stripComments(css).matchAll(re)) {
    for (const d of m[1].matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/gi)) out[d[1]] = d[2].trim();
  }
  return out;
}

const toLinear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const fromLinear = (c) => (c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055);

function parseHex(v) {
  const h = normaliseHex(v);
  return [0, 2, 4].map((i) => Number.parseInt(h.slice(i, i + 2), 16) / 255);
}

function toOklab([r, g, b]) {
  const [lr, lg, lb] = [r, g, b].map(toLinear);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
  ];
}

function fromOklab([L, a, b]) {
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  const lin = [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s
  ];
  return lin.map((c) => Math.min(1, Math.max(0, fromLinear(c))));
}

function splitTop(text) {
  const parts = [];
  let depth = 0;
  let current = '';
  for (const ch of text) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) {
      parts.push(current.trim());
      current = '';
    } else current += ch;
  }
  parts.push(current.trim());
  return parts;
}

function resolveColour(value, vars, seen = []) {
  const v = value.trim();
  const ref = v.match(/^var\((--[a-z0-9-]+)\)$/i);
  if (ref) {
    if (seen.includes(ref[1]) || !(ref[1] in vars)) return null;
    return resolveColour(vars[ref[1]], vars, [...seen, ref[1]]);
  }
  if (v.startsWith('#')) return parseHex(v);
  const mix = v.match(/^color-mix\(\s*in oklab\s*,([\s\S]*)\)$/i);
  if (mix) {
    const [a, b] = splitTop(mix[1]);
    const take = (part) => {
      const m = part.match(/^(.*?)(?:\s+([\d.]+)%)?$/);
      return { colour: resolveColour(m[1], vars, seen), pct: m[2] === undefined ? null : Number(m[2]) };
    };
    const x = take(a);
    const y = take(b);
    if (!x.colour || !y.colour) return null;
    const px = x.pct ?? (y.pct === null ? 50 : 100 - y.pct);
    const mixed = toOklab(x.colour).map((c, i) => (c * px) / 100 + (toOklab(y.colour)[i] * (100 - px)) / 100);
    return fromOklab(mixed);
  }
  return null;
}

function luminance(rgb) {
  const [r, g, b] = rgb.map(toLinear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function ratio(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

if (fs.existsSync(tokensFile)) {
  const tokensCss = fs.readFileSync(tokensFile, 'utf8');
  const brandCss = fs.existsSync(brandFile) ? fs.readFileSync(brandFile, 'utf8') : '';
  const light = { ...blocks(tokensCss, ':root'), ...blocks(brandCss, ':root') };
  const dark = { ...light, ...blocks(tokensCss, ':root.dark'), ...blocks(brandCss, ':root.dark') };

  const textOn = ['--bg', '--surface'];
  const checks = [];
  for (const t of ['--ink', '--ink-soft', '--ink-muted', '--ink-eyebrow', '--primary']) {
    for (const bg of textOn) checks.push([t, bg, 4.5]);
  }
  for (const bg of ['--raised', '--hover', '--primary-soft']) checks.push(['--ink', bg, 4.5]);
  for (const kind of ['warning', 'error', 'success', 'info']) {
    checks.push([`--${kind}-fg`, `--${kind}-bg`, 4.5]);
  }
  checks.push(['--on-primary', '--primary', 4.5]);
  for (let i = 1; i <= 5; i++) checks.push([`--chart-${i}`, '--surface', 3]);

  for (const [theme, vars] of [['light', light], ['dark', dark]]) {
    for (const [fg, bg, min] of checks) {
      const a = resolveColour(`var(${fg})`, vars);
      const b = resolveColour(`var(${bg})`, vars);
      if (!a || !b) {
        failures.push(`Contrast (${theme}): could not resolve ${fg} or ${bg}.`);
        continue;
      }
      const r = ratio(a, b);
      if (r < min) {
        failures.push(`Contrast (${theme}): ${fg} on ${bg} is ${r.toFixed(2)}:1; it needs ${min}:1.`);
      }
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

console.log('[INFO] Theme token check passed: every shipped colour is a tokens.css or brand.css value, and contrast holds in both themes.');
