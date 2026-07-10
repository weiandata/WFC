# Scripts

Use this directory only for small utility scripts that support repository tasks
such as setup, validation, documentation, release preparation, or maintenance.

Business logic must live in the project's language-native source structure, not
in `scripts/`. Each script should have one clear purpose, safe defaults,
documented inputs and outputs, meaningful failures, and a reproducible way to
run it. Do not place credentials, client data, or environment-specific secrets
in scripts.

No utility script is included in this language-independent template. Generated
repositories should add scripts only when they provide a real project need.
