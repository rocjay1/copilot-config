---
applyTo: "**/*.tf,**/*.tfvars"
---

# Terraform conventions
<!-- Loaded only when Copilot works with matching files. Keep it to rules that differ from
     common Terraform practice; the model already knows the defaults. -->

- Module layout: <e.g. modules/<name>/{main,variables,outputs,versions}.tf>
- Naming: <resource and variable naming rules>
- Required tags: <list, and where they're set (provider default_tags vs. per resource)>
- Provider and module versions are pinned in `versions.tf`; don't change pins as a side effect.
- Verify with `terraform fmt -check` and `terraform validate`, then `terraform plan`.
  Summarize the plan, and call out any destroy or replace explicitly.
