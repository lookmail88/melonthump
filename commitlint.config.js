module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [2, 'always', [
      'feat', 'fix', 'docs', 'style', 'refactor',
      'test', 'chore', 'ci', 'perf', 'revert'
    ]],
    'subject-case': [2, 'never', ['start-case', 'pascal-case', 'upper-case']],
  },
};
