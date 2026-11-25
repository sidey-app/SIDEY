"""Close one finished-turn Herdr worker after the orchestrator collected its result."""
import argparse
import json
import subprocess


def query(*args):
    return json.loads(subprocess.check_output(args, text=True))


def worker_pane(spaces, parent, task, worker, record):
    labels = record.get("labels", {})
    status = record.get("status", {})
    if not (
        parent != worker
        and record.get("address") == worker
        and record.get("parent") == parent
        and labels.get("sidey.owner") == "herdr-workers"
        and task and labels.get("sidey.task") == task
        and isinstance(status, dict) and status.get("app") == "codex"
        and status.get("state") in {"done", "idle"}
    ):
        raise ValueError("Worker identity, ownership, task or idle state did not match")

    for space in spaces:
        for tab in space["tabs"]:
            if space["id"] != labels.get("herdr.space") or tab["id"] != labels.get("herdr.tab"):
                continue
            panes = {p["terminal"]: p["pane"] for p in tab["terminals"] if p.get("app") == "codex"}
            if parent in panes and worker in panes and panes[worker] and panes[worker] != panes[parent]:
                return panes[worker]
    raise ValueError("Parent and worker were not found in the labelled tab")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("parent", "task", "worker"):
        parser.add_argument(name)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    spaces = query("herdr-app", "ls")["spaces"]
    try:
        pane = worker_pane(spaces, args.parent, args.task, args.worker, query("hc", "get", args.worker))
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    if args.dry_run:
        print(pane)
    else:
        subprocess.run(["herdr-app", "do", "pane.close", "--pane", pane], check=True)


if __name__ == "__main__":
    main()
