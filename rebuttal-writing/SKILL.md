---
name: rebuttal-writing
description: >-
  Write, structure, and audit academic conference rebuttals and author responses
  (ICLR, NeurIPS, ICML, CVPR, ACL, OpenReview). Use whenever the user asks to
  analyze peer reviews, plan rebuttal experiments, draft or revise point-by-point
  author responses, align manuscript revisions with rebuttal claims, or format
  responses for OpenReview.
license: MIT
metadata:
  author: Joe
  version: "1.0.0"
---

# Rebuttal Writing

Write point-by-point conference rebuttals that address what each reviewer is actually doubting, keep all supporting evidence inside the response itself, and stay consistent with the revised paper.

For concrete response templates across common critique types, read [references/patterns-and-examples.md](./references/patterns-and-examples.md).

---

## 1. Document Structure and Ordering

Follow this structure for every reviewer unless the venue enforces a rigid form:

1. **Two-sentence opening.** Thank the reviewer for recognizing the paper's strengths and for giving constructive feedback, then state that the manuscript has been revised accordingly and that point-by-point responses follow.
   - Do **not** put a standalone "Global experimental setup" block at the top of the reply before answering anything. Introduce experimental settings inside the specific response where those results first appear.
2. **Answer all Weaknesses first, then all Questions (`W1, W2, ... -> Q1, Q2, ...`).**
   - Never answer only the Questions section, never place `Q` before `W`, and never interleave them out of order (`Q2 -> W1 -> Q1`).
   - If a review writes Weaknesses as unnumbered paragraphs, split them into `W1, W2, ...` in the exact order written by the reviewer so every critique has its own heading.
3. **Summarize what the reviewer is actually asking under each heading.**
   - Use paired headings: `### **W1**` followed by `### **Response to W1**`.
   - Under `### **W1**` (or `### **Q1**`), write **one or two plain sentences** that capture the reviewer's underlying concern.
   - Do **not** paste long verbatim paragraphs from the review (which consume OpenReview character limits and bury the point), and do **not** write vague topic labels such as `"Benchmark"` or `"Ablation"`.
   - Diagnose the real doubt before answering. If a reviewer objects that an evaluation has no human validation, lead with validation evidence rather than procedural details about how prompts were formatted.
4. **Never omit a Question that was already answered earlier.**
   - Reviewers scan the response to check that every `W` and `Q` they wrote is accounted for.
   - When `Q1` is already covered in `W1`, still write `### **Q1**`, summarize the question in one sentence, and under `### **Response to Q1**` write `Please see the response to W1.` (or give a one-sentence direct answer to a specific sub-question in `Q1`, followed by `Please see the response to W1 for full details.`).

Skeleton for one reviewer:

```markdown
## Reviewer XXXX

We sincerely thank the reviewer for recognizing the value of our work and for the thoughtful and constructive feedback. We have carefully revised the manuscript accordingly and provide our point-by-point responses below.

### **W1**

[1–2 sentences summarizing what the reviewer is actually questioning in W1.]

### **Response to W1**

[Direct conclusion + structured evidence and complete tables.]

### **Q1**

[1 sentence summarizing Q1.]

### **Response to Q1**

Please see the response to W1.
```

---

## 2. Self-Contained Evidence (Assume the Reviewer Will Not Read the Revision)

Most conference rules state that reviewers are not required to read the revised PDF. Treat every OpenReview response as a standalone document:

- **Put full tables and numbers directly in the response.** Never write *"All five models improve; per-model results are in Appendix D.4"* while showing only an aggregate mean. Put the per-model breakdown, confidence intervals, and cost or latency columns directly into the response table.
- **Give the takeaway right after each table, with strategic bolding.** Bold one or two key conclusion clauses per section (for example, `**demonstrating that encoder fine-tuning is not necessary for the gain**`) so a skimming reviewer or Area Chair sees the conclusion at a glance.
- **Cite manuscript sections only as a secondary pointer.** After presenting the complete evidence in the response, note briefly where it appears in the revision (`We have incorporated these results into Section 4.5 of the revised manuscript.`). Only point to the PDF alone when the evidence is inherently visual (such as a trajectory figure), and still describe in prose what the figure shows.

---

## 3. Playbooks for Common Reviewer Critiques

When a single Weakness bundles several distinct criticisms, open `Response to W1` with a one-sentence roadmap and answer each part under numbered bold headings (`**1. ...**`, `**2. ...**`, `**3. ...**`).

### A. LLM-as-a-Judge, Self-Constructed Benchmarks, and Lack of Human Validation

Do **not** lead with a small random spot-check (such as 50 sampled answers out of thousands), which looks underpowered. Use a funnel from full-set cross-checking to targeted human inspection:

1. **Multi-model, cross-family cross-check.** Re-score the full evaluation set with additional independent judges, including at least one judge from a different model family that neither generated artifacts nor answered questions. Report:
   - Whether relative rankings hold across all models and judges (with paired confidence intervals).
   - How overall strictness differs across judges (for example, Judge A strictest, Judge B intermediate, Judge C most lenient), showing that threshold shifts change absolute scores without changing rankings.
   - A direct **self-preference check** comparing how the original judge scores its own outputs versus other models' outputs relative to an external judge.
2. **Exhaustive human check on cross-judge disagreements.** Extract **all cases where the judges disagree** and inspect them manually against the rubric and ground truth. State clearly what caused the disagreements (such as partial-credit strictness thresholds), whether any systematic bias appeared, and whether relative rankings changed.
3. **Independent / judge-free validation.** Show empirical checks that rule out benchmark favoritism (for example, a raw-input baseline outperforming standalone processed input on local items) and, whenever available, results on public benchmarks graded by deterministic test suites rather than LLM judges.

