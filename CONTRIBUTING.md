# Contributing

## Scope
Public `main` is the stable, public-safe shell of `feedback-hub`.

Contributions here should improve the public shell without introducing:
- private project names
- absolute local paths
- private support-tool assumptions
- internal-only operating detail

## Before You Change Anything
1. Read [README.md](README.md).
2. Read the public docs in `docs/`.
3. Run the canonical verifier:

```bash
./scripts/verify.sh
```

## Contribution Expectations
- keep changes small and reviewable
- preserve the standalone public shell
- document architecture or workflow changes in the same change
- keep public wording understandable to a technically literate stranger
- avoid adding provider-specific assumptions to public onboarding

## Public/Private Boundary
Do not add internal support-system artifacts to public `main`.

Examples that do not belong here:
- internal control files
- private repo inventory
- absolute workstation paths
- private runtime state or logs
- raw project feedback or internal curated learnings content

## Change Quality
Before opening a pull request:
1. run `./scripts/verify.sh`
2. update docs if behavior changed
3. confirm the change is safe to publish
4. make sure AI-assisted changes were human-reviewed before submission

## Pull Requests
- explain the problem being solved
- explain any public-facing behavior changes
- call out docs or architecture updates explicitly
- keep unrelated cleanup out of the same PR when possible
