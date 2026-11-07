// PostgreSQL 최상위 문장만 분리. 문자열·주석·달러 인용 안의 ; 는 유지.
export function splitStatements(sql) {
  const statements = [];
  let start = 0, i = 0, quote = '', dollar = '', block = 0, line = false, escaped = false;
  while (i < sql.length) {
    const c = sql[i], next = sql[i + 1];
    if (line) { if (c === '\n') line = false; i++; continue; }
    if (block) {
      if (c === '/' && next === '*') { block++; i += 2; }
      else if (c === '*' && next === '/') { block--; i += 2; }
      else i++;
      continue;
    }
    if (dollar) {
      if (sql.startsWith(dollar, i)) { i += dollar.length; dollar = ''; }
      else i++;
      continue;
    }
    if (quote) {
      if (escaped && c === '\\') { i += 2; continue; }
      if (c === quote && next === quote) { i += 2; continue; }
      if (c === quote) quote = '';
      i++; continue;
    }
    if (c === '-' && next === '-') { line = true; i += 2; continue; }
    if (c === '/' && next === '*') { block = 1; i += 2; continue; }
    if (c === "'" || c === '"') {
      quote = c;
      escaped = c === "'" && /[eE]/.test(sql[i - 1] || '') && !/[\w$]/.test(sql[i - 2] || '');
      i++; continue;
    }
    if (c === '$' && !/[\w$]/.test(sql[i - 1] || '')) {
      const tag = sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/)?.[0];
      if (tag) { dollar = tag; i += tag.length; continue; }
    }
    if (c === ';') { statements.push(sql.slice(start, i + 1)); start = i + 1; }
    i++;
  }
  if (quote || dollar || block) throw Error('종료되지 않은 SQL 인용/주석');
  const remainder = stripLeadingComments(sql.slice(start)).trim();
  if (remainder) throw Error('세미콜론 없는 SQL 문장: ' + remainder.slice(0, 80));
  return statements;
}
export function stripLeadingComments(sql) {
  let rest = sql.trimStart();
  while (rest.startsWith('--') || rest.startsWith('/*')) {
    if (rest.startsWith('--')) { const end = rest.indexOf('\n'); rest = end < 0 ? '' : rest.slice(end + 1).trimStart(); }
    else {
      let depth = 1, i = 2;
      while (i < rest.length && depth) {
        if (rest.startsWith('/*', i)) { depth++; i += 2; }
        else if (rest.startsWith('*/', i)) { depth--; i += 2; }
        else i++;
      }
      if (depth) throw Error('종료되지 않은 SQL 주석');
      rest = rest.slice(i).trimStart();
    }
  }
  return rest;
}
