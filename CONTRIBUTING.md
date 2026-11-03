# Contributing

1. Create a branch from `main`; use Conventional Commit subjects (`fix: ...`, `docs: ...`).
2. Run the CI checks (needs [ShellCheck](https://www.shellcheck.net/)):

   ```bash
   bash -n setup.sh backend-setup.sh coder-setup.sh gitlab-setup.sh certify.sh
   shellcheck setup.sh backend-setup.sh coder-setup.sh gitlab-setup.sh certify.sh
   ```

   Run the installers themselves only on a disposable server: they write to
   `/opt`, replace Nginx configuration and remove existing installations.
3. Open a pull request against `main`; it is squash-merged after CI passes and review.

Code contributions are licensed under MIT ([LICENSE](LICENSE)), documentation
under CC BY 4.0 ([LICENSE-DOCS](LICENSE-DOCS)).
