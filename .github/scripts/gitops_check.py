#!/usr/bin/env python3
"""Render what a change touches at its base and head revisions, validate the
head renders with kubeconform, and apply the repo policy (see POLICY below).

Usage: gitops_check.py --base <rev> --head <rev> [--out <dir>] [--no-kubeconform]

Rendered:
- platform-apps/<app>/<env>/ dirs touched by the change: `helm template` of the
  upstream chart from config.yaml with that dir's values.yaml.
- argocd-apps/ (always, it maps manifests/ dirs to their Applications):
  `helm template` with env=local and rawManifestEnvs={local}.
- every Application in that render whose source path is a directory in this
  repo (manifests/, network-policies/): the YAML files under it.

kubeconform runs only on head renders of sources the change touched, so drift
elsewhere doesn't block unrelated PRs.

POLICY
a. No new Job/CronJob and no new Argo CD or Helm hook. A finding is new when it
   isn't in the base render and isn't matched by .github/policy/job-allowlist.txt.
b. No custom resources from the groups in SSA_UNSAFE_GROUPS in an app synced
   with ServerSideApply=true (every platform-apps app, via the ApplicationSet):
   Argo CD 2.10 can't resolve their schemas and its diff panics.
Disabled platform apps (enabled != "true") don't deploy, so they yield no
policy findings; enabling one makes its findings new.
"""
import argparse
import fnmatch
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile

import yaml

SSA_UNSAFE_GROUPS = {
    "external-secrets.io",
    "generators.external-secrets.io",
    "postgresql.cnpg.io",
    "barmancloud.cnpg.io",
    "trust.cert-manager.io",
}
ARGO_HOOK, HELM_HOOK = "argocd.argoproj.io/hook", "helm.sh/hook"
# Argo CD never runs Helm test hooks, so resources that are only test hooks never exist.
HELM_TEST_HOOKS = {"test", "test-success", "test-failure"}
JOB_KINDS = {"Job", "CronJob"}
RAW_ENV = "local"
# CRD APIs the cluster serves (prometheus-operator-crds is wave -5); Argo CD passes
# the live list to helm, some charts refuse to render without them.
HELM_API_VERSIONS = ["monitoring.coreos.com/v1"]
ALLOWLIST = ".github/policy/job-allowlist.txt"
KUBECONFORM_SCHEMAS = [
    "default",
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/"
    "{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json",
]


class Loader(yaml.SafeLoader):
    """SafeLoader minus the YAML 1.1 '=' value tag, which breaks on bare '=' scalars in CRDs."""


Loader.yaml_implicit_resolvers = {
    k: [r for r in v if r[0] != "tag:yaml.org,2002:value"]
    for k, v in yaml.SafeLoader.yaml_implicit_resolvers.items()
}


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def export_tree(rev, dest):
    data = subprocess.run(["git", "archive", rev], check=True, capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        tar.extractall(dest, filter="data")


def load_docs(text, origin):
    try:
        return [d for d in yaml.load_all(text, Loader=Loader) if isinstance(d, dict)]
    except yaml.YAMLError as e:
        raise SystemExit(f"YAML parse error in {origin}: {e}")


def helm_template(args, origin):
    p = subprocess.run(["helm", "template", *args], capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"helm template failed for {origin}:\n{p.stderr}")
    return p.stdout


def render_platform_app(tree, src):
    """src = platform-apps/<app>/<env>. Returns (yaml_text, enabled) or None if absent."""
    cfg_path = os.path.join(tree, src, "config.yaml")
    if not os.path.exists(cfg_path):
        return None
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f) or {}
    _, app, env = src.split("/")
    chart, repo, ver = cfg["chart"], cfg["repoURL"], str(cfg["targetRevision"])
    args = [f"{env}-{app}"]
    if "://" in repo:
        args += [chart, "--repo", repo]
    else:  # bare registry host: Argo CD treats it as an OCI Helm repo
        args += [f"oci://{repo.rstrip('/')}/{chart}"]
    args += ["--version", ver, "--namespace", cfg.get("namespace", "default"), "--include-crds"]
    for v in HELM_API_VERSIONS:
        args += ["--api-versions", v]
    values = os.path.join(tree, src, "values.yaml")
    if os.path.exists(values):
        args += ["-f", values]
    return helm_template(args, src), str(cfg.get("enabled")) == "true"


