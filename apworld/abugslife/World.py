"""Compatibility shim.

Archipelago worlds are discovered via the package's __init__.py.
Older drafts of this project had a separate World.py with an unfinished implementation.

Keeping this file avoids import errors if anything still references `worlds.abl.World`.
"""

from .__init__ import BugsLifeWorld as ABLWorld, BugsLifeWeb as ABLWeb  # noqa: F401
