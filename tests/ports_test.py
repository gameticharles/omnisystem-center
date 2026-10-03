"""Tests for bin/omnisystem-center-ports and bin/omnisystem-center-procs.
Run: python3 -m unittest discover -s tests -p '*_test.py'
"""
import importlib.machinery
import importlib.util
import os
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(os.path.dirname(HERE), "bin")


def load(name):
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), os.path.join(BIN, name))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


P = load("omnisystem-center-ports")
Q = load("omnisystem-center-procs")

SS = """tcp LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=4242,fd=23))
tcp LISTEN 0 511 [::1]:5173 [::]:* users:(("node",pid=4242,fd=24))
tcp LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*
udp UNCONN 0 0 [fe80::1]%wlan0:546 [::]:*
tcp LISTEN 0 128 *:22 *:*
tcp ESTAB 0 0 10.0.0.2:44444 1.1.1.1:443 users:(("curl",pid=7,fd=3))
"""


class PortsParsing(unittest.TestCase):
    def test_addresses(self):
        self.assertEqual(P.split_address("127.0.0.1:5173"), ("127.0.0.1", 5173))
        self.assertEqual(P.split_address("[::1]:631"), ("::1", 631))
        self.assertEqual(P.split_address("127.0.0.53%lo:53"), ("127.0.0.53", 53))
        self.assertEqual(P.split_address("[fe80::1]%wlan0:546"), ("fe80::1", 546))
        self.assertEqual(P.split_address("*:22"), ("0.0.0.0", 22))

    def test_parse_skips_established(self):
        rows = P.parse_ss(SS)
        self.assertEqual([(r["proto"], r["port"]) for r in rows], [("tcp", 5173), ("tcp", 5173), ("tcp", 53), ("udp", 546), ("tcp", 22)])
        self.assertEqual(rows[0]["procs"], [("node", 4242)])
        self.assertEqual(rows[2]["procs"], [])

    def test_reach(self):
        kinds = {"100.101.102.103": "tailscale0", "192.168.1.5": "wlan0", "10.8.0.2": "wg0"}
        self.assertEqual(P.reach("127.0.0.1", kinds), "local")
        self.assertEqual(P.reach("::1", kinds), "local")
        self.assertEqual(P.reach("0.0.0.0", kinds), "network")
        self.assertEqual(P.reach("::", kinds), "network")
        self.assertEqual(P.reach("192.168.1.5", kinds), "network")
        self.assertEqual(P.reach("100.101.102.103", kinds), "vpn")
        self.assertEqual(P.reach("10.8.0.2", kinds), "vpn")
        self.assertEqual(P.reach("172.17.0.1", kinds), "containers")
        self.assertEqual(P.reach("fe80::1", kinds), "local-link")

    def test_stacks(self):
        self.assertEqual(P.stack_of("node /app/node_modules/.bin/vite --port 5173", "node")[0], "Vite")
        self.assertEqual(P.stack_of("python3 manage.py runserver", "python3")[0], "Django")
        self.assertEqual(P.stack_of("python3 -m http.server 8000", "python3")[0], "Python HTTP")
        self.assertEqual(P.stack_of("/usr/bin/node server.js", "node")[0], "Node")
        self.assertEqual(P.stack_of("", "sshd")[0], "")

    def test_project_root_stops_at_home(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = os.path.join(tmp, "my-app")
            os.makedirs(os.path.join(app, "public", "assets"))
            open(os.path.join(app, "package.json"), "w").close()
            self.assertEqual(P.project_root(os.path.join(app, "public", "assets")), app)
        self.assertEqual(P.project_root(os.path.expanduser("~")), "")
        self.assertEqual(P.project_root("/"), "")

    def test_dev(self):
        mine = {"mine": True, "cmd": "/usr/bin/node x.js", "name": "node"}
        other = {"mine": False, "cmd": "/usr/bin/node x.js", "name": "node"}
        self.assertTrue(P.is_dev(5173, mine, ""))
        self.assertTrue(P.is_dev(41234, mine, ""), "a dev runtime anywhere")
        self.assertFalse(P.is_dev(5173, other, ""), "someone else's")
        self.assertFalse(P.is_dev(631, None, ""))
        editor = {"mine": True, "cmd": "/proc/self/exe --type=utility --utility-sub-type=node.mojom.NodeService", "name": "antigravity-ide"}
        stack = P.stack_of(editor["cmd"], editor["name"])[0]
        self.assertEqual(stack, "Node")
        self.assertTrue(P.is_dev(33489, editor, "", stack), "a stack in the command line, as Omaports")
        self.assertFalse(P.is_dev(33489, editor, ""), "without the stack, not")

    def test_scan_names_a_real_listener(self):
        with tempfile.NamedTemporaryFile("w", suffix=".ss", delete=False) as fake:
            fake.write('tcp LISTEN 0 5 0.0.0.0:8765 0.0.0.0:* users:(("python3",pid=%d,fd=3))\n' % os.getpid())
            fake.write("tcp LISTEN 0 5 127.0.0.1:6379 0.0.0.0:*\n")
        os.environ["OMNISYSTEM_PORTS_SS"] = fake.name
        try:
            data = P.scan()
        finally:
            del os.environ["OMNISYSTEM_PORTS_SS"]
            os.unlink(fake.name)
        mine = [r for r in data["listeners"] if r["port"] == 8765][0]
        self.assertEqual((mine["pid"], mine["mine"], mine["reach"], mine["dev"], mine["http"]), (os.getpid(), True, "network", True, True))
        redis = [r for r in data["listeners"] if r["port"] == 6379][0]
        self.assertEqual((redis["name"], redis["guess"], redis["owner"]), ("Redis", True, "system"))

    def test_container_id_is_validated(self):
        result = subprocess.run([os.path.join(BIN, "omnisystem-center-ports"), "stop-container", "x; rm -rf /"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)


class Processes(unittest.TestCase):
    def test_parse_stat_with_spaces_and_parens(self):
        comm, fields = Q.parse_stat("123 (Web (Content) 1) S 1 123 123 0 -1")
        self.assertEqual(comm, "Web (Content) 1")
        self.assertEqual(fields[:2], ["S", "1"])

    def test_cpu_share_needs_the_same_process(self):
        before = {5: {"start": 100, "ticks": 0}, 6: {"start": 100, "ticks": 0}}
        rows = {5: {"start": 100, "ticks": Q.TICK}, 6: {"start": 999, "ticks": Q.TICK}}
        Q.with_cpu(rows, before, 2.0)
        self.assertEqual(rows[5]["cpu"], 50.0)
        self.assertEqual(rows[6]["cpu"], 0.0, "a reused PID starts again")

    def test_signals_are_checked(self):
        child = subprocess.Popen(["sleep", "30"])
        try:
            with open(f"/proc/{child.pid}/stat") as handle:
                start = int(handle.read().rsplit(")", 1)[1].split()[19])
            run = lambda *a: subprocess.run([os.path.join(BIN, "omnisystem-center-procs"), *a], capture_output=True, text=True)
            self.assertIn("already ended", run("signal", str(child.pid), str(start + 1), "TERM").stdout)
            self.assertIn("never signalled", run("signal", "1", "0", "TERM").stdout)
            self.assertIn("unknown signal", run("signal", str(child.pid), str(start), "USR9").stdout)
            done = run("signal", str(child.pid), str(start), "TERM")
            self.assertIn('"ended": true', done.stdout)
        finally:
            child.kill()
            child.wait()

    def test_commands_are_one_line(self):
        child = subprocess.Popen(["sh", "-c", "sleep 30\n# a second line", "x"])
        try:
            time.sleep(0.2)
            rows = Q.sample(Q.users(), Q.mem_total(), Q.boot_time())
            self.assertNotIn("\n", rows[child.pid]["cmd"])
            self.assertIn("# a second line", rows[child.pid]["cmd"])
        finally:
            child.kill()
            child.wait()

    def test_a_tree_ends_children_first(self):
        parent = subprocess.Popen(["sh", "-c", "sleep 30 & sleep 30 & wait"])
        try:
            time.sleep(0.3)
            kids = [pid for pid, _ in Q.descendants(parent.pid)]
            self.assertEqual(len(kids), 2)
            with open(f"/proc/{parent.pid}/stat") as handle:
                start = int(handle.read().rsplit(")", 1)[1].split()[19])
            out = subprocess.run([os.path.join(BIN, "omnisystem-center-procs"), "signal-tree", str(parent.pid), str(start), "TERM"],
                                 capture_output=True, text=True).stdout
            self.assertIn('"children": 2', out)
            time.sleep(0.3)
            for kid in kids:
                state = open(f"/proc/{kid}/stat").read().rsplit(")", 1)[1].split()[0] if os.path.exists(f"/proc/{kid}") else "gone"
                self.assertIn(state, ("gone", "Z"))
        finally:
            parent.kill()
            parent.wait()

    def test_sample_finds_this_process(self):
        rows = Q.sample(Q.users(), Q.mem_total(), Q.boot_time())
        me = rows[os.getpid()]
        self.assertTrue(me["mine"])
        self.assertIn("python", me["name"])
        self.assertGreater(me["rss"], 0)


if __name__ == "__main__":
    unittest.main()
