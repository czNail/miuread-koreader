# beta.3 progress stabilization candidate

Base: v6.1.0-beta.2 full source. No public release or Tag made.

Changes target reproducible sync callback, Web/Agent source inconsistency, duplicate readback and queued-download race regressions.

Unverified: whether WeRead accepts all Web reading-time compatibility reports and whether the server actually wrote the observed co=0. Instrumented protocol observations from a Kindle are still required before attributing root cause to a particular PR.

Conservative limitation: a compatibility reading-time upload can be deferred if the Web GET does not expose a trustworthy chapterUid/co/progress. Do not convert it to an untested pure time-only POST.

Unresolved behavior: adopting the remote baseline without first navigating the EPUB is restricted for unresolved coordinates; precise-location navigation remains a separate future test.

Web/Agent confirmation semantics: when a Web readback matches the exact submitted position, the Web POST may be marked Web-confirmed even if Agent is stale; an Agent-only match never confirms a Web POST. Cross-source disagreement remains in diagnostics.
