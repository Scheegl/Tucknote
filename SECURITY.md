# Security policy

Report suspected vulnerabilities privately through **Security → Report a vulnerability** on the GitHub repository. Include the app and macOS versions, impact, and a reproducible example using disposable data. Leave personal inbox data, secrets, and credentials out of the report. Use public Issues for ordinary bugs and feature requests.

Security fixes are made for the latest published version. Maintainers will confirm scope, prepare a fix, and coordinate disclosure with the reporter.

Tucknote stores its inbox as local JSON under Application Support. The containing directory is restricted to the current account on write. Files are readable by processes running as that account. Tucknote applies no separate encryption to the JSON.

Automatic title fetching is off by default. Enabling it or choosing **Refresh Link Titles** sends requests to saved HTTPS URLs, including their query parameters, and can follow HTTPS redirects. YouTube metadata requests use a canonical video or playlist URL. The app uses ephemeral sessions with cookie and credential stores disabled and uses the operating system's TLS trust checks.
