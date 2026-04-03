# Rectify all the question and answer for now i am just copy pasting it

Why use both? (The Hybrid Model)
Separation of Concerns: You use GitHub Actions for Infrastructure CI/CD and Jenkins for the Application DevSecOps Pipeline.
Specialization: Jenkins is highly extensible for complex Maven builds and deep security scanning (SonarQube, OWASP ZAP) using Shared Libraries. GitHub Actions is "closer to the code" for IaC linting and quick provisioning


Why GitHub Actions over Jenkins for Terraform?
OIDC Security (Zero-Secret Model): GitHub Actions supports OIDC (OpenID Connect). This means you don't store long-lived AWS_ACCESS_KEY_ID secrets; instead, GitHub requests a temporary token from AWS for each run, which is significantly more secure for a banking platform.
Native PR Integration: Since the Terraform code lives in GitHub, Actions provides immediate feedback. A terraform plan can be automatically posted as a comment on a Pull Request, allowing for mandatory peer reviews before any infrastructure change is applied.
Lightweight Execution: Terraform doesn't require the heavy build agents that a Java/Maven application does. GitHub Actions provides a fast, ephemeral environment perfect for executing IaC scripts without maintaining a persistent Jenkins agent.


