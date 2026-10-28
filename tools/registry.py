"""Export public module identities from the canonical Hub registry, never a second list."""
import argparse
import json
from pathlib import Path
import sys


def modules(source):
    source = Path(source).resolve()
    sys.path.insert(0, str(source / "tools"))
    from check_hub import parse_registry, find_source
    rows = parse_registry((source / "scripts/hub.lua").read_text(encoding="utf-8"))
    if not rows:
        raise ValueError("canonical Hub registry is empty")
    result = []
    for row in rows:
        path = find_source(row["file"])
        if not path:
            raise ValueError(f"missing canonical module: {row['file']}")
        relative = Path(path).resolve().relative_to(source).as_posix()
        result.append(dict(id=row["id"], gameId=int(row["gameId"]),
                           placeId=int(row["placeId"]), path="games/" + row["file"],
                           source=relative, localName=row["file"]))
    if len({row["gameId"] for row in result}) != len(result):
        raise ValueError("duplicate universe in canonical registry")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(modules(args.source)))
