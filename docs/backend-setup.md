# Backend Setup

## Purpose
`feedback-hub` can run without automated curation.

If you want automated curation, configure a backend adapter that can send prompts to an LLM CLI or API and return promotion instructions in the expected format.

## Public Contract
The sync runner expects a backend adapter script with this contract:

```text
<backend_script> <prompt_file> <output_file> <repo_root>
```

The adapter should write one of these line types to the output file:
- `PROMOTE<TAB>project<TAB>source_relative_path<TAB>destination<TAB>copy|move<TAB>reason`
- `NOOP<TAB><reason>`
- `DEFER<TAB><reason>`

## What This Means For You
You can wire `feedback-hub` to:
- an LLM CLI
- an HTTP API wrapper
- a local model runner
- a remote model service

The public product does not assume any one provider.

## Setup Pattern
1. Write or choose a backend adapter script.
2. Point the sync runner at that adapter.
3. Verify that the adapter can read a prompt file and write a valid output file.
4. Use automated curation only after that contract works locally.

## Non-Goals
- This document does not prescribe one required vendor.
- This document does not guarantee a specific bundled provider configuration.
- This document does not expose private operator defaults.
