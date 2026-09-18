#!/usr/bin/env python3
"""Cluster-free custody render, NOTES and archive checks. Requires Helm and PyYAML.

Build locked dependencies first. All fixture mutations and packages use temporary
copies; no cluster, registry publication or retained fixture is accessed.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
CHART = ROOT / "charts/openbao-custody"


def helm(*args, success=True):
    result = subprocess.run(
        [os.environ.get("HELM", "helm"), *map(str, args)],
        capture_output=True,
        text=True,
        check=False,
    )
    if success and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result


class CustodyChartTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="custody-chart-check-")
        cls.addClassCleanup(cls.work.cleanup)
        cls.chart = Path(cls.work.name) / "openbao-custody"
        shutil.copytree(CHART, cls.chart)
        # Helm template omits NOTES. Render the exact source as ConfigMap data
        # in this disposable copy so Helm 3 and 4 can test it at a chosen kube
        # version without an install or an API connection.
        notes = (cls.chart / "templates/NOTES.txt").read_text()
        (cls.chart / "templates/review-notes.yaml").write_text(
            "apiVersion: v1\nkind: ConfigMap\nmetadata:\n"
            "  name: review-notes\ndata:\n  notes: |-\n"
            + "\n".join("    " + line for line in notes.splitlines())
            + "\n"
        )

    def render(self, release="openbao-custody", *args, chart=None):
        result = helm(
            "template", release, chart or self.chart,
            "--namespace", "custody", "--kube-version", "1.30.0", *args,
        )
        return [doc for doc in yaml.safe_load_all(result.stdout) if doc]

    def resource(self, docs, kind, name=None):
        matches = [doc for doc in docs if doc["kind"] == kind
                   and (name is None or doc["metadata"]["name"] == name)]
        self.assertEqual(len(matches), 1, (kind, name, matches))
        return matches[0]

    def test_names_notes_and_raft_joins(self):
        variants = [
            ("openbao-custody", [], "openbao-custody"),
            ("another-release", [], "openbao-custody"),
            ("another-release", ["--set", "openbao.fullnameOverride=custom"], "custom"),
            ("review", ["--set", "openbao.fullnameOverride="], "review-openbao"),
            ("review-openbao", ["--set", "openbao.fullnameOverride="], "review-openbao"),
            ("review", ["--set", "openbao.fullnameOverride=,openbao.nameOverride=bao"], "review-bao"),
            ("review-bao", ["--set", "openbao.fullnameOverride=,openbao.nameOverride=bao"], "review-bao"),
            ("review", ["--set", "openbao.fullnameOverride=" + "a" * 62 + "-suffix"], "a" * 62),
        ]
        for release, args, expected in variants:
            with self.subTest(release=release, args=args):
                docs = self.render(release, *args)
                sts = self.resource(docs, "StatefulSet", expected)
                self.resource(docs, "Service", expected + "-active")
                self.assertEqual(sts["spec"]["serviceName"], expected + "-internal")
                hcl = self.resource(docs, "ConfigMap", expected + "-config")["data"]["extraconfig-from-values.hcl"]
                for ordinal in range(3):
                    self.assertIn(f'https://{expected}-{ordinal}.{expected}-internal:8200', hcl)
                notes = self.resource(docs, "ConfigMap", "review-notes")["data"]["notes"]
                self.assertTrue(notes.startswith("OpenBao Custody has been deployed!"))
                self.assertIn(f"https://{expected}-active.custody.svc.cluster.local:8200", notes)
                self.assertIn(f"exec {expected}-0 -- bao operator init", notes)
                self.assertIn(f"exec -it {expected}-<n> -- bao operator unseal", notes)
                self.assertIn("auth/<mount>/config", notes)

    def test_namespace_and_replica_overrides(self):
        docs = self.render("review", "--set", "openbao.global.namespace=other,openbao.server.ha.replicas=5")
        notes = self.resource(docs, "ConfigMap", "review-notes")["data"]["notes"]
        self.assertIn("kubectl -n other", notes)
        self.assertIn("-active.other.svc.cluster.local:8200", notes)
        self.assertIn("5 configured", notes)
        hcl = self.resource(docs, "ConfigMap", "openbao-custody-config")["data"]["extraconfig-from-values.hcl"]
        self.assertEqual(hcl.count("leader_api_addr"), 5)
        self.assertIn("openbao-custody-4.openbao-custody-internal", hcl)

    def test_default_storage_tls_and_independence(self):
        docs = self.render()
        sts = self.resource(docs, "StatefulSet")
        self.assertEqual(sts["spec"]["persistentVolumeClaimRetentionPolicy"],
                         {"whenDeleted": "Retain", "whenScaled": "Retain"})
        self.assertEqual(sts["spec"]["updateStrategy"]["type"], "OnDelete")
        self.assertEqual({p["metadata"]["name"] for p in sts["spec"]["volumeClaimTemplates"]}, {"data", "audit"})
        self.assertFalse(any(d["kind"] == "NetworkPolicy" for d in docs))
        containers = sts["spec"]["template"]["spec"]["containers"]
        self.assertEqual(containers[0]["image"], "quay.io/openbao/openbao:2.6.2")
        for pod_spec in (sts["spec"]["template"]["spec"], self.resource(docs, "Pod")["spec"]):
            container = pod_spec["containers"][0]
            self.assertIn("openbao-custody-tls", {v["name"] for v in container["volumeMounts"]})
            env = {v["name"]: v.get("value") for v in container["env"]}
            self.assertEqual(env["BAO_CACERT"], "/openbao/userconfig/openbao-custody-tls/ca.crt")
        umbrella = yaml.safe_load((ROOT / "charts/governance-platform/Chart.yaml").read_text())
        self.assertNotIn("openbao-custody", {dep["name"] for dep in umbrella["dependencies"]})

    def test_dev_profile(self):
        docs = self.render("review", "-f", CHART / "examples/values-dev-kind.yaml")
        self.assertEqual(self.resource(docs, "StatefulSet")["spec"]["replicas"], 1)
        notes = self.resource(docs, "ConfigMap", "review-notes")["data"]["notes"]
        self.assertIn("http://openbao-custody-active.custody.svc.cluster.local:8200", notes)
        self.assertIn("1 configured", notes)
        self.assertIn("disposable clusters only", notes)
        hcl = self.resource(docs, "ConfigMap", "openbao-custody-config")["data"]["extraconfig-from-values.hcl"]
        self.assertIn("tls_disable = 1", hcl)
        self.assertNotIn("retry_join", hcl)

    def test_network_policy_keeps_peers_and_restricts_clients(self):
        docs = self.render("openbao-custody", "-f", CHART / "examples/values-network-policy.yaml")
        spec = self.resource(docs, "NetworkPolicy")["spec"]
        client, peer = spec["ingress"]
        self.assertEqual(client["from"], [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "governance"}}}])
        self.assertEqual({p["port"] for p in client["ports"]}, {8200})
        self.assertEqual({p["port"] for p in peer["ports"]}, {8200, 8201})
        self.assertNotIn("namespaceSelector", peer["from"][0])
        labels = self.resource(docs, "StatefulSet")["spec"]["template"]["metadata"]["labels"]
        self.assertTrue(all(labels[k] == v for k, v in peer["from"][0]["podSelector"]["matchLabels"].items()))
        self.assertNotIn("egress", spec)

    def test_kubernetes_minimum(self):
        result = helm("template", "review", CHART, "--kube-version", "1.29.0", success=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("1.30.0-0", result.stderr)
        self.render(chart=CHART)
        helm("template", "review", CHART, "--kube-version", "1.32.0")

    def test_package(self):
        with tempfile.TemporaryDirectory(prefix="custody-package-check-") as work:
            chart = Path(work) / "openbao-custody"
            shutil.copytree(CHART, chart)
            for filename in (".DS_Store", "test.swp", "test.bak", "test.tmp", "test~", ".git/config", ".idea/test", ".vscode/test"):
                path = chart / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("package exclusion fixture\n")
            helm("package", chart, "--destination", work)
            archive = Path(work) / "openbao-custody-0.1.0.tgz"
            with tarfile.open(archive) as package:
                names = set(package.getnames())
                for filename in ("README.md", "examples/values-dev-kind.yaml", "examples/values-network-policy.yaml", "templates/_helpers.tpl", "templates/NOTES.txt", "Chart.lock", "charts/openbao/Chart.yaml"):
                    self.assertIn("openbao-custody/" + filename, names)
                self.assertFalse(any(name.endswith((".swp", ".bak", ".tmp", "~", ".DS_Store")) or "/.git/" in name or "/.idea/" in name or "/.vscode/" in name for name in names))
                metadata = yaml.safe_load(package.extractfile("openbao-custody/Chart.yaml"))
                self.assertEqual(metadata["version"], "0.1.0")
                self.assertEqual(metadata["appVersion"], "2.6.2")
                upstream = yaml.safe_load(package.extractfile("openbao-custody/charts/openbao/Chart.yaml"))
                self.assertEqual(upstream["version"], "0.29.5")
                self.assertEqual(upstream["kubeVersion"], metadata["kubeVersion"])
            helm("lint", archive, "--strict")
            self.render(chart=archive)


if __name__ == "__main__":
    unittest.main(verbosity=2)
