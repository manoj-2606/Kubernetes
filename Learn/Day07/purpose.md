# Day 07 — Purpose

Not every workload is a long-running web server. Kubernetes supports three additional
workload patterns that production systems depend on daily:

DaemonSets ensure exactly one Pod runs on every node — the correct pattern for
node-level agents like log collectors, metrics exporters, and security scanners.
Running these as Deployments means some nodes get multiple Pods and others get none.

Jobs ensure a task runs to completion exactly the right number of times — database
migrations, batch processing, data exports. A Deployment restarts failed containers
forever. A Job runs until success and stops.

CronJobs schedule Jobs on a time basis — nightly backups, hourly reports, cleanup
tasks. Without CronJobs, teams run cron on a VM outside the cluster, losing all
Kubernetes scheduling, resource management, and observability benefits.

NetworkPolicy closes the final gap from Day 05. Namespaces isolate names and policies
but not network traffic. Without NetworkPolicy, any Pod in any namespace can send
traffic to any other Pod. In a multi-team cluster this is a serious security gap.
NetworkPolicy enforces explicit allow rules — everything else is denied.

These four primitives complete the core Kubernetes workload model.