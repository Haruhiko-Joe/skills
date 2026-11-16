# Rebuttal Patterns and Examples

Concrete structural patterns distilled from successful conference rebuttals. Adapt the structure and tone to the paper at hand; never copy domain numbers.

---

## Pattern 1: Opening + `W -> Q` Ordering + Cross-Referencing Covered Questions

Keep the opening to two sentences, summarize what the reviewer is actually questioning under each `W` and `Q`, embed the full table in `W`, and keep covered `Q`s concise so the reviewer sees zero omissions and zero walls of repeated text.

```markdown
### Reviewer GXCW

We sincerely thank the reviewer for recognizing the value of our work and for the thoughtful and constructive feedback. We have carefully revised the manuscript accordingly and provide our point-by-point responses below.

### **W1**

Table 1 does not separate the proposed representation from additional encoder fine-tuning; the transport cost is a reasonable design choice rather than a standalone contribution.

### **Response to W1**

Thank you for identifying these ambiguities. First, we added an ablation that freezes all encoder blocks and trains only the decomposition module:

| Representation | Benchmark A (%) | Benchmark B (%) | Benchmark C (%) |
| --- | ---: | ---: | ---: |
| Pretrained baseline | 52.8 | 80.5 | 65.9 |
| Ours, w/o encoder fine-tuning | 56.3 | 82.9 | 66.1 |
| Ours, with encoder fine-tuning | 56.1 | 83.1 | 66.6 |

The frozen-encoder variant still improves over the baseline across all three benchmarks, **demonstrating that encoder fine-tuning is not necessary for the gain**. Moreover, fine-tuning uses the same pretraining dataset and receives gradients solely from the decomposition objective, so it refines object awareness rather than introducing external data.

Second, we agree that our experiments do not establish superiority over every alternative displacement-aware cost. **Our transport cost is one natural implementation enabled by the mask interface rather than a standalone planning loss.** We have revised Section 3 to state this scope explicitly.

### **Q1**

Comparison with other displacement-aware costs.

### **Response to Q1**

Please see the response to W1. We agree that the supported claim is that **a displacement-aware cost on masks is more suitable than pointwise $\ell_1$**, and we have revised our wording accordingly.
```

---

## Pattern 2: Multi-Judge Cross-Check + Exhaustive Human Check on Disagreements

When reviewers question an LLM judge or a self-constructed benchmark ("closed-loop evaluation, no human validation"), lead with full-set cross-family evaluation followed by manual inspection of **all** cross-judge disagreements:

```markdown
### **W1**

The evaluation is closed-loop: the authors wrote the benchmark items, the same model (`Model-A`) builds the representation and acts as sole judge while also being one of the evaluated models, and there is no human validation.

### **Response to W1**

To validate the evaluation pipeline independently of `Model-A` and add thorough human verification, we conducted a three-step check across all 180 items and all five evaluated models (4,500 outputs):

**1. Multi-model, cross-family judge cross-check.**
We re-scored all 4,500 outputs using two additional independent judges: `Model-A-Next` and `Model-B` from a distinct model family that neither built the artifacts nor answered any item. Although overall grading strictness differs systematically—`Model-A-Next` is the strictest, `Model-A` is intermediate, and `Model-B` is the most lenient—**our full method outperforms the baseline for every evaluated model under all three judges**:

| Judge | Family | Strictness | Mean paired gain [95% CI] | Models with Ours > Baseline |
| --- | --- | --- | --- | :---: |
| Model-A (paper) | Family 1 | Intermediate | +6.9 [+5.9, +8.2] | 5 / 5 |
| Model-A-Next | Family 1 | Strictest | +4.3 [+3.0, +5.7] | 5 / 5 |
| Model-B | Family 2 | Most lenient | +4.7 [+3.5, +5.9] | 5 / 5 |

Comparing `Model-A` minus `Model-A-Next` across evaluated models also shows **no self-preference**: +6.1 points on `Model-A`'s own outputs ($n = 900$) versus +6.0 to +10.2 points on the other four models.

**2. Exhaustive human check on all cross-judge disagreements.**
Rather than inspecting only a small random subset, we extracted **every case where the three judges disagreed** across the 4,500 outputs and manually checked each judgment against the output text, rubric, and ground truth. Disagreements reflect consistent differences in partial-credit strictness across models rather than unreasonable grading or bias toward our method, and leave all relative rankings unchanged.

**3. Isolation of item authoring and judge-free external evaluation.**
All items and rubrics were written from raw ground-truth artifacts alone without access to generated representations (and an unrestricted raw-input baseline scores 79.4 vs. 76.9 for our standalone representation, confirming the items do not favor our format). We also added a downstream evaluation graded strictly by official unit test suites without any LLM judge.
```

