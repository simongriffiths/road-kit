// A dependency-free validator for the subset of JSON Schema draft 2020-12 that road-kit's
// contract schemas use. It is not a general validator.
//
// It refuses to run a schema that uses a keyword it does not implement. A validator that skipped
// an unknown keyword would pass documents the schema means to reject, and nobody would notice.
//
// Only local references ("#/$defs/name") are supported.

const ANNOTATIONS = new Set([
  '$schema', '$id', '$comment', 'title', 'description', 'default', 'examples', 'format',
  'deprecated', 'readOnly', 'writeOnly', '$defs'
]);

const ASSERTIONS = new Set([
  '$ref', 'type', 'const', 'enum', 'required', 'properties', 'patternProperties',
  'additionalProperties', 'items', 'minItems', 'maxItems', 'uniqueItems', 'contains',
  'minLength', 'maxLength', 'pattern', 'minimum', 'maximum', 'minProperties', 'allOf',
  'anyOf', 'oneOf', 'not', 'if', 'then', 'else'
]);

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  return typeof value;
}

function matchesType(value, type) {
  const actual = typeOf(value);
  if (type === 'number') return actual === 'number' || actual === 'integer';
  return actual === type;
}

function deepEqual(a, b) {
  if (a === b) return true;
  if (typeOf(a) !== typeOf(b)) return false;
  if (Array.isArray(a)) {
    return a.length === b.length && a.every((item, index) => deepEqual(item, b[index]));
  }
  if (a && typeof a === 'object') {
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every((key) => deepEqual(a[key], b[key]));
  }
  return false;
}

function resolve(root, ref) {
  if (!ref.startsWith('#/')) throw new Error(`Unsupported $ref ${ref}: only local references`);
  let node = root;
  for (const part of ref.slice(2).split('/')) {
    node = node?.[part.replace(/~1/g, '/').replace(/~0/g, '~')];
  }
  if (node === undefined) throw new Error(`Unresolved $ref ${ref}`);
  return node;
}

// Returns a list of error strings; empty when the instance is valid.
export function validate(schema, instance) {
  const errors = [];
  check(schema, schema, instance, '$', errors);
  return errors;
}

function check(root, schema, value, path, errors) {
  if (schema === true) return;
  if (schema === false) {
    errors.push(`${path}: not allowed`);
    return;
  }

  for (const keyword of Object.keys(schema)) {
    if (!ANNOTATIONS.has(keyword) && !ASSERTIONS.has(keyword)) {
      throw new Error(`Schema keyword "${keyword}" at ${path} is not supported by this validator`);
    }
  }

  if (schema.$ref) check(root, resolve(root, schema.$ref), value, path, errors);

  if (schema.type !== undefined) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.some((type) => matchesType(value, type))) {
      errors.push(`${path}: expected ${types.join(' or ')}, got ${typeOf(value)}`);
      return;
    }
  }
  if ('const' in schema && !deepEqual(value, schema.const)) {
    errors.push(`${path}: must equal ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.some((option) => deepEqual(value, option))) {
    errors.push(`${path}: must be one of ${JSON.stringify(schema.enum)}`);
  }

  if (typeof value === 'string') {
    if (schema.minLength !== undefined && [...value].length < schema.minLength) {
      errors.push(`${path}: shorter than ${schema.minLength}`);
    }
    if (schema.maxLength !== undefined && [...value].length > schema.maxLength) {
      errors.push(`${path}: longer than ${schema.maxLength}`);
    }
    if (schema.pattern !== undefined && !new RegExp(schema.pattern, 'u').test(value)) {
      errors.push(`${path}: does not match ${schema.pattern}`);
    }
  }

  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) {
      errors.push(`${path}: below ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && value > schema.maximum) {
      errors.push(`${path}: above ${schema.maximum}`);
    }
  }

  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${path}: fewer than ${schema.minItems} items`);
    }
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${path}: more than ${schema.maxItems} items`);
    }
    if (schema.uniqueItems) {
      for (let i = 0; i < value.length; i += 1) {
        for (let j = i + 1; j < value.length; j += 1) {
          if (deepEqual(value[i], value[j])) errors.push(`${path}: items ${i} and ${j} are equal`);
        }
      }
    }
    if (schema.items !== undefined) {
      value.forEach((item, index) => check(root, schema.items, item, `${path}[${index}]`, errors));
    }
    if (schema.contains !== undefined
        && !value.some((item) => validate_(root, schema.contains, item))) {
      errors.push(`${path}: contains no item matching ${JSON.stringify(schema.contains)}`);
    }
  }

  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const keys = Object.keys(value);
    if (schema.minProperties !== undefined && keys.length < schema.minProperties) {
      errors.push(`${path}: fewer than ${schema.minProperties} properties`);
    }
    for (const name of schema.required ?? []) {
      if (!(name in value)) errors.push(`${path}: missing required "${name}"`);
    }
    const patterns = Object.entries(schema.patternProperties ?? {})
      .map(([pattern, sub]) => [new RegExp(pattern, 'u'), sub]);
    for (const key of keys) {
      const child = `${path}.${key}`;
      let matched = false;
      if (schema.properties && key in schema.properties) {
        matched = true;
        check(root, schema.properties[key], value[key], child, errors);
      }
      for (const [regex, sub] of patterns) {
        if (regex.test(key)) {
          matched = true;
          check(root, sub, value[key], child, errors);
        }
      }
      if (!matched && schema.additionalProperties !== undefined) {
        if (schema.additionalProperties === false) {
          errors.push(`${path}: unexpected property "${key}"`);
        } else {
          check(root, schema.additionalProperties, value[key], child, errors);
        }
      }
    }
  }

  for (const sub of schema.allOf ?? []) check(root, sub, value, path, errors);
  if (schema.anyOf && !schema.anyOf.some((sub) => validate_(root, sub, value))) {
    errors.push(`${path}: matches none of anyOf`);
  }
  if (schema.oneOf) {
    const count = schema.oneOf.filter((sub) => validate_(root, sub, value)).length;
    if (count !== 1) errors.push(`${path}: matches ${count} of oneOf, expected exactly 1`);
  }
  if (schema.not !== undefined && validate_(root, schema.not, value)) {
    errors.push(`${path}: matches a schema it must not`);
  }
  if (schema.if !== undefined) {
    const branch = validate_(root, schema.if, value) ? schema.then : schema.else;
    if (branch !== undefined) check(root, branch, value, path, errors);
  }
}

function validate_(root, schema, value) {
  const errors = [];
  check(root, schema, value, '$', errors);
  return errors.length === 0;
}