def render_argocd_apps(tree):
    return helm_template(
        ["platform-root", os.path.join(tree, "argocd-apps"),
         "--set", f"env={RAW_ENV}", "--set", f"rawManifestEnvs={{{RAW_ENV}}}"],
        "argocd-apps",
    )


def read_dir_yaml(tree, path):
    parts = []
    root = os.path.join(tree, path)
    for d, _, files in sorted(os.walk(root)):
        for name in sorted(files):
            if name.endswith((".yaml", ".yml")):
                with open(os.path.join(d, name)) as f:
                    parts.append(f"# Source: {os.path.relpath(os.path.join(d, name), tree)}\n{f.read()}")
    return "\n---\n".join(parts)


def raw_dir_of(path):
    """manifests/<name>/<env>/... -> manifests/<name>/<env>; network-policies/<env>/... likewise."""
    p = path.split("/")
    if p[0] == "manifests" and len(p) >= 4:
        return "/".join(p[:3])
    if p[0] == "network-policies" and len(p) >= 3:
        return "/".join(p[:2])
    return None


def render_rev(rev, changed, out):
    """Returns {source: {"text", "docs", "ssa", "enabled", "changed"}} for one revision."""
    sources = {}
    with tempfile.TemporaryDirectory() as tree:
        export_tree(rev, tree)

        argo_text = render_argocd_apps(tree)
        sources["argocd-apps"] = dict(text=argo_text, ssa=False, enabled=True,
                                      changed=any(c.startswith("argocd-apps/") for c in changed))
        raw_apps = {}
        for doc in load_docs(argo_text, "argocd-apps"):
            if doc.get("kind") != "Application":
                continue
            spec = doc.get("spec", {})
            path = (spec.get("source") or {}).get("path")
            if path and raw_dir_of(path.rstrip("/") + "/_"):  # a repo dir, not a chart
                opts = (spec.get("syncPolicy") or {}).get("syncOptions") or []
                raw_apps[path.rstrip("/")] = "ServerSideApply=true" in opts

        changed_raw = {d for d in map(raw_dir_of, changed) if d}
        for path in sorted(set(raw_apps) | changed_raw):
            if not os.path.isdir(os.path.join(tree, path)):
                continue
            sources[path] = dict(text=read_dir_yaml(tree, path), ssa=raw_apps.get(path, False),
                                 enabled=path in raw_apps, changed=path in changed_raw)

        for src in sorted({"/".join(c.split("/")[:3]) for c in changed
                           if c.startswith("platform-apps/") and c.count("/") >= 3}):
            r = render_platform_app(tree, src)
            if r is not None:
                sources[src] = dict(text=r[0], ssa=True, enabled=r[1], changed=True)

    for src, s in sources.items():
        s["docs"] = load_docs(s["text"], f"{rev}:{src}")
        fn = os.path.join(out, src.replace("/", "__") + ".yaml")
        with open(fn, "w") as f:
            f.write(s["text"])
        s["file"] = fn
    return sources


def load_allowlist(path):
    entries = []
    if not os.path.exists(path):
        return entries
    with open(path) as f:
        for n, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 3)
            if len(parts) < 4:
                raise SystemExit(f"{path}:{n}: want '<source-glob> <kind-glob> <name-glob> <reason>'")
            entries.append(parts[:3])
    return entries


def group_of(api_version):
    return api_version.split("/")[0] if "/" in api_version else ""


