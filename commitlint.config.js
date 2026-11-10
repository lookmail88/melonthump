module.exports = {
  extends: ['@commitlint/config-conventional'],
  // commitlint's default merge ignores only match the standard
  // capitalized forms ("Merge branch ..."). This repo has merge
  // commits with custom lowercase messages (e.g. the 2026-11-08
  // "merge branch 2.0 into development" merge), which the parser
  // otherwise lints as regular commits and fails with empty
  // type/subject. Ignore merge messages outright.
  ignores: [
    (message) => {
      const text = typeof message === 'string'
        ? message
        : (message && message.header) || '';
      return /^merge\b/i.test(text.trim());
    },
  ],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'test', 'chore', 'ci', 'perf', 'revert'
    ]],
    'subject-case': [2, 'never', ['start-case', 'pascal-case', 'upper-case']],
  },
};
