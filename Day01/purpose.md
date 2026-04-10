# Day 01 — Purpose

Kubernetes is not a tool you learn by writing YAML. It is a system you learn by
understanding what problem each component solves and what happens when it fails.

This day establishes the mental model before the syntax. Without this foundation:
- You will debug errors by guessing, not reasoning
- You will fail architecture questions in interviews
- You will copy manifests without knowing what they guarantee

The local cluster (minikube) is intentional. Before touching AKS, you must understand
the primitives without cloud abstraction hiding behavior from you.