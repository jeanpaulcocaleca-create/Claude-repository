# AGENTS.md · rules for every AI agent in this repository

Codex, ChatGPT, Claude and any other agent read this file first.

This repository holds two projects for the same owner in Santa Elena, Monteverde, Costa Rica.

| Project | Where it lives | Its rules |
|---|---|---|
| Hanging Garden Café system (Canopy OS: POS, kitchen, menu, accounting) | `website/`, `supabase/`, `docs/` on branch `claude/hanging-garden-coffee-proposal-1m8zd4` (pull request #1) | `CLAUDE.md` on that branch |
| Basecamp Monteverde website: the lodge only, with the café and tours as outbound links (planning stage, no site code yet) | `basecamp/` | `basecamp/CODEX.md` |

## Never (every agent, every project)

- Never run the "Publish website (PRODUCTION · manual only)" workflow. Never create or move `v*` release tags. Never change GitHub Pages, branch protection, environments or secrets. Only the owner publishes.
- Never push to or rewrite the `gh-pages` branch. It is the live café website.
- Never commit passwords, PINs, API keys, tokens, database connection strings or guest personal data. This repository is public.
- Never force-push or rewrite history on a branch another agent works on. Bring changes in with a merge.
- Never spend money, open accounts, change DNS, send messages to guests or publish anything on the owner's behalf without the owner's explicit approval.

## Who decides (Basecamp project)

- **Owner**, GitHub account `jeanpaulcocaleca-create`: the only one who approves scope, prices, design, spending and publishing.
- **ChatGPT / Codex**: overseer and reviewer. Reads, reviews, asks, proposes. Does not push commits to Claude's branch. If Codex writes code, it opens its own pull request.
- **Claude**: builder. Writes code and documents on branch `claude/brave-archimedes-ar8uc1` and answers on the pull request.

The full working agreement, message formats and current status are in `basecamp/CODEX.md`.

## Code Review Rules

Codex applies these when reviewing pull requests that change files under `basecamp/`.

1. **No recurring fees.** Flag any feature that needs a membership, monthly plan or subscription. Per-use fees (card processing, per-message WhatsApp, per-request AI) are allowed only if listed in the cost table of `basecamp/CODEX.md`.
2. **No copied brands.** Flag logos, photos, wording or trademarks taken from Marriott, Hilton or any other company. Copying layout patterns is fine.
3. **Facts must match.** Flag any price, policy, room detail, tour detail or claim on a page that does not match `basecamp/RESEARCH.md` or an owner decision in `basecamp/CODEX.md`.
4. **No secrets or guest data** anywhere in the repository.
5. **Phones first.** Flag pages that break at 360 px wide, images without alt text, and English text without its Spanish twin.
6. **Stay in the lane.** Flag any change to `.github/workflows/`, `website/`, `supabase/` or `gh-pages` made as part of Basecamp work.
7. **Build gate.** While `basecamp/CODEX.md` says "Build status: ON HOLD", flag any website code added under `basecamp/`.
