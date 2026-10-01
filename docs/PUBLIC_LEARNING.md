# Public learning deployment

License: CC BY 4.0. Attribution: Computor contributors, TU Graz.

Public learning and hosted execution have different admission boundaries. The
main/27.3 public website can offer `/learn`, a read-only course catalog and public
GitHub examples without provisioning a hosted workspace. These paths need no
Computor account and never authorize anonymous execution.

Deploy the backend/web from an exact tested main commit. Keep code.tugraz.at on
its stable release/2026.10 checkout and configuration. The current Computor
Marketplace extension supports both backends; Hackl is optional for course tools.
Record backup, migration, health and rollback evidence for the public rollout.

Coder is optional for public practice. Learners can execute locally or in their
own GitHub Codespaces. The course devcontainer pins its base image and Python
dependencies and installs the Computor extension. Signed-in learners can ask
Luna from their assignment page when the public tutor is enabled; inference
runs on the existing restricted service, independent of their code workspace.
Optional AI extensions may use the learner's external provider key. No model
runs on the GitHub VM. Hackl/BYOK integration remains a later option.

Keep hosted capacity limits independent of account availability. Before opening
broader registration or server grading, pass the untrusted-execution gate for the
exact deployed runtime: tenant isolation, reference/credential isolation, network
denial, cgroups, pids, disk/output/time limits and concurrent admission. Coder
workspaces and grading workers are separate boundaries and both need evidence.
An open source release or a successful health response alone does not clear this
gate. Existing invite/admission controls stay until the gate passes.

Documentation for course policy, public API and model setup is maintained in
[the backend guide](https://github.com/computor-org/computor-backend/blob/main/docs/public-learning.md)
and [the public course guide](https://github.com/computor-org/data-science-python/blob/main/docs/GETTING_STARTED.md).
