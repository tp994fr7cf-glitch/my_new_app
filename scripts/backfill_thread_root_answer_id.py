import argparse
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

import firebase_admin
from firebase_admin import credentials, firestore


@dataclass
class AnswerNode:
    path: str
    answer_id: str
    question_id: str
    parent_comment_id: Optional[str]
    parent_comment_type: Optional[str]
    thread_root_answer_id: Optional[str]


@dataclass
class BackfillStats:
    scanned: int = 0
    candidates: int = 0
    resolvable: int = 0
    unresolved: int = 0
    updated: int = 0


def ensure_app() -> None:
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(credentials.ApplicationDefault())


def chunked(items: List[Tuple[str, str]], size: int) -> Iterable[List[Tuple[str, str]]]:
    for i in range(0, len(items), size):
        yield items[i : i + size]


def normalize_id(value: object) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip()


def is_direct_answer(node: AnswerNode) -> bool:
    parent_type = normalize_id(node.parent_comment_type)
    if parent_type == "answer":
        return False
    parent_id = normalize_id(node.parent_comment_id)
    return (
        parent_id == ""
        or parent_id == node.question_id
        or parent_type == "question"
    )


def resolve_root_answer_id(
    node: AnswerNode,
    answers_by_id: Dict[str, AnswerNode],
) -> Optional[str]:
    current = node
    visited: set[str] = set()

    for _ in range(30):
        current_id = normalize_id(current.answer_id)
        if current_id == "" or current_id in visited:
            return None
        visited.add(current_id)

        explicit_root_id = normalize_id(current.thread_root_answer_id)
        if explicit_root_id:
            explicit_root = answers_by_id.get(explicit_root_id)
            if explicit_root is None or not is_direct_answer(explicit_root):
                return None
            return explicit_root_id

        if is_direct_answer(current):
            return current.answer_id

        if normalize_id(current.parent_comment_type) != "answer":
            return None

        parent_id = normalize_id(current.parent_comment_id)
        if parent_id == "":
            return None

        parent = answers_by_id.get(parent_id)
        if parent is None:
            return None
        current = parent
    return None


def collect_nodes_from_collection_group(db: firestore.Client) -> List[AnswerNode]:
    nodes: List[AnswerNode] = []
    for doc in db.collection_group("lessonQuestionAnswers").stream():
        data = doc.to_dict() or {}
        answer_id = normalize_id(doc.id)
        question_id = normalize_id(data.get("questionId"))
        if answer_id == "" or question_id == "":
            continue
        nodes.append(
            AnswerNode(
                path=doc.reference.path,
                answer_id=answer_id,
                question_id=question_id,
                parent_comment_id=data.get("parentCommentId"),
                parent_comment_type=data.get("parentCommentType"),
                thread_root_answer_id=data.get("threadRootAnswerId"),
            )
        )
    return nodes


def collect_nodes_from_public_collection(db: firestore.Client) -> List[AnswerNode]:
    nodes: List[AnswerNode] = []
    for doc in db.collection("publicLessonQuestionAnswers").stream():
        data = doc.to_dict() or {}
        answer_id = normalize_id(doc.id)
        question_id = normalize_id(data.get("questionId"))
        if answer_id == "" or question_id == "":
            continue
        nodes.append(
            AnswerNode(
                path=doc.reference.path,
                answer_id=answer_id,
                question_id=question_id,
                parent_comment_id=data.get("parentCommentId"),
                parent_comment_type=data.get("parentCommentType"),
                thread_root_answer_id=data.get("threadRootAnswerId"),
            )
        )
    return nodes


def build_updates(nodes: List[AnswerNode], stats: BackfillStats) -> List[Tuple[str, str]]:
    updates: List[Tuple[str, str]] = []
    grouped: Dict[str, Dict[str, AnswerNode]] = {}

    for node in nodes:
        grouped.setdefault(node.question_id, {})[node.answer_id] = node

    for answers_by_id in grouped.values():
        for node in answers_by_id.values():
            stats.scanned += 1
            if normalize_id(node.parent_comment_type) != "answer":
                continue
            if normalize_id(node.thread_root_answer_id):
                continue
            stats.candidates += 1
            root_id = resolve_root_answer_id(node, answers_by_id)
            if not root_id:
                stats.unresolved += 1
                continue
            stats.resolvable += 1
            updates.append((node.path, root_id))

    return updates


def apply_updates(
    db: firestore.Client,
    updates: List[Tuple[str, str]],
    *,
    dry_run: bool,
    batch_size: int = 400,
) -> int:
    if dry_run or not updates:
        return 0

    updated = 0
    for items in chunked(updates, batch_size):
        batch = db.batch()
        for path, root_id in items:
            batch.update(db.document(path), {"threadRootAnswerId": root_id})
        batch.commit()
        updated += len(items)
    return updated


def run(dry_run: bool) -> None:
    ensure_app()
    db = firestore.client()

    user_stats = BackfillStats()
    public_stats = BackfillStats()

    user_nodes = collect_nodes_from_collection_group(db)
    public_nodes = collect_nodes_from_public_collection(db)

    user_updates = build_updates(user_nodes, user_stats)
    public_updates = build_updates(public_nodes, public_stats)

    total_updates = user_updates + public_updates
    updated = apply_updates(db, total_updates, dry_run=dry_run)

    print("=== threadRootAnswerId backfill ===")
    print(f"dry_run={dry_run}")
    print(
        "users/*/lessonQuestionAnswers:"
        f" scanned={user_stats.scanned}"
        f" candidates={user_stats.candidates}"
        f" resolvable={user_stats.resolvable}"
        f" unresolved={user_stats.unresolved}"
    )
    print(
        "publicLessonQuestionAnswers:"
        f" scanned={public_stats.scanned}"
        f" candidates={public_stats.candidates}"
        f" resolvable={public_stats.resolvable}"
        f" unresolved={public_stats.unresolved}"
    )
    print(f"update_targets={len(total_updates)}")
    print(f"updated={updated}")
    if dry_run:
        print("Dry run only. Re-run with --apply to execute updates.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Backfill threadRootAnswerId for reply answers."
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
