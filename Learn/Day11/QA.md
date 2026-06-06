# Kubernetes Day 11 — QA Session

> Format: Concept explanation → Scenario/Question → Complete Answer → Senior Additions
> Covers CI/CD Pipeline, Custom Helm Charts, and GitOps.
> Designed for direct use in senior and principal DevOps interviews.

---

## Section 1: CI/CD Pipeline with --atomic

### Concept

`helm upgrade --install` with `--atomic` and `--wait` provides production-safe
deployments. `--wait` makes Helm wait until all Pods pass their readiness probes before
marking the upgrade successful. `--atomic` makes Helm automatically roll back to the
previous revision if the upgrade fails or times out.

When rollback occurs via `--atomic`, Helm creates a new revision. It does not undo
revision 2 — it creates revision 3 that re-applies revision 1's templates. Helm history
always grows forward. The failed revision remains in history for audit.

```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         failed      Upgrade failed: timed out waiting for condition
3         deployed    Rollback to 1
```

The pipeline exit code is non-zero when `--atomic` triggers rollback. ADO marks the
Deploy stage red. The application continues serving traffic via revision 3.

---

### Q1: Pipeline Deploy Fails with --atomic — What Happens

**Question:**
Your CI/CD pipeline builds and pushes successfully. The Deploy stage fails. Walk
through exactly what happens to the running application and what the pipeline reports.

**Complete Answer:**

Helm starts the upgrade to the new image. `--wait` monitors readiness probes on new
Pods. If Pods fail to become Ready before `--timeout 5m` expires — bad image,
application crash, probe misconfiguration, resource quota exceeded — `--atomic`
triggers automatic rollback.

Helm creates a new revision that re-applies the last successful revision's templates.
Kubernetes performs a rolling update replacing the failed new Pods with the previous
version. The application never loses all traffic — rolling update ensures minimum
availability throughout.

The pipeline: `helm upgrade` exits with non-zero. ADO marks Deploy stage failed.
Failure notification sent. The running application serves traffic through the
automatically restored previous revision.

**Helm history after atomic failure:**
```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         failed      Upgrade failed: timed out
3         deployed    Rollback to 1
```

Revision 2 marked failed — permanent audit record. Revision 3 is the auto-rollback.
The engineer investigates revision 2, fixes the code, pushes again — pipeline creates
revision 4.

---

## Section 2: Helm Chart Versioning

### Concept

`Chart.yaml` contains two version fields:

`version` — the chart package version. Must be incremented whenever chart structure
changes. Used by Helm chart repositories to distinguish chart releases. Two charts
with the same name and version cannot coexist in a repository — the second push is
rejected.

`appVersion` — informational only. Represents the application version, not the chart.
Helm does not use this for upgrade decisions. The actual deployed version is controlled
by `image.tag` in values.

Forgetting to increment `version` when modifying templates causes silent failures in
chart repository workflows — the repository rejects the package push. In Git-based
chart workflows, it breaks the audit trail in `helm history`.

---

### Q2: chart version vs appVersion — What Happens When Not Incremented

**Question:**
Explain the difference between `version` and `appVersion` in Chart.yaml. What happens
if you forget to increment chart `version` when modifying a template?

**Complete Answer:**

`version` — chart version. Governs chart packaging and repository publishing. Must
follow semver and increment on any chart change.

`appVersion` — application version. Informational. Not used by Helm for upgrade logic.

**If version is not incremented:**

In chart repository workflows: the repository rejects the push — a chart with that
name and version already exists. The pipeline fails at the package push step.

In Git-based chart workflows: no hard failure but `helm history` becomes unreadable:

```
REVISION  CHART VERSION  DESCRIPTION
1         my-app-0.1.0   Install
2         my-app-0.1.0   Upgrade  ← identical chart version, different templates
```

Cannot determine which template change corresponds to which revision during incident
investigation.

**Semver convention for chart version:**
- Patch (0.1.0 → 0.1.1) — minor template fix, default value change
- Minor (0.1.0 → 0.2.0) — new template added, new configurable value
- Major (0.1.0 → 1.0.0) — breaking values structure change, removed template

---

## Section 3: Push-based CI/CD vs Pull-based GitOps

### Concept

Push-based CI/CD — the pipeline actively deploys changes to the cluster. After the
pipeline completes, there is no ongoing enforcement. Manual changes persist silently.
The cluster can drift from Git over time.

Pull-based GitOps — a controller (ArgoCD or Flux) runs inside the cluster and
continuously reconciles cluster state against a Git repository. Any drift — manual
kubectl change, accidental deletion — is detected and corrected automatically within
seconds.

