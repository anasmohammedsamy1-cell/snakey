"""Helpers shared by source-level invariant checks.

Each check module remains directly executable and is also collectable by pytest.
"""
import re


def _items(checks):
    return list(checks.items()) if isinstance(checks, dict) else list(checks)


def register_checks(namespace, checks):
    """Expose every named invariant as an individual pytest test function."""
    for index, (name, passed) in enumerate(_items(checks)):
        slug = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
        test_name = f"test_invariant_{index:02d}_{slug or 'unnamed'}"

        def _test(check_name=name, result=bool(passed)):
            assert result, check_name

        _test.__doc__ = name
        namespace[test_name] = _test


def run_checks(checks):
    """Print the familiar CLI report and return a process exit code."""
    items = _items(checks)
    failed = [name for name, passed in items if not passed]
    for name, passed in items:
        print(f"{'PASS' if passed else 'FAIL'}: {name}")
    print(f"{len(items) - len(failed)}/{len(items)} checks passed")
    return 1 if failed else 0
