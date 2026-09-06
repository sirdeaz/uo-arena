# Working on UO Arena

## An issue comes first, always

**Open a GitHub issue before writing any code.** The issue is the unit of work here, not
the pull request. It is where the problem gets stated, argued about and agreed on, and it
is what makes the history readable later — a PR that appeared from nowhere leaves no
record of why anyone thought the change was worth making.

This holds however small the change looks, and whoever noticed it.

## Plan mode ends at an issue, not at code

**The deliverable of a planning session is an issue.** When plan mode is used, the plan
gets written up as a GitHub issue and the work stops there, for a separate decision about
whether and when to build it.

Approving a plan is not approval to implement it. `ExitPlanMode` means "the plan is
settled" — the next step is filing it, then stopping and saying so.

Do not go from an approved plan straight into changing files, opening a branch, or raising
a PR. Wait to be asked.

## What an issue should carry

Match the ones already in the repo (see #1–#9 for the house style):

- The problem, in terms of what a player or a maintainer actually experiences.
- Evidence, as `file.gd:line` references — the real code, not a paraphrase of it.
- Why it matters *for this game specifically*, not in the abstract.
- A proposal, held loosely, with the trade-offs named.
- A "done looks like" section that someone else could check against.
- A "watch out for" section when there are traps — a sealed gap, a silent fallback, a test
  that cannot catch the thing.

Prefer several small issues over one that bundles unrelated work, and cross-reference them
when one depends on another.

## Then, and only when asked

Implementation goes on the branch named in the session's instructions, and the PR body
says `Closes #N`. If a PR for that branch has already merged, restart the branch from the
current `main` rather than stacking on merged history.

## Commands

```bash
./run_tests.sh          # headless suite; expects a clean pass
./run_game.sh           # the offline practice harness
./build.sh              # native + browser builds
```

Godot is found via `$GODOT_BIN`, then `godot4`/`godot` on `PATH`. The suite needs the
project imported first, and a fresh clone needs **two** import passes — the first reports
errors for class names not yet registered.

## Conventions worth not relearning

- **Tests use real objects, not mocks**, and there is no framework: `tests/test_*.gd`
  subclassing `TestCase`, discovered by `tests/test_main.gd`. Only four assertions exist
  and the message argument is mandatory — write it as why the behaviour matters.
- **Pull the decision into a static function** so it can be tested without a scene tree.
  This is the strongest convention in the codebase; `ArenaView.shape_polygon` and
  `Fighter.movement_direction_toward` both exist in that shape for that reason.
- **`server/` holds no rendering code**, so the Dedicated Server export stays clean.
- **Every colour goes through `client/palette.gd`.** One meaning per colour, and
  `tests/test_palette.gd` fails on a raw hex literal anywhere in `client/`. A variant of an
  existing signal should be a new named *alpha*, not a new hue.
