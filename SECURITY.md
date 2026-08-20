# Security policy

Report vulnerabilities in this Elixir SDK privately to the SDK maintainers at
`security@developing.tools`.

Report vulnerabilities in Dodo Payments' hosted API or service privately to
Dodo Payments at `pt-team@dodopayments.com`, the contact published in the official
[Security Reporting Policy](https://docs.dodopayments.com/miscellaneous/security-policy).
Do not open a public issue for an undisclosed security problem.

Include the affected SDK version, a minimal reproduction, and the impact you
believe is possible. Maintainers should acknowledge a private report within
seven days, even when investigation is still in progress.

Never include live Dodo Payments API keys, webhook secrets, document URLs,
customer data, or unredacted request and response bodies in a report.

Security fixes are published for the latest minor release. When a fix changes
authentication, signing, retry safety, or redaction behavior, the advisory will
state whether previous releases should be considered unsafe for production use.

Reports are in scope when they affect a supported release of this Elixir SDK,
its default Req transport, webhook verification, credential handling, or the
published Phoenix example. Dodo's hosted service and unrelated application code
are outside this repository's scope. Until a 1.0 support policy is published,
only the latest released 0.x minor receives security fixes.
