# Project notes: upgrading mizerCourse

## State as of 2026-08-19

Installed: mizer 3.2.1.9004 (a dev version that already carries the 3.3
changes), mizerExperimental 3.2.0.

`understand/*.qmd` were upgraded to the 3.3 idiom:

- `power = 0` → `biomass = FALSE`, `power = 2` → `biomass = TRUE, per_log_size = TRUE`
  in `plotSpectra()`, `plotSpectra2()`, `plotCDF()` and `animateSpectra()`.
  Verified figure-for-figure that this is behaviour-preserving.
- `getPredKernel()` → `pred_kernel()`, `getReproductionLevel()` → `reproduction_level()`.
  In `predation-growth-and-mortality.qmd` the local variable that used to be called
  `pred_kernel` was renamed to `kernel` so it does not shadow the function.

`build/*.qmd` were checked and upgraded on 2026-08-19 (same session style as
above). All five execute cleanly under mizer 3.2.1.9004:

- `power = 2` → `biomass = TRUE, per_log_size = TRUE` in `plotlySpectra()`
  (`create-first-model.qmd` ×4, `refine.qmd` ×2). `power` is still accepted and
  is *not* deprecated — it is documented as an alternative to the other two —
  but the new idiom matches `understand/`. Verified `return_data` identical.
- `getReproductionLevel()` → `reproduction_level()` in `tune-resilience.qmd`
  (5 places incl. prose). This one *did* emit a lifecycle deprecation warning
  into the rendered page.
- `create-first-model.qmd` prose named `matchYields()`, removed in 3.3.
  Rewritten to point at `mizerExperimental::matchYield()` (adjusts catchability,
  not abundance).
- `landings.qmd` had a stray bare URL pasted between two chunks; removed.

`use/*.qmd` were checked and upgraded on 2026-08-19. All seven files render
without errors and the four content pages now render with no deprecation
warnings at all:

- `further-scenarios.qmd` carried most of it:
  `power = 2` → `biomass = TRUE, per_log_size = TRUE` in `plotlySpectra()`
  (verified identical via `plotSpectra(..., return_data = TRUE)`);
  `getReproductionLevel()` → `reproduction_level()` (this one warned);
  `params@gear_params` → `gear_params(params)`;
  `params@linecolour` / `scen@params@linecolour` → `getColours(params)`;
  three `qplot()` calls → `ggplot() + geom_point() + labs()` (ggplot2 warned);
  `size =` → `linewidth =` on `geom_line()`/`geom_hline()` (ggplot2 warned).
  All the affected figures came out byte-identical, so every one of these is
  behaviour-preserving.
- `running_a_simulation.qmd`: `head(sim@effort)` → `head(getEffort(sim))`,
  and the sentence about "the `effort` slot" reworded to name `getEffort()`.
  The file already used `getEffort()` a few sections earlier.
- `exploring_the_simulation_results.qmd`: prose still called the abundance
  array `n` (the pre-3.0 slot name); reworded to name `N(sim)`. No code change.
- `a_multispecies_model_of_the_north_sea.qmd`: `inter` → `NS_interaction`.
  `inter` is a deprecated alias (mizer ≤ 2.3) but is *data*, so it never warns —
  grep for it rather than expecting the render to tell you. This was the only
  occurrence in the whole repo.
- `change-resources.qmd` and `fishing-scenarios.qmd` are "In preparation" stubs
  with no R code, and are not in the `_quarto-website.yml` render list.
  `quarto render use/change-resources.qmd` therefore writes a standalone
  `use/change-resources.html` **next to the source** instead of into `docs/`;
  delete it afterwards.

### The North Sea LFI figure changed, and that is the 3.3 bug fix

`plot_ns_indicators-1.png` in `a_multispecies_model_of_the_north_sea.qmd` is the
one figure whose *content* moved. The committed version had the unexploited LFI
(`lfi0`) and its 0.8 reference line both sitting at 0 — that was the
`getProportionOfLargeFish()`-on-a-`MizerParams` bug (weights recycled down the
columns for all but the first species), fixed in 3.3. `lfi0` is now ≈ 0.485 and
the reference ≈ 0.388, which is what the surrounding prose always assumed. The
closing sentence was tightened to match: the LFI is below the reference for
1967–≈2004 and rises above it only at the very end.

`library(mizerExperimental)` in `further-scenarios.qmd` **is** still needed —
`plotYieldVsF()` is the one function there that mizer does not export.

### `collect-parameters.qmd` now takes `w_inf` from von Bertalanffy fits

