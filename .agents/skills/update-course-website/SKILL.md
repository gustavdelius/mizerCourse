---
name: update-course-website
description: Rebuild the published mizer course website (the Quarto output in docs/, served by GitHub Pages) after tutorial sources change. Use whenever the user asks to rebuild, re-render, regenerate, refresh or publish the course website, a course page or docs/, to "rebuild the page affected by PR #N", or to update the website for a branch — and whenever a PR or commit touches *.qmd files, _quarto*.yml, styles.css or the data files the tutorials read, even if the user doesn't mention Quarto or docs/. Covers working out which pages are affected (including the build/ chain through saved .rds files), rendering on a PR branch without disturbing the main checkout, checking the rendered output, and committing it as "Update course website". Not for writing or editing tutorial content or mizer code; use the mizer task skills for that.
---

# Updating the course website

The site at <https://mizer.course.sizespectrum.org> is the Quarto project in
this repository, rendered into `docs/`. GitHub Pages serves `docs/` straight
from `master` (a legacy Pages build, no CI). Nothing rebuilds `docs/`
automatically: the HTML committed on `master` is exactly what students see. A
change to a tutorial is not live until someone renders it and commits the
output.

## What is tracked

- `docs/` is tracked: it is the published site.
- `_freeze/`, `*_cache/` and the `<dir>/*_files/` folders next to the sources
  are git-ignored local scratch.
- The data the tutorials read is tracked: `build/*.rds`, `build/*.csv`,
  `use/*.rds`, `understand/size-data.rds`. Rendering rewrites some of these
  (see step 1).
- The default Quarto profile is `website` (`_quarto-website.yml`). The `book`
  profile (`_quarto-book.yml`, a PDF into `docs/book/`) is not published. Leave
  it alone unless asked.

`_quarto.yml` sets `execute: freeze: true`. This cuts both ways:

- Rendering a named file or directory (`quarto render understand/foo.qmd`)
  always executes its code, whatever the freeze setting.
- A whole-project `quarto render` never re-executes a page that already has
  frozen results, even when its source changed. A full render on its own would
  therefore publish stale output for exactly the pages you changed.

## 1. Work out which pages are affected

List the changed files: `gh pr view N --json files,headRefName,state` for a PR,
or `git diff --name-only <base>...<branch>`. Then map them to pages:

| What changed | What to render |
|---|---|
| `<dir>/<page>.qmd` | that page |
| a data file in `build/`, `use/` or `understand/` | the pages that read it |
| a heading that other pages link to | the pages whose links now break (the check in step 4 finds these) |
| `_quarto.yml`, `_quarto-website.yml`, `styles.css` | every page, because the navbar, sidebar and header script are baked into each HTML file: a full render (step 3b) |
| a new page | first add it to `project.render` and `sidebar.contents` in `_quarto-website.yml` (and to the chapters in `_quarto-book.yml`), then do a full render |

A page that only gains a link *to* another page does not make the target page
need re-rendering, as long as the target's heading already exists.

**The build/ tutorials form a chain through tracked files that rendering
rewrites.** At the time of writing:

- `collect-parameters` saves `build/celtic_species_params.rds`, which
  `create-first-model` reads.
- `create-first-model` saves `build/cel_model.rds`, which `refine` reads.
- `landings` reads `cel_model_refined.rds` and `tune-resilience` reads
  `cel_model_landings.rds`. Both files are saved in `eval=FALSE` chunks, so
  rendering never regenerates them. They change only when someone saves them by
  hand.

So a change to `collect-parameters` means rendering `collect-parameters`, then
`create-first-model`, then `refine`, in that order. Chunks change, so re-derive
the chain before relying on it:

```bash
grep -n -E "saveRDS\(|saveParams\(|saveSim\(|readRDS\(|readParams\(|readSim\(|read\.csv\(" */*.qmd
```

For each hit, check the enclosing chunk header for `eval=FALSE`. Only evaluated
chunks take part in the chain.

**Some evaluated chunks download from GitHub `master`.** They overwrite the
local tracked file with master's copy. At the time of writing these are
`landings-3` (`build/catch.csv`) and `further-scenarios-25` (`use/sim0.rds`).
Re-find them with:

```bash
grep -n 'download.file("http' */*.qmd
```

Keep the hits whose chunk header lacks `eval=FALSE`. This has two consequences:

- Rendering those pages needs network access.
- If the branch changes one of those files, the render uses master's version and
  overwrites the branch's version on disk. Restore it with
  `git checkout -- <file>`, and tell the user the page cannot show the new data
  until the file is on master.

## 2. Render on the right branch

