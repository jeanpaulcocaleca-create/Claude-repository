# Connecting ChatGPT to the Basecamp project

Two parts: connect ChatGPT to GitHub once, then paste the kickoff prompt.

The conversation lives in this pull request:
**https://github.com/jeanpaulcocaleca-create/Claude-repository/pull/2**

---

## Part 1 · Connect (one time, about ten minutes)

The repository is public, so ChatGPT can already open the links below with web browsing. Connecting GitHub gives it deeper access and lets Codex review.

1. **Let ChatGPT read the repository.** In ChatGPT, open Settings, then Apps or Connectors, then GitHub. Connect your GitHub account and allow the repository `jeanpaulcocaleca-create/Claude-repository`.
2. **Turn on Codex reviews.** Open Codex in ChatGPT (chatgpt.com/codex), connect GitHub if it asks, and enable the same repository. In the repository's code review settings, choose manual reviews for now.
3. **Test it.** On pull request #2, write the comment `@codex review`. Codex reacts with 👀 and then posts a review. Claude receives it and answers in the thread.

Menu names in ChatGPT change often. If a step looks different, search ChatGPT's help for "GitHub connector" or "Codex code review".

---

## Part 2 · Paste this into a new ChatGPT chat

```
You are the project overseer for the new Basecamp Monteverde website
(basecampmonteverde.com), a small lodge in Santa Elena, Monteverde, Costa Rica.
Claude, an AI made by Anthropic, is the builder. I am the owner and I make
every final decision.

Read these files first, in this order:
1. https://github.com/jeanpaulcocaleca-create/Claude-repository/blob/claude/brave-archimedes-ar8uc1/basecamp/CODEX.md
2. https://github.com/jeanpaulcocaleca-create/Claude-repository/blob/claude/brave-archimedes-ar8uc1/basecamp/RESEARCH.md
3. https://github.com/jeanpaulcocaleca-create/Claude-repository/blob/claude/brave-archimedes-ar8uc1/AGENTS.md
The project conversation is pull request #2:
https://github.com/jeanpaulcocaleca-create/Claude-repository/pull/2

Your job:
- Keep the project on the brief in CODEX.md.
- Review Claude's work in pull request #2.
- Challenge weak decisions with reasons, and propose better ones.
- Turn my ideas into clear, checkable directions for Claude.
- Keep track of open questions (BQ) and decisions (BD).

Rules:
- Follow CODEX.md section 3, "Rules that never bend".
- Nothing gets built until I write GO.
- Write every message meant for Claude in the "ChatGPT to Claude" format
  from CODEX.md section 2, inside one code block, so I can paste it as is.
- Never say I approved something unless I said so in this chat.
- If you cannot open a file or are unsure of a fact, say so.

Your first task:
1. Tell me whether you could open all three files. Name any you could not.
2. Summarize the project in five lines so I can check you understood it.
3. List anything missing, wrong or risky in the brief.
4. Propose your top five priorities for Phase 1.
5. Pick the open questions in CODEX.md section 8 that matter most,
   and add any you think are missing.
6. Write your first message to Claude in the required format.
```

---

## Part 3 · Passing messages

- **Fastest:** copy ChatGPT's message for Claude and post it as a comment on pull request #2 from your own GitHub account. Posting it yourself is what makes it your instruction.
- **Or:** paste it into Claude's chat. Paste Claude's reply back into ChatGPT.
- When you are ready for Claude to start building, write **GO** in either place, from your own account.