Changed on request 2026-08-19. It used to estimate `w_inf` from the largest fish
in `catch.csv`, falling back to FishBase's `Length` (max length) for the 5
species with no catch data. It now takes the **median of `TLinfinity` over the
FishBase "popgrowth" table** (`rfishbase::popgrowth()`), which is the asymptotic
length from published von Bertalanffy fits, converted to total length. All 17
species have popgrowth entries, so the catch-data path and the `l_max` column
are gone; the column is now `l_inf`.

Use `TLinfinity`, not `Loo`: `Loo` is in whatever length measure the study used
(the `Type` column — TL/SL/FL), while the `a`/`b` from FishBase's "estimates"
table are for total length.

The resulting `w_inf` is 2–8× smaller than the old max-size values for most
species (Cod 41 kg → 13 kg, Boarfish 279 g → 35 g; Monkfish is the one that went
up). This is expected — max observed length overestimates the vB asymptote — and
`l_mat/l_inf` stays in the plausible 0.39–0.81 range for all 17 species.

Two knock-on edits were needed:

- `create-first-model.qmd` step 8 needed a **third** `calibrateBiomass() |>
  matchBiomasses() |> matchGrowth() |> steady()` round. With two rounds the
  smaller `w_inf` left biomasses 0.84–1.01 of observed; with three it is
  0.94–1.02, which is what the surrounding prose claims.
- `landings.qmd` pointed at the (now deleted) catch.csv download chunk in
  `collect-parameters.qmd#asymptotic-size`; repointed at its own chunk.

**Still stale:** the committed `cel_model_refined.rds` and
`cel_model_landings.rds` still carry the old max-size `w_inf` (Cod ≈ 41 kg).
They are written by `eval=FALSE` chunks, i.e. by hand through `tuneParams()`, so
only the user can regenerate them. `refine.qmd` and `landings.qmd` still render,
they just start from a model built on the old sizes.

### How these were checked

`use/` was checked with `quarto render <file>.qmd --cache-refresh`, one file at
a time. Rendering a single file ignores `freeze:` and `--cache-refresh` defeats
the knitr cache, so every chunk really re-executes — confirm it by looking for
the `n/N [chunk-label]` progress lines in the render log. Then grep the produced
`docs/use/*.html` for `warning|deprecat`, since knitr writes warnings into the
page rather than to stderr. (The `Error: false,` hit in every page is the giscus
JSON in the header, not a real error.)

`understand/` and `build/` were checked differently, before that was worked out.
Not with `quarto render` (freeze + cache would have masked everything). Instead
`knitr::knit()` per file with `cache = FALSE`, `error = FALSE`, cwd `build/` and
`fig.path` pointed at a scratch dir. Note that this *executes* the tutorials, so
it rewrites `build/celtic_species_params.rds` and `build/cel_model.rds`. FishBase
drifts between queries, so `celtic_species_params.rds` will show a small diff
even when nothing in the tutorial changed; `git checkout` it unless you meant to
update it.

## Things to know about this repo

- Rendering config lives in `_quarto.yml` (`profile: default: website`, which
  selects `_quarto-website.yml`), with `execute: cache: true` **and**
  `freeze: true`.
- knitr caches (`understand/*_cache/`) are per-chunk, so after editing a chunk
  whose *downstream* chunks are unchanged, delete the file's `_cache/`
  directory before rendering. They are gitignored and regenerate.
- `quarto render a.qmd b.qmd` fails in this project ("withBinaryFile: does not
  exist"). Render one file at a time.
- Rendering a single file does **not** refresh `_freeze/`. Staleness there is
  harmless — the next full `quarto render` just re-executes that file.
- A full `quarto render` re-executes every changed source, so check
  `git status` first: uncommitted edits elsewhere (e.g. `build/`) would get
  baked into `docs/`.

## Chunk labels

`understand/single-species-spectra.qmd` is the only file whose chunks had
descriptive `#| label:` lines before commit 95095ce added
`{r single-species-spectra-N}` header names to every chunk in the repo. The two
collided and knitr warned 45 times, "Duplicated chunk option(s) 'label' in both
chunk header and pipe comments". Fixed by stripping the header names there and
keeping the `#| label:` lines: the pipe label is the one knitr actually uses, so
that keeps the `docs/.../figure-html/` filenames (`plot-psi-1.png` and friends)
stable. Every other file has header names only and is unaffected.

When adding a chunk to that file, write `` ```{r} `` plus a `#| label:` line;
do not name the chunk in the header.

## mizerExperimental

Of the functions the `understand/` tutorials use, only `plotDeath()` and
`plotlyDeath()` (in `species-interactions.qmd`) still need mizerExperimental.
`plotSpectra2()`, `plotDiet()`, `plot2()`, `addPlot()`, `animateSpectra()` and
`steadySingleSpecies()` are all exported by mizer now, so the
`library(mizerExperimental)` call in the other three tutorials is redundant.
Left in place deliberately — not changed without the user asking.
