# Day 11 — Purpose

Everything built across Days 01-10 has been provisioned manually or triggered
manually. Day 11 automates the entire delivery chain. A developer pushes code.
The pipeline builds a Docker image, pushes it to ACR, and deploys the new version
to AKS using Helm — without any human intervention after the code push.

This is the standard delivery pattern at Finnish tech companies. Wolt, Reaktor,
Futurice, and Elisa all operate on this model. A senior DevOps engineer who cannot
design and implement this pipeline end to end is not competitive at that level.

Writing a custom Helm chart demonstrates you understand Helm beyond consuming
third-party charts. Every Finnish company with multiple microservices has internal
Helm charts. Being able to write, template, and maintain them is a senior expectation.

GitOps is covered conceptually because it is increasingly the default in Finnish
enterprise environments — particularly at companies using ArgoCD or Flux. Understanding
the difference between push-based CI/CD and pull-based GitOps shows architectural
maturity that separates senior from principal candidates.