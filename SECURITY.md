# Security policy

Report suspected vulnerabilities privately through **Security → Report a vulnerability** on the GitHub repository. Include the app and macOS versions, impact, and a reproducible example using disposable data. Leave personal inbox data, secrets, and credentials out of the report. Use public Issues for ordinary bugs and feature requests.

Security fixes are made for the latest published version. Maintainers will confirm scope, prepare a fix, and coordinate disclosure with the reporter.

Tucknote stores its inbox as local JSON under Application Support. The containing directory is restricted to the current account on write. Files are readable by processes running as that account. Tucknote applies no separate encryption to the JSON.

Tucknote automatically requests YouTube metadata using canonical video or playlist IDs. Automatic title and description fetching for other sites is on by default and can be disabled in Settings. Automatic fetching or choosing **Refresh Link Titles** sends requests to saved HTTPS URLs, including their query parameters, and can follow HTTPS redirects. YouTube metadata requests use a canonical video or playlist URL. The app uses ephemeral sessions with cookie and credential stores disabled and uses the operating system's TLS trust checks.

## Keep private data out of Git

Builds, local credentials, signing files, and inbox data are ignored. Store signing identities and notarization credentials in Keychain. Keep test data synthetic.

Install the optional local check with `git config --local core.hooksPath .githooks`. It scans the index before a commit. GitHub CI runs the same check, and GitHub secret scanning and push protection provide a separate server-side check. Run `python3 Tools/check-secrets.py workspace` to scan worktree files or `python3 Tools/check-secrets.py history` to scan local Git objects. These checks print locations and rule names only. Custom or unusually short secrets may escape pattern matching, so review changes before pushing.