def findings(sources):
    """-> (hooks_or_jobs, ssa_unsafe): sets of (source, kind, name)."""
    jobs, unsafe = set(), set()
    for src, s in sources.items():
        if not s["enabled"]:
            continue
        for d in s["docs"]:
            kind = d.get("kind", "")
            meta = d.get("metadata") or {}
            ident = (src, kind, meta.get("name", "?"))
            ann = meta.get("annotations") or {}
            helm_hooks = {h.strip() for h in str(ann.get(HELM_HOOK, "")).split(",") if h.strip()}
            if helm_hooks and helm_hooks <= HELM_TEST_HOOKS and ARGO_HOOK not in ann:
                continue
            if kind in JOB_KINDS or helm_hooks or ARGO_HOOK in ann:
                jobs.add(ident)
            if s["ssa"] and group_of(d.get("apiVersion", "")) in SSA_UNSAFE_GROUPS:
                unsafe.add(ident)
    return jobs, unsafe


def kubeconform(files):
    if not files:
        return True
    cmd = ["kubeconform", "-strict", "-ignore-missing-schemas", "-summary", "-output", "text"]
    for loc in KUBECONFORM_SCHEMAS:
        cmd += ["-schema-location", loc]
    p = subprocess.run(cmd + files, capture_output=True, text=True)
    print(p.stdout + p.stderr, end="")
    return p.returncode == 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-kubeconform", action="store_true")
    a = ap.parse_args()

    base = git("merge-base", a.base, a.head).strip()
    head = git("rev-parse", a.head).strip()
    changed = [c for c in git("diff", "--name-only", base, head).splitlines() if c]
    out = a.out or tempfile.mkdtemp(prefix="gitops-check-")
    print(f"base {base[:12]}  head {head[:12]}  changed files: {len(changed)}  renders: {out}")

    os.makedirs(f"{out}/base", exist_ok=True)
    os.makedirs(f"{out}/head", exist_ok=True)
    b = render_rev(base, changed, f"{out}/base")
    h = render_rev(head, changed, f"{out}/head")
    touched = [f"{k}{'' if v['enabled'] else ' [disabled]'}{' [SSA]' if v['ssa'] else ''}"
               for k, v in sorted(h.items()) if v["changed"]]
    print("touched sources (head): " + (", ".join(touched) or "none"))

    ok = True
    if not a.no_kubeconform:
        print("\n## kubeconform (head, touched sources)")
        ok &= kubeconform([v["file"] for v in h.values() if v["changed"]])

    allow = load_allowlist(ALLOWLIST)
    bj, _ = findings(b)
    hj, hu = findings(h)
    def allowed(f):
        return any(all(fnmatch.fnmatchcase(v, g) for v, g in zip(f, e)) for e in allow)

    new_jobs = sorted(f for f in hj - bj if not allowed(f))

    print("\n## policy a: new Jobs/CronJobs/hooks")
    for f in sorted(hj):
        state = "NEW" if f in new_jobs else ("allowlisted" if allowed(f) else "existing")
        print(f"  {state:11} {f[0]}: {f[1]}/{f[2]}")
    if new_jobs:
        ok = False
        print("FAIL: new one-time Jobs/hooks. Prefer a declarative, controller-reconciled "
              f"option; if none exists, add an entry with the reason to {ALLOWLIST}.")
    else:
        print("ok")

    print("\n## policy b: SSA-unsafe custom resources in ServerSideApply apps")
    for f in sorted(hu):
        print(f"  FAIL {f[0]}: {f[1]}/{f[2]}")
    if hu:
        ok = False
        print("FAIL: Argo CD 2.10 panics diffing these under ServerSideApply. Move them to "
              "an argocd-apps/templates/app-*.yaml Application without ServerSideApply=true.")
    else:
        print("ok")

    with open(f"{out}/summary.json", "w") as f:
        json.dump({"base": base, "head": head, "new_jobs": new_jobs, "ssa_unsafe": sorted(hu),
                   "ok": bool(ok)}, f, indent=1)
    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