With GitOps, the pipeline no longer runs `helm upgrade`. It only builds, pushes to
ACR, and updates the image tag in a Git values file. The GitOps controller detects
the change and applies it. Pipeline owns build and push. Controller owns deploy.

---

### Q3: Push CI/CD vs Pull GitOps — Concrete Failure Prevention

**Question:**
Explain the difference between push-based CI/CD and pull-based GitOps. Give a concrete
scenario where GitOps prevents a problem pipeline-based deployment cannot.

**Complete Answer:**

Push-based: pipeline pushes changes to the cluster on each run. No ongoing enforcement.
Pull-based: GitOps controller continuously pulls desired state from Git and reconciles.
Any drift auto-corrected.

**Scenario 1 — kubectl edit drift prevention:**
An engineer runs `kubectl edit deployment my-app -n production` to temporarily increase
replicas during an incident. In push-based CI/CD, this manual change persists
indefinitely until the next deployment overwrites it. In GitOps, the controller detects
within seconds that the live replica count differs from Git and restores it automatically.
The unauthorized change is corrected and logged.

**Scenario 2 — Partial deployment failure convergence:**
Pipeline deploys 10 microservices. Service 5 fails. Pipeline stops. Services 1-4 are
on the new version, 5-10 are on the old. Cluster is inconsistent. Human must determine
what deployed and manually complete or roll back.

With GitOps, the commit represents all 10 services simultaneously. The controller
reconciles each independently. Service 5 fails and keeps retrying. Services 6-10
succeed. The cluster converges toward the desired state without human intervention.

**When to use each:**

| Scenario | Approach |
|----------|----------|
| Small team, simple deployments | Push-based CI/CD |
| Multi-team, many environments | GitOps |
| Regulated (fintech, healthcare) | GitOps — audit trail in Git |
| Finnish enterprise AKS | GitOps increasingly standard |

---

## Section 4: Production Rollback

### Concept

Helm rollback re-applies a previous revision's rendered templates including the exact
image tag used at that revision. It does not require pipeline re-run, image rebuild,
or Git changes. The old image must still exist in ACR — guaranteed when using immutable
Build.BuildId tags, not when using `latest` only.

Rollback creates a new revision. History grows forward. The failed revision remains
for audit.

---

### Q4: Production Rollback — Exact Commands and Sequence

**Question:**
The pipeline succeeds but the new version is malfunctioning in production. Walk
through the exact rollback commands and what happens at each step.

**Complete Answer:**

```powershell
# Step 1 — identify revisions
helm history my-app -n day11
```
```
REVISION  STATUS    DESCRIPTION
1         deployed  Install complete      ← stable
2         deployed  Upgrade complete      ← broken, currently running
```

```powershell
# Step 2 — roll back to revision 1
helm rollback my-app 1 -n day11
```

Helm re-applies revision 1's rendered templates. Kubernetes performs rolling update —
new Pods with old image replace broken Pods. Application continues serving traffic.

```powershell
# Step 3 — verify history after rollback
helm history my-app -n day11
```
```
REVISION  STATUS      DESCRIPTION
1         superseded  Install complete
2         superseded  Upgrade complete
3         deployed    Rollback to 1
```

```powershell
# Step 4 — confirm correct image running
kubectl get pods -n day11 -o jsonpath='{.items[*].spec.containers[0].image}'
```

**Why this works — the immutable tag dependency:**
Rollback re-applies revision 1's `image.tag=41` (the old Build.BuildId). That image
still exists in ACR because Build.BuildId tags are immutable and never overwritten.
If you had used `latest` only, rollback silently deploys the broken version again.

---

## Section 5: Business Case for CI/CD

### Concept

Manual `kubectl apply` from developer laptops creates three production-scale problems:
reliability risk from human error, security and compliance gaps from direct cluster
access, and delivery bottlenecks as team size grows. For Finnish enterprise clients,
the compliance angle is often the deciding argument — regulators ask specifically how
production deployments are controlled and audited.

---

### Q5: Business Case — Manual kubectl to CI/CD Pipeline

**Question:**
Make the business case for migrating from manual `kubectl apply` from developer laptops
to a proper CI/CD pipeline. Three points.

**Complete Answer:**

**Point 1 — Reliability through consistency:**
Manual deployments introduce human error — wrong namespace, wrong image tag, missing
resource definitions. A pipeline executes the same validated sequence every time.
`--atomic` auto-rolls back failures. Readiness probes gate every deployment.

**Point 2 — Security and compliance:**
A developer's laptop with production cluster kubeconfig is a security gap. A pipeline
service principal with scoped permissions replaces direct developer access. Every
deployment is logged in ADO with the triggering commit, the approver, and the
timestamp. For Finnish companies under GDPR, Finanssivalvonta regulations, or ISO
27001, this audit trail is not optional.

