# Maintainers

| Maintainer | Areas |
|---|---|
| @themoriarti | Everything: architecture, releases, CI and the self-hosted runners |

## How changes are reviewed

There is one active maintainer, and the rules say what that allows:

- Every change to `main` goes through a pull request, and the checks of
  `ci.yml` and `crun_build.yml` must pass before it merges.
- The maintainer merges their own pull requests once those checks pass. No
  second person reviews them, and GitHub does not let an author approve their
  own pull request, so no approving review is required.
- A pull request from anyone else needs the maintainer's approving review.
- An architectural change carries an ADR in `docs/architecture/`, linked from
  the pull request.
- The maintainer triages issues and labels, and tags releases.

When a second maintainer is active, a non-trivial change (100 lines or more,
or one that affects an ADR) needs an approving review from a maintainer other
than its author, and branch protection requires one.
