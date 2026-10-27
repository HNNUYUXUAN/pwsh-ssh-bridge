"""Install runtime files from a reviewed source checkout into a NEW skill directory."""
import argparse
from pathlib import Path
from build import ROOT, inventory, validate


def install(destination, root=ROOT):
    files = inventory(root)
    validate(files)
    destination = destination.expanduser().absolute()
    # Never merge with an existing installation or silently overwrite edits.
    destination.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as output:
            output.write(data)
    return len(files)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path, help='exact new skill directory, including pwsh-ssh-bridge')
    args = parser.parse_args()
    print(f'Installed {install(args.destination)} runtime files into {args.destination}')
