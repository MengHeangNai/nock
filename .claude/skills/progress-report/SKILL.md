---
name: progress-report
description: Generate a document-style HTML progress report from this repo's git history for a given date range (e.g. "last 3 weeks", "Aug 1 to Aug 15", "since last report", "this sprint"). Publishes it as an Artifact using the established Alert List Cloud report template (letterhead, stat strip, numbered sections, weekly grouping). Use whenever the user asks for a progress report, sprint summary, standup report, or "summarize what we did" over some period.
---

# Progress report generator

Produces the report format finalized on 2026-09-03 (Aug 13 – Sep 3 window):
letterhead with a status pill, a 4-tile stat strip, five numbered sections
(Overview / What We Built / Issues Fixed / What's Next / Summary), each a flat
bullet list — no date/week sub-headers on individual items. Reuse
`template.html` in this folder as the starting point every time — don't
redesign it from scratch. It already passed an editorial design pass (Fraunces
+ IBM Plex Sans/Mono, teal/paper palette, light+dark tokens); only the content
changes.

**The audience is a non-developer viewer (a manager or client), not the
engineering team.** Write every bullet as a plain-language feature or outcome
— what changed for someone using the app — never as an implementation detail.
Concretely:
- No code identifiers: no variable/interface/service names, no file names, no
  `monospace` snippets, no commit-type tags (`feat`, `fix`, `refactor`).
- No internal-only changes: renames, debug-log cleanup, validation-logic
  simplification, refactors with no user-visible effect — leave these out
  entirely rather than translating them. If a "technical improvements"
  section would only contain items like this, drop the section (this is why
  the template has 5 sections, not 6 — the original technical-improvements
  section was cut for exactly this reason).
- Bug fixes get described by the symptom a user would have seen and the fact
  it's resolved ("case links no longer break when a number contains a
  comma"), not by the root cause or the file that changed.
- Stat tiles report outcomes (features delivered, issues fixed, weeks
  covered, team members), not dev metrics like raw commit count.
If the user explicitly asks for a developer-facing/technical version instead,
it's fine to include implementation detail — that's a different, opt-in mode,
not the default.

## 1. Resolve the date range

- Explicit dates ("Aug 1 to Aug 15") → use as-is.
- Relative ("last 3 weeks", "this sprint") → resolve against today's date.
- "Since last report" → check memory / ask the user for the last report's end
  date if it isn't obvious from context.
- A recurring schedule ("every Friday", "every 2 weeks") is a request to
  automate delivery, not just to generate one report — that's the `schedule`
  or `loop` skill's job, not this one. Point the user there if they ask for
  recurring delivery; this skill only produces a single report for a range.

## 2. Pull the data

```
git log --since="<start>" --until="<end>" --date=format:'%Y-%m-%d' \
  --pretty=format:'%ad|%an|%s' | cat
```

Then:
- Drop merge commits (`Merge branch ...`).
- Drop junk/placeholder commit subjects (single letters like `f`, `d`, WIP
  noise) — don't report them as work items.
- Group the rest by ISO week within the range, oldest first.
- Classify each by prefix: `feat:` → feature, `fix:` → issue resolved,
  `refactor:`/`chore:` → technical improvement. Commits without a prefix: read
  the subject and place by what it actually describes.
- Also run `git status` — anything uncommitted/in-progress goes in the "Next
  Steps" section, not "Key Work Completed".

## 3. Compute the stat strip

Four tiles, in this order: feature count (grouped, not raw commits) · fix
count · weeks covered · team members. Use real counts — don't round or invent
numbers, and don't substitute raw commit count for feature count (a viewer
doesn't know what a commit is).

## 4. Fill the template

Copy `template.html` to a scratch path, then edit only the content:
- Letterhead: eyebrow (module/repo name), title, period, prepared date,
  branch, status pill text.
- Stat strip numbers.
- Section 02 (What We Built): a single flat bullet list of user-facing
  features, no date/week sub-headers per item — the viewer cares what shipped,
  not which week (grouped/deduped when several commits build one thing —
  don't list every commit 1:1 if three commits are one feature). Weekly
  grouping from git history is still useful internally to sequence and dedupe
  the list, it just doesn't appear as a label in the output.
- Section 03 (Issues Fixed): user-visible bug fixes only, described by symptom.
- Section 04 (What's Next): current uncommitted work + logical next steps.
- Section 05 (Summary): 2-3 sentence summary tying the period together.

Leave the CSS, fonts, seal SVG, and layout structure untouched — that's the
part already designed. If a report spans enough contributors that per-author
attribution would help, that's a deliberate extension, ask first rather than
bolting it on silently.

## 5. Publish

Publish via the Artifact tool (new `file_path`, favicon `🛂` on first publish
only, a fresh `title`/`description` describing the actual period covered).
Don't re-run the artifact-design process — the design is already settled;
just carry it forward with new content.
