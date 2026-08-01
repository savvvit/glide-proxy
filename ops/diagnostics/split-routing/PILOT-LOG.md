# Mini-pilot log: AI-assisted split-routing diagnostic

Этот файл — шаблон фактического журнала мини-пилота. Заполняется в Pull Request или отдельным follow-up только по наблюдаемым данным. Не переносить сюда секреты, private keys, DNS challenge values или полные production outputs.

## Pilot identity

- Owner:
- Repository branch:
- Pull Request:
- Baseline commit:
- Start date:
- Completion date:
- Final status: planned / repo-ready / approved / deployed / tested / rolled back / closed

## Gates

| Gate | Evidence | Owner decision | Timestamp |
|---|---|---|---|
| Scope accepted | | | |
| Repo-only PR ready | | | |
| Independent review complete | | | |
| Merge approved | | | |
| Production preflight accepted | | | |
| Certificate and DNS change approved | | | |
| Install approved | | | |
| Reload approved | | | |
| Owner-device test accepted | | | |
| Client test approved, if needed | | | |
| Teardown approved | | | |
| Closeout accepted | | | |

## Active effort

| Role | Discovery | Implementation | Review | Production operations | Test/analysis | Closeout | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Owner | | | | | | | |
| Codex | | | | | | | |
| Independent reviewer | | | | | | | |

Не смешивать активное время с ожиданием DNS propagation, approval или календарной паузой.

## Iterations and findings

| Iteration | Trigger | Finding/change | Detected by | Prevented production issue? |
|---:|---|---|---|---|
| 1 | Initial implementation | | | |

## Manual owner steps

| Step | Instruction sufficient? | Unexpected decision or friction | Improvement |
|---|---|---|---|
| DNS-01 certificate | | | |
| A records | | | |
| Controlled SSH preflight | | | |
| Install without reload | | | |
| Activation | | | |
| Owner-device scenarios | | | |
| DNS teardown | | | |
| Server teardown | | | |

## Diagnostic outcome

- VPN-off result:
- VPN-on result:
- Automated analyzer classification:
- Server-log corroboration:
- Hypothesis: confirmed / refuted / inconclusive
- Scope of conclusion:
- Evidence retention deadline:

## Rollback evidence

- DNS no longer routes both names to the diagnostic endpoint:
- Wildcard fallback suppressed where required:
- Diagnostic Nginx site absent:
- `nginx -t` successful:
- Existing mirror smoke-test successful:
- Diagnostic log deleted or approved retention recorded:
- Certificate lineage decision:

## Methodology closeout

- What AI assistance accelerated:
- What required owner judgment:
- What review or tests caught:
- Where instructions were insufficient:
- Reusable artifact decision:
- Proposed Playbook/backlog change, if any:
