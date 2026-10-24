# Principles (always apply)

- **Small PRs.** One concern per PR, about 200 changed lines or fewer. Each PR must deploy and revert on its own.
  - Split into steps (secrets, then app, then cutover, then cleanup) rather than bundling.
  - *Why:* every PR is reviewed by a human. Big mixed PRs stall and hide mistakes.
- **Declarative over one-time Jobs.** Prefer an operator CR, the software's own declarative config, or a reconciling controller.
  - A Job or Argo/Helm hook needs a stated reason in the PR, plus the follow-up that would replace it.
  - *Why:* Jobs run once and drift. Reconciled state self-heals.
- **Order over sprawl.** Put config only in its designated directory (see `CLAUDE.md`). Template or reuse an existing pattern rather than copy-paste near-identical manifests. Don't add new top-level dirs.
- **Root-cause fixes.** Use the platform's own capability (operator, IdP, ESO) rather than a workaround.
- **Public repo.** No internal tracker or task IDs, and no secret values, in files, commits or PR text.
