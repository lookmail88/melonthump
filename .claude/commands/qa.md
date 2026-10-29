---
description: Run QA verification on a branch using the qa subagent and the qa-testing skill
argument-hint: [branch-name]
---

Run QA on the branch named in $ARGUMENTS, following the qa-testing skill (.claude/skills/qa-testing/) exactly.

Steps:
1. If $ARGUMENTS is empty, ask me which branch to test and stop.
2. Delegate the run to the qa subagent with this brief: "Target branch: $ARGUMENTS. Fetch origin, identify the branch's tip commit and its base branch (this repo's development branch), sync your checkout/worktree to the branch tip, then execute the qa-testing skill end to end: build/test gate first, requirement-by-requirement checklist (requirements source: the branch's PR if one exists, otherwise the diff plus the repo's design/requirements docs), evidence for every failure, severity grading, and the skill's QA Report format ending with a Not covered section."
3. When the subagent returns, present its QA Report to me unchanged in substance — do not soften verdicts, drop findings, or upgrade a partial result into a pass. If the report is missing the commit hash, the checklist, or the Not covered section, send it back to complete them before showing me anything.
4. Do not fix any finding yourself in this command. If I want fixes, I will say so separately.
