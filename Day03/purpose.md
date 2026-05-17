# Day 03 — Purpose

Hardcoding configuration inside a container image is one of the most common and
dangerous mistakes in containerized systems. It means:
- Different environments (dev, staging, prod) need different images
- Secrets are baked into images that may be pushed to public registries
- A config change requires a full image rebuild and redeployment

ConfigMaps and Secrets solve this by externalizing configuration entirely.
The image stays identical across environments. Only the configuration changes.

This day is not about memorizing YAML fields. It is about understanding:
- How configuration reaches a running container (two mechanisms: env vars and volumes)
- What the behavioral difference is between those two mechanisms
- Why Secrets in Kubernetes are not as secure as most people assume
- What production-grade secret management actually looks like

These questions appear in every senior DevOps and platform engineering interview.