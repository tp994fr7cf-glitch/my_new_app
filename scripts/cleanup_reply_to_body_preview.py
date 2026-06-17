import argparse
from dataclasses import dataclass
from typing import Iterable, List

import firebase_admin
from firebase_admin import credentials, firestore


@dataclass
class CleanupStats:
    scanned: int = 0
    matched: int = 0
    updated: int = 0


def ensure_app() -> None:
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(credentials.ApplicationDefault())


def chunked(items: List[str], size: int) -> Iterable[List[str]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def collect_targets(
    db: firestore.Client,
    collection_name: str,
    *,
    use_collection_group: bool,
) -> tuple[List[str], int]:
    if use_collection_group:
        docs = db.collection_group(collection_name).stream()
    else:
        docs = db.collection(collection_name).stream()

    targets: List[str] = []
    scanned = 0
    for doc in docs:
        scanned += 1
        data = doc.to_dict() or {}
        if "replyToBodyPreview" in data:
            targets.append(doc.reference.path)
    return targets, scanned


def apply_cleanup(
    db: firestore.Client,
    targets: List[str],
    *,
    dry_run: bool,
    batch_size: int = 400,
) -> int:
    if dry_run or not targets:
        return 0

    updated = 0
    for batch_paths in chunked(targets, batch_size):
        batch = db.batch()
        for path in batch_paths:
            ref = db.document(path)
            batch.update(ref, {"replyToBodyPreview": firestore.DELETE_FIELD})
        batch.commit()
        updated += len(batch_paths)
    return updated


def run(dry_run: bool) -> None:
    ensure_app()
    db = firestore.client()

    stats = CleanupStats()

    user_subcollection_targets, user_scanned = collect_targets(
        db,
        "lessonQuestionAnswers",
        use_collection_group=True,
    )
    public_targets, public_scanned = collect_targets(
        db,
        "publicLessonQuestionAnswers",
        use_collection_group=False,
    )

    stats.matched = len(user_subcollection_targets) + len(public_targets)
    stats.scanned = user_scanned + public_scanned

    print("=== replyToBodyPreview cleanup ===")
    print(f"dry_run={dry_run}")
    print(
        "targets:"
        f" users/*/lessonQuestionAnswers={len(user_subcollection_targets)},"
        f" publicLessonQuestionAnswers={len(public_targets)}"
    )

    stats.updated += apply_cleanup(
        db,
        user_subcollection_targets,
        dry_run=dry_run,
    )
    stats.updated += apply_cleanup(
        db,
        public_targets,
        dry_run=dry_run,
    )

    print(
        "result:"
        f" scanned={stats.scanned}, matched={stats.matched}, updated={stats.updated}"
    )
    if dry_run:
        print("Dry run only. Re-run with --apply to execute updates.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Remove replyToBodyPreview from lesson question answer documents."
        )
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply updates. Without this flag, runs dry-run only.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run(dry_run=not args.apply)
