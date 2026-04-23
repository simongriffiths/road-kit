import fs from 'node:fs';
import path from 'node:path';

const appRoot = process.cwd();
const srcRoot = path.join(appRoot, 'src');
const distRoot = path.join(appRoot, 'dist');
const runtimeConfigFile = path.join(srcRoot, 'config', 'runtime.ts');
const phaseArgIndex = process.argv.indexOf('--phase');
const phase = phaseArgIndex >= 0 ? process.argv[phaseArgIndex + 1] : 'all';

function walkFiles(rootDir, predicate) {
  const results = [];

  for (const entry of fs.readdirSync(rootDir, { withFileTypes: true })) {
    const fullPath = path.join(rootDir, entry.name);

    if (entry.isDirectory()) {
      results.push(...walkFiles(fullPath, predicate));
      continue;
    }

    if (predicate(fullPath)) {
      results.push(fullPath);
    }
  }

  return results;
}

function validateSourceUsage() {
  const sourceFiles = walkFiles(
    srcRoot,
    (filePath) => filePath.endsWith('.ts') || filePath.endsWith('.tsx')
  );

  const offenders = sourceFiles.filter((filePath) => {
    if (filePath === runtimeConfigFile) {
      return false;
    }

    const content = fs.readFileSync(filePath, 'utf8');
    return content.includes('import.meta.env.VITE_ORDS_BASE_URL');
  });

  if (offenders.length > 0) {
    throw new Error(
      [
        'Direct VITE_ORDS_BASE_URL access is forbidden outside src/config/runtime.ts.',
        'Use the runtime URL helper so hosted builds cannot regress to placeholder hosts.',
        ...offenders.map((filePath) => `- ${path.relative(appRoot, filePath)}`)
      ].join('\n')
    );
  }
}

function validateDistArtifacts() {
  if (!fs.existsSync(distRoot)) {
    throw new Error('dist/ does not exist. Build output is required for dist validation.');
  }

  const jsFiles = walkFiles(distRoot, (filePath) => filePath.endsWith('.js'));
  const htmlFiles = walkFiles(distRoot, (filePath) => filePath.endsWith('.html'));
  const placeholderFiles = [];
  let placeholderIsRuntimeAware = false;

  for (const filePath of [...jsFiles, ...htmlFiles]) {
    const content = fs.readFileSync(filePath, 'utf8');

    if (content.includes('https://<host>')) {
      placeholderFiles.push(path.relative(appRoot, filePath));

      if (content.includes('window.location.origin')) {
        placeholderIsRuntimeAware = true;
      }
    }
  }

  if (placeholderFiles.length > 0 && !placeholderIsRuntimeAware) {
    throw new Error(
      [
        'Build output still contains https://<host> but no runtime host substitution was found.',
        'This would break browser requests against the hosted UI.',
        ...placeholderFiles.map((filePath) => `- ${filePath}`)
      ].join('\n')
    );
  }
}

if (phase === 'source' || phase === 'all') {
  validateSourceUsage();
}

if (phase === 'dist' || phase === 'all') {
  validateDistArtifacts();
}

console.log(`[INFO] Build validation passed for phase=${phase}`);