### B. Missing Baseline, Confound, or Unfair Comparison

- **Run the natural competitor under matched conditions.** Keep the harness, model, budget, and evaluation protocol identical so only the contested factor changes.
- **When a requested ablation is structurally ill-defined, explain why and run the closest valid control.** Sometimes a reviewer asks for a control that breaks the method's interface or mixes two effects (for example, removing a representation on which the downstream loss is defined, hard-capping tree-traversal calls before leaves are reached, or byte-truncating disjoint module pages). State plainly why that literal modification is ill-defined, then immediately present controlled evidence that answers the underlying concern (such as stratifying existing pairs where `calls(Ours) <= calls(Baseline)`, testing an ablation that makes *more* calls yet scores lower, or fixing per-call retrieval budget).

### C. Overclaiming or Scope Challenges

- **Agree where the reviewer is right and narrow the claim cleanly.** Do not defend wording that goes beyond the data. Write: *"We agree that our evidence supports [exact narrower claim] rather than [broader claim], and we have revised Section X accordingly."*
- **Separate method-specific limitations from field-wide limitations.** Group limitations into **(a) specific to our design** (explain the deliberate trade-off, such as trading universal pixel fidelity for temporal identity stability) and **(b) shared across this class of methods**, noting practical mitigations or future work.

### D. Novelty and Missing Related Work

1. **Classify prior work by pipeline stage or core question.** Give a short taxonomy table showing how adjacent directions differ in objective and which category your work belongs to.
2. **Contrast mechanisms side by side.** Provide a structured comparison table (`Aspect | Prior Family A | Prior Family B | Ours`) across 4–6 concrete dimensions (inputs, training/transfer regime, objective, inference cost), then add quantitative comparisons on shared benchmarks where code or checkpoints exist. If a recent baseline has no public code or checkpoints, state that fact plainly rather than guessing numbers.

### E. Cost, Latency, and Break-Even Questions

- **Show the arithmetic explicitly.** State per-task runtime cost for each condition, one-time construction or pretraining cost, per-query saving, and the resulting break-even range.
- **Be honest when same-model runtime cost increases.** Never claim a break-even point where none exists. If carrying extra context raises per-trial cost within the same model, say so directly and show where cost-effectiveness actually arises (for example, pairing a cheaper model with your method to match or approach a much pricier model at a fraction of its cost, or amortizing one-time setup via cheap incremental updates).

### F. Presentation and Clarity Critiques

- Apologize briefly without being defensive (`We are sorry that our presentation made this section harder to follow than necessary.`), then list 2–3 concrete edits made in the revision: state methodological changes upfront, define core terms before using them, and add a worked example or diagram.

---

## 4. Consistency and `pdfdiff` Discipline

Before finalizing both the rebuttal and any revised manuscript, check three things:

1. **One number per condition everywhere.** Never report two different scores for the same condition across tables or between the paper and rebuttal (for example, mixing original-run numbers with rerun numbers for the same baseline). Pick one canonical source (usually the original paper table for existing conditions) and keep all shared rows identical.
2. **Exact terminology match.** Use the exact condition names from the paper's tables (`Unstructured`, `Structured`, `Source + shell`); if a reviewer used an informal name (`Flat`), write `Unstructured (Flat)` on first mention.
3. **`pdfdiff` safety.** Reviewers and Area Chairs often inspect an automated diff between the original submission and the revised PDF. Do not rewrite original provenance or setup sentences in ways that look evasive next to the original wording, and keep main-text page limits strictly intact.

---

## 5. OpenReview Formatting and Pre-Submission Checklist

OpenReview parses Markdown together with MathJax/KaTeX, which creates silent rendering bugs if unchecked. Run through this checklist on every response file before delivery:

1. **Escape every currency dollar sign as `\$`.** Two bare `$` signs in the same paragraph or table cell (such as `saves $0.05 per query on a $10–200 build` or `$1.03 / $1.25`) cause OpenReview to render all text between them as math in italics with spaces stripped (`0.05perqueryona`). Write `\$0.05`, `\$10–\$200`, and `\$1.03 / \$1.25` everywhere.
2. **Check comment length if the venue caps per-comment characters.** When OpenReview enforces a per-comment limit (commonly 5,000 characters), split cleanly at `### **W...**` or `### **Q...**` boundaries so tables and arguments are never cut mid-thought. Keeping summaries under `W` and `Q` to 1–2 sentences avoids unnecessary splits.
3. **Readable prose pass.** Read the draft once cold as a tired reviewer: prefer plain verbs, unpack stacks of three or more nouns, keep small connectives (`that`, `which`, `because`), and replace defensive or vague phrasing with direct mechanisms and numbers.
4. **Automated check.** Run a quick verification command on the finished Markdown file to catch accidental math spans or leftover placeholders:

```bash
python3 -c '
import pathlib, re, sys
for p in sys.argv[1:]:
    txt = pathlib.Path(p).read_text()
    spans = re.findall(r"(?<!\\)\$[^$\n]+(?<!\\)\$", txt)
    print(p, "total chars:", len(txt), "math spans:", spans)
' response_*.md
```

Every item printed in `math spans` must be genuine LaTeX math (such as `$K=16$` or `$n = 900$`), never prose between two dollar amounts.