**For a PR, the rebuild goes on the PR branch** as its own commit after the
source commits, before the PR is merged. PRs #9 and #11 did this, and their
descriptions said "Sources only… `docs/` left to be regenerated". For changes
made directly on `master`, or a PR that is already merged, render on an
up-to-date `master`.

If the branch is not the one checked out, **do not switch the main checkout.**
Make a worktree in the scratchpad instead:

```bash
git fetch origin <branch>
git worktree add <scratchpad>/pr<N> <branch>
```

The main checkout is the user's working copy. Their live R session is connected
through `.mcp.json`, and several other agent config files are tracked on
`master` but missing from older branches, so checking out such a branch deletes
them from disk. A worktree also leaves their untracked `_freeze/` and caches
alone.

Before rendering, check that the local branch matches the remote:
`git rev-list --left-right --count <branch>...origin/<branch>` should print
`0	0`.

## 3a. Render the affected pages

From the root of the checkout you are rendering in, render one page at a time,
in dependency order:

```bash
quarto render understand/predation-growth-and-mortality.qmd --cache-refresh > ../render.log 2>&1
```

- Run it in the background. Pages with simulations take minutes.
- Use the shell, not the user's live R session. Quarto starts its own R
  process, and running the render through their session would block their
  console.
- `--cache-refresh` is cheap insurance against stale knitr caches in old
  `*_cache/` folders.
- A single-page render also updates that page's entries in `docs/search.json`
  and `docs/sitemap.xml`. A content-only change needs no full render.
- **Check that each render succeeded**: exit status 0, and `Output created:` at
  the end of the log. A failed render leaves the old HTML in `docs/` untouched,
  so the step 4 check would pass on the stale page without checking anything.
- A chunk can fail even though nobody touched it, when the installed mizer has
  changed an API since the page was last rendered. The page is then broken for
  students too. Find the fix with the upgrade-mizer-code skill, and confirm the
  released CRAN version behaves the same, not just the installed development
  version. Commit the fix as its own source commit and say so in the PR
  description.

Record the versions the figures were made with, for the commit message:

```bash
quarto --version
Rscript -e 'cat(format(packageVersion("mizer")), format(packageVersion("mizerExperimental")), "\n")'
```

If they differ from the versions the PR says it was checked with, tell the
user.

## 3b. Full render (site-wide changes only)

1. Render each page whose source changed on its own (step 3a), so that its
   frozen results are fresh.
2. Run `quarto render` from the root.

In a fresh worktree there is no `_freeze/`, so every page executes: slow, and it
needs network access. To speed this up you can first copy the main checkout's
`_freeze/` into the worktree. Then check the result: on a page whose source did
not change, the diff should be confined to shared markup (navbar, sidebar,
`<head>`). If a figure or a printed result changes on such a page, the copied
freeze was stale, so render that page on its own.

## 4. Check the output

For each rendered page, run the bundled check from the root of the checkout
that was rendered:

```bash
bash <skill-dir>/scripts/check-rendered-page.sh understand/predation-growth-and-mortality [base-ref]
```

`<skill-dir>` is the absolute path this skill was loaded from. A worktree of a
branch cut before this skill was committed does not contain the skill, so a
relative path would not find the script there. `base-ref` defaults to `HEAD`,
the last committed version of the page.

The script reports:

- R warnings or errors in the page that were not in the base version. Any new
  one needs explaining.
- Figure files that the page no longer references. Delete them, or they get
  published as junk.
- Relative links or `#anchors` that don't resolve.
- Tracked files outside `docs/` that are now modified.

Then check by eye. **Open every new or changed figure** with Read and confirm it
shows what the surrounding text says it shows: a page can render without errors
and still be wrong.

`git status --short` should list only the following:

- `docs/<dir>/<page>.html` and `.llms.md`
- the page's figure PNGs
- `docs/search.json` and `docs/sitemap.xml`

Small byte changes to existing PNGs are normal redraw noise. If rendering
changed a data file, commit it only when that change is intended. For example,
a PR that changes `collect-parameters` should also update the saved species
params. Otherwise restore the file.

## 5. Commit, push, clean up

Commit `docs/` (plus any intended data file) on the branch:

```
Update course website

Re-render <pages> for <what changed>.
Rendered with Quarto <x>, mizer <y>, mizerExperimental <z>.
```

- **Push:** pushing updates the PR. Ask first unless the user has already asked
  you to push.
- **Merge:** don't merge the PR. Merging is what publishes the site, and that
  is the user's call.
- **Clean up:** afterwards, remove the worktree from the main checkout with
  `git worktree remove <path>`.