---

## Pattern 3: Positioning Novelty Against Adjacent Literature

When a reviewer claims the paper "merely combines existing components" or misses related work, first map the field by pipeline stage, then give a crisp side-by-side comparison table, and finally add shared-benchmark numbers:

```markdown
### **W1**

Missing discussion and quantitative comparison with closely related methods X and Y; clarify novelty beyond combining existing modules.

### **Response to W1**

Thank you for bringing these works to our attention. Because [broad topic] spans several distinct problems, adjacent papers target different stages of the pipeline:

| Direction | Core question | Representative methods | Relation to ours |
| --- | --- | --- | --- |
| Stage 1: Representation | How are raw inputs mapped to structured states? | Method A, Method B | Upstream precedent |
| **Stage 2: Dynamics (our focus)** | **How do structured states evolve under actions?** | **Method X, Method Y** | **Same category** |
| Stage 3: Policy / Search | How are rollouts turned into actions? | Method C, Method D | Downstream consumer |

Within Stage 2, our approach differs from Method X and Method Y in two key ways:
1. **Task-agnostic transfer.** We pretrain the state module once and **freeze it across all downstream tasks**, whereas prior methods retrain it on each target environment.
2. **Decoupling identity from spatial change.** Prior methods update $K \times T$ entangled state vectors per step, whereas we fix $K$ semantic vectors and predict $K \times T$ spatial masks, preserving temporal identity across occlusion.

| Aspect | Method X / Y | Method Z | **Ours** |
| --- | --- | --- | --- |
| State training | Trained per target environment | Trained per target environment | Pretrained once and **frozen downstream** |
| State representation | $K \times T$ time-varying vectors | $K \times T$ time-varying vectors | $K$ fixed vectors + $K \times T$ dynamic masks |
| Objective | Pointwise $\ell_2$ in latent space | Pointwise $\ell_2$ in latent space | Displacement-aware transport on masks |

We also added direct quantitative comparisons on [shared benchmarks] below:
[Insert complete benchmark table]
```

---

## Pattern 4: Handling a Structurally Ill-Defined Ablation + Budget Confound

When a reviewer asks for a budget cap or component removal that would break the access protocol, explain the mechanism plainly and immediately provide within-experiment controls:

```markdown
**Tool-call count and budget analysis.**
Neither condition sets a call limit, and reasoning effort is identical. Progressive access splits navigation and reading into lightweight steps so the agent loads only relevant nodes (20.1 calls vs. 11.9 for `Unstructured`). We did not impose a hard call cap because truncating progressive traversal before it reaches leaf pages conflates call budget with incomplete navigation. Instead, three controls show that extra calls do not drive the gain:
- **Same-or-fewer-calls subset**: across all 900 `(item, model)` pairs, in the **229 pairs where `Structured` made no more calls than `Unstructured`**, the paired gain is **+6.6 [+4.6, +8.7]** (higher than +3.3 [+2.1, +4.4] on the remaining 671 pairs).
- **More calls can score lower**: the `Hierarchy-only` ablation averages *more* calls than full `Structured` (25.5 vs. 20.5) yet achieves lower coverage because it explores more branches by trial and error without relational links.
- **Gain scales with structural complexity**: gains grow from +3.3 on single-module items to +8.0 on cross-module items and +9.5 on repository-wide items.
```

---

## Pattern 5: Honest Cost, Latency, and Cross-Tier Break-Even Analysis

Never hide cases where runtime cost increases, and escape every literal `$` as `\$`:

```markdown
- **Construction cost, runtime cost, and cost-effectiveness**: building the 23 repository instances cost **\$1,070 in total, or about \$47 per build**. Within the **same model**, carrying read pages across multi-turn editing increases per-trial cost by 21%–25% (\$1.03 to \$1.25 on `Model-Small`; \$4.24 to \$5.32 on `Model-Large`), so single-model runtime cost does not amortize construction cost in this setting. **Cost-effectiveness comes across model tiers**: pairing `Model-Small` with our method raises resolution from 43.0% to **52.6%**, closing over half the gap to native `Model-Large` (61.4%) at **\$1.25 vs. \$4.24 per trial (30% of native `Model-Large`'s cost, saving \$2.99 per trial—about 16 trials to offset a \$47 build)**.
```