The one-line close: "With manual deployments, your auditor asks who deployed the
broken change at 3pm on Tuesday and you cannot answer. With a pipeline, you show
them the ADO log in 30 seconds."

**Point 3 — Delivery speed and team scalability:**
Manual deployments are a bottleneck — one person deploys, everyone waits, knowledge
is concentrated in whoever knows the kubectl commands. A pipeline lets every developer
trigger deployments through code push. Approval gates replace tribal knowledge.
New engineers deliver to production on their first week without needing cluster
credentials.

---

## Section 6: Production Incident Response

### Concept

A complete incident response covers four phases: detect, respond, restore, prevent.
Senior engineers present all four. Most candidates present only detect and restore.

Log Analytics is critical when Pods are already replaced — container logs are gone
but LAW retains them for the configured retention period. Knowing the KQL queries for
OOMKill, failed Pods, and application errors separates engineers who operate in
production from engineers who only operate in labs.

---

### Q6: Production Incident — Kubernetes Diagnosis and Resolution

**Question:**
A Finnish hiring manager asks: "Walk me through a production incident on Kubernetes
and how you would diagnose and resolve it. Use a specific scenario."

**Complete Answer:**

**Scenario:** New version deployed via CI/CD pipeline successfully. Users report 500
errors. Pods are in CrashLoopBackOff.

**Phase 1 — Detect:**
```powershell
kubectl get pods -n production
```
Shows 3 Pods in CrashLoopBackOff, RESTARTS counter at 4 and climbing.

```powershell
kubectl describe pod <pod-name> -n production
```
Events show: `Back-off restarting failed container`. Exit code 1.

```powershell
kubectl logs <pod-name> -n production --previous
```
`--previous` fetches logs from the last terminated container. Output:
`Error: DATABASE_URL environment variable not set`

**Phase 2 — Respond:**
Confirm the missing env var was present in the previous release values. Check the
Helm values file — someone removed it in the latest commit.

**Phase 3 — Restore:**
```powershell
helm history my-app -n production
helm rollback my-app 1 -n production
kubectl get pods -n production -w
```
Previous version restored within 2 minutes. Users no longer seeing errors.

**Phase 4 — Prevent:**
Fix the values file. Add a Helm test that validates required env vars are present
before marking the deployment successful. Add application startup check that fails
fast with a clear error when required configuration is missing — making the readiness
probe fail and `--atomic` catch it before users are affected.

**When kubectl logs is unavailable — LAW queries:**
```kql
ContainerLogV2
| where TimeGenerated > ago(1h)
| where ContainerName contains "my-app"
| where LogMessage contains "Error" or LogMessage contains "Exception"
| project TimeGenerated, PodName, LogMessage
| order by TimeGenerated desc
```

```kql
KubePodInventory
| where TimeGenerated > ago(1h)
| where ContainerLastStatus == "OOMKilled" or PodStatus == "Failed"
| project TimeGenerated, PodName, Namespace, ContainerLastStatus, PodRestartCount
| order by TimeGenerated desc
```

Stating these queries shows you operate in production where Pods are replaced before
anyone opens a terminal.

---

## Day 11 Verdict — Kubernetes Track Complete

| Area | Status |
|------|--------|
| --atomic pipeline failure behavior | Complete — Helm history revision sequence noted |
| chart version vs appVersion | Complete — repository rejection and audit trail impact noted |
| Push CI/CD vs GitOps | Complete — two concrete scenarios, controller convergence noted |
| Production rollback commands | Complete — immutable tag dependency, history growth noted |
| Business case for CI/CD | Principal-level — compliance angle, Finanssivalvonta, one-line close |
| Production incident response | Principal-level — all four phases, LAW queries, --previous flag |

---

## Kubernetes Track Summary — Days 01-11

| Day | Topic | Status |
|-----|-------|--------|
| 01 | Architecture, Pods, Deployments | Complete |
| 02 | Services, Labels, Selectors | Complete |
| 03 | ConfigMaps, Secrets | Complete |
| 04 | Probes, Rolling Updates, Rollbacks | Complete |
| 05 | Namespaces, ResourceQuota, RBAC | Complete |
| 06 | Storage, PersistentVolumes, StatefulSets | Complete |
| 07 | DaemonSets, Jobs, CronJobs, NetworkPolicy | Complete |
| 08 | Ingress, HPA, Taints, Tolerations, Affinity, PDB | Complete |
| 09 | AKS provisioning with Terraform | Complete |
| 10 | Azure Key Vault, Workload Identity, Helm | Complete |
| 11 | CI/CD Pipeline, Custom Helm Chart, GitOps | Complete |

**Next track: Docker (3 days) then Prometheus + Grafana (5 days)**