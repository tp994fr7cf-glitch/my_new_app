import datetime
import os
import random
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import firebase_admin
from firebase_admin import credentials, firestore


COURSE_TITLE_TARGET = "数学 方程式入門"
LESSON_NUMBER_TARGET = 1
SEED_PREFIX = "SEED0604"
RANDOM_SEED = 604


@dataclass
class UserInfo:
    uid: str
    display_name: str
    role: str


@dataclass
class QuestionInfo:
    id: str
    author: UserInfo
    body: str
    is_public: bool
    target: str
    created_at: datetime.datetime


@dataclass
class AnswerInfo:
    id: str
    author: UserInfo
    question_id: str
    body: str
    created_at: datetime.datetime


def normalize_title(text: str) -> str:
    return text.replace("　", " ").strip()


def now_utc() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def ts(base: datetime.datetime, sec: int) -> datetime.datetime:
    return base + datetime.timedelta(seconds=sec)


def is_teacher_user(data: Dict) -> bool:
    active_role = data.get("activeRole")
    roles = data.get("roles")
    if active_role == "teacher":
        return True
    if isinstance(roles, list) and "teacher" in roles:
        return True
    return False


def make_note_title(user_idx: int, note_idx: int) -> str:
    return f"{SEED_PREFIX}-N{user_idx + 1}{note_idx + 1}"


def make_note_body(user_idx: int, note_idx: int) -> str:
    samples = [
        "方程式の移項手順を簡潔に整理したメモです",
        "計算時の符号ミスを防ぐ確認ポイントです",
        "一次方程式を解く流れを短くまとめました",
        "途中式を省かず丁寧に書く練習メモです",
        "分数方程式で最小公倍数を使う手順メモです",
    ]
    return f"{SEED_PREFIX} {samples[(user_idx + note_idx) % len(samples)]}"


def make_question_body(user_idx: int, question_idx: int) -> str:
    samples = [
        "この解き方で符号が変わる理由を確認したいです",
        "先生だけ回答可で途中式の見方を教えてください",
        "公開質問です。別の解き方があれば知りたいです",
        "先生にだけ表示でつまずいた点を相談したいです",
        "引用メモの手順で計算しても合わず確認したいです",
    ]
    return f"{SEED_PREFIX} {samples[(user_idx + question_idx) % len(samples)]}"


def make_answer_body(user_idx: int, answer_idx: int) -> str:
    samples = [
        "途中式を一行ずつ確認するとミスを減らせます",
        "符号は両辺に同じ操作をした結果として変わります",
        "分母を払った後に必ず検算すると安心です",
        "先に移項し最後に係数で割ると整理しやすいです",
        "その手順で正しいです。次は速度を意識しましょう",
        "質問ありがとうございます。ここは公式より整理が大事です",
        "この返信はスレッド動作確認用のサンプルです",
        "他者回答への返信として整合性を確認する例です",
        "さらに返信を重ねる動作を確認するためのコメントです",
        "引用あり回答の表示確認を行うためのテキストです",
    ]
    return f"{SEED_PREFIX} {samples[(user_idx + answer_idx) % len(samples)]}"


class BatchWriter:
    def __init__(self, db: firestore.Client):
        self.db = db
        self.batch = db.batch()
        self.ops = 0

    def set(self, ref, data: Dict):
        self.batch.set(ref, data)
        self.ops += 1
        if self.ops >= 450:
            self.flush()

    def flush(self):
        if self.ops == 0:
            return
        self.batch.commit()
        self.batch = self.db.batch()
        self.ops = 0


def main():
    random.seed(RANDOM_SEED)
    try:
        firebase_admin.get_app()
    except ValueError:
        firebase_admin.initialize_app(credentials.ApplicationDefault())

    db = firestore.client()
    writer = BatchWriter(db)
    base_time = now_utc()

    users_snapshot = db.collection("users").stream()
    users: List[UserInfo] = []
    students: List[UserInfo] = []
    teachers: List[UserInfo] = []

    for doc in users_snapshot:
        data = doc.to_dict() or {}
        profile_name = data.get("displayName") or data.get("name") or ""
        email = data.get("email") or ""
        display_name = profile_name or email or f"user-{doc.id[:6]}"
        role = "teacher" if is_teacher_user(data) else "student"
        info = UserInfo(uid=doc.id, display_name=display_name, role=role)
        users.append(info)
        if role == "teacher":
            teachers.append(info)
        else:
            students.append(info)

    print(f"users_total={len(users)} students={len(students)} teachers={len(teachers)}")
    if len(users) == 0:
        raise RuntimeError("usersコレクションが空のため中断しました。")

    if len(users) != 5 and os.getenv("ALLOW_NON5_USERS") != "1":
        raise RuntimeError(
            "ユーザー総数が5ではありません。確認後に続行する場合は "
            "ALLOW_NON5_USERS=1 を付けて再実行してください。"
        )

    courses = list(db.collection("courses").stream())
    course_doc = None
    for doc in courses:
        data = doc.to_dict() or {}
        title = str(data.get("title", ""))
        if normalize_title(title) == normalize_title(COURSE_TITLE_TARGET):
            course_doc = doc
            break
    if course_doc is None:
        raise RuntimeError("対象講座「数学 方程式入門」が見つかりませんでした。")

    course = course_doc.to_dict() or {}
    course_id = course_doc.id
    course_title = str(course.get("title", "数学 方程式入門"))
    lessons = course.get("lessons") or []
    lesson_title = "レッスン1"
    lesson_index = LESSON_NUMBER_TARGET - 1
    if isinstance(lessons, list) and 0 <= lesson_index < len(lessons):
        lesson = lessons[lesson_index] or {}
        lesson_title = str(lesson.get("title", lesson_title))
    interaction_setting_id = f"{course_id}_{LESSON_NUMBER_TARGET}"

    settings_ref = db.collection("lessonInteractionSettings").document(interaction_setting_id)
    writer.set(
        settings_ref,
        {
            "courseId": course_id,
            "lessonNumber": LESSON_NUMBER_TARGET,
            "lessonNotesPublicEnabled": True,
            "lessonQuestionsPublicEnabled": True,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        },
    )

    notes_by_user: Dict[str, List[Dict]] = {u.uid: [] for u in students}
    questions: List[QuestionInfo] = []
    answers: List[AnswerInfo] = []

    # 1) Public notes: each student 5
    for u_idx, user in enumerate(students):
        for n_idx in range(5):
            note_id = f"{SEED_PREFIX.lower()}-note-{user.uid[:8]}-{n_idx + 1}"
            created = ts(base_time, u_idx * 300 + n_idx * 10)
            title = make_note_title(u_idx, n_idx)[:20]
            body = make_note_body(u_idx, n_idx)
            allows_question_citation = n_idx % 2 == 0
            note_data = {
                "noteId": note_id,
                "userId": user.uid,
                "authorId": user.uid,
                "authorName": user.display_name,
                "title": title,
                "body": body,
                "folderId": "",
                "folderName": "",
                "courseId": course_id,
                "courseTitle": course_title,
                "interactionSettingId": interaction_setting_id,
                "lessonNumber": LESSON_NUMBER_TARGET,
                "lessonTitle": lesson_title,
                "visibility": "public",
                "studentVisibility": "public",
                "tags": [SEED_PREFIX.lower(), "memo"],
                "attachmentTypes": [],
                "hasAudioAttachment": False,
                "sourceNoteId": None,
                "sourceAuthorId": None,
                "isCopied": False,
                "canPublish": True,
                "allowsQuestionCitation": allows_question_citation,
                "hasPublicMirror": True,
                "isDeleted": False,
                "moderationStatus": "visible",
                "favoriteCount": 0,
                "ratingAverage": 0.0,
                "ratingCount": 0,
                "copyCount": 0,
                "createdAt": created,
                "updatedAt": created,
                "publicPublishedAt": created,
            }
            writer.set(
                db.collection("users").document(user.uid).collection("lessonNotes").document(note_id),
                note_data,
            )
            writer.set(db.collection("publicLessonNotes").document(note_id), note_data)
            notes_by_user[user.uid].append(
                {
                    "id": note_id,
                    "title": title,
                    "body": body,
                    "createdAt": created,
                    "allowsQuestionCitation": allows_question_citation,
                }
            )

    # 2) Questions: each student 5
    for u_idx, user in enumerate(students):
        user_notes = notes_by_user[user.uid]
        quotable_note = next((n for n in user_notes if n["allowsQuestionCitation"]), None)
        for q_idx in range(5):
            q_id = f"{SEED_PREFIX.lower()}-q-{user.uid[:8]}-{q_idx + 1}"
            created = ts(base_time, 2000 + u_idx * 300 + q_idx * 11)
            is_public = q_idx in (0, 2, 4)
            target = "everyone" if q_idx in (0, 4) else "teacher"
            quote_enabled = q_idx in (0, 3) and quotable_note is not None
            body = make_question_body(u_idx, q_idx)
            q_data = {
                "questionId": q_id,
                "userId": user.uid,
                "authorId": user.uid,
                "authorName": user.display_name,
                "authorDisplayName": None,
                "authorRole": "student",
                "courseId": course_id,
                "courseTitle": course_title,
                "interactionSettingId": interaction_setting_id,
                "lessonNumber": LESSON_NUMBER_TARGET,
                "lessonTitle": lesson_title,
                "title": "",
                "body": body,
                "visibility": "public" if is_public else "teacherOnly",
                "studentVisibility": "public" if is_public else "teacherOnly",
                "target": target,
                "attachmentTypes": [],
                "quotedNoteId": quotable_note["id"] if quote_enabled else None,
                "quotedNoteTitle": quotable_note["title"] if quote_enabled else None,
                "quotedNoteBody": quotable_note["body"] if quote_enabled else None,
                "status": "open",
                "answerCount": 0,
                "isDeleted": False,
                "moderationStatus": "visible",
                "createdAt": created,
                "updatedAt": created,
            }
            writer.set(
                db.collection("users")
                .document(user.uid)
                .collection("lessonQuestions")
                .document(q_id),
                q_data,
            )
            if is_public:
                writer.set(db.collection("publicLessonQuestions").document(q_id), q_data)

            questions.append(
                QuestionInfo(
                    id=q_id,
                    author=user,
                    body=body,
                    is_public=is_public,
                    target=target,
                    created_at=created,
                )
            )

    public_questions = [q for q in questions if q.is_public]
    if not public_questions:
        raise RuntimeError("公開質問が生成されなかったため中断しました。")

    # 3) Answers: each user 10 (teacher included)
    answer_seq = 0
    for u_idx, user in enumerate(users):
        own_questions = [q for q in questions if q.author.uid == user.uid]
        other_questions = [q for q in public_questions if q.author.uid != user.uid]
        base_q = own_questions[0] if own_questions else public_questions[0]
        alt_q = other_questions[0] if other_questions else public_questions[-1]

        for a_idx in range(10):
            answer_seq += 1
            a_id = f"{SEED_PREFIX.lower()}-a-{user.uid[:8]}-{a_idx + 1}"
            created = ts(base_time, 4000 + answer_seq * 9)
            body = make_answer_body(u_idx, a_idx)

            if a_idx in (0, 5):
                parent_type = "question"
                question_ref = base_q
                parent_id = question_ref.id
                reply_to_author_id = question_ref.author.uid
                reply_to_author_role = question_ref.author.role
                reply_to_display_name = question_ref.author.display_name
                reply_to_body_preview = question_ref.body[:24]
                reply_to_created_at = question_ref.created_at
            elif a_idx in (1, 6):
                parent_type = "question"
                question_ref = alt_q
                parent_id = question_ref.id
                reply_to_author_id = question_ref.author.uid
                reply_to_author_role = question_ref.author.role
                reply_to_display_name = question_ref.author.display_name
                reply_to_body_preview = question_ref.body[:24]
                reply_to_created_at = question_ref.created_at
            else:
                parent_candidates = [a for a in answers if a.author.uid != user.uid]
                if not parent_candidates:
                    parent_candidates = answers[:]
                parent = parent_candidates[-1]
                question_ref = next(q for q in questions if q.id == parent.question_id)
                parent_type = "answer"
                parent_id = parent.id
                reply_to_author_id = parent.author.uid
                reply_to_author_role = parent.author.role
                reply_to_display_name = parent.author.display_name
                reply_to_body_preview = parent.body[:24]
                reply_to_created_at = parent.created_at

            quote_note = None
            if a_idx in (5, 9):
                owner_notes = notes_by_user.get(question_ref.author.uid) or []
                quote_note = next(
                    (n for n in owner_notes if n["allowsQuestionCitation"]),
                    None,
                )

            author_display_name = "先生" if user.role == "teacher" else None
            answer_data = {
                "answerId": a_id,
                "questionId": question_ref.id,
                "courseId": course_id,
                "courseTitle": course_title,
                "lessonNumber": LESSON_NUMBER_TARGET,
                "lessonTitle": lesson_title,
                "authorId": user.uid,
                "authorName": user.display_name,
                "authorDisplayName": author_display_name,
                "authorRole": user.role,
                "body": body,
                "attachmentTypes": [],
                "parentCommentId": parent_id,
                "parentCommentType": parent_type,
                "replyToAuthorId": reply_to_author_id,
                "replyToAuthorRole": reply_to_author_role,
                "replyToDisplayName": reply_to_display_name,
                "replyToBodyPreview": reply_to_body_preview,
                "replyToCreatedAt": reply_to_created_at,
                "quotedNoteId": quote_note["id"] if quote_note else None,
                "quotedNoteTitle": quote_note["title"] if quote_note else None,
                "quotedNoteBody": quote_note["body"] if quote_note else None,
                "isDeleted": False,
                "moderationStatus": "visible",
                "createdAt": created,
                "updatedAt": created,
            }

            writer.set(
                db.collection("users")
                .document(user.uid)
                .collection("lessonQuestionAnswers")
                .document(a_id),
                answer_data,
            )
            if question_ref.is_public:
                writer.set(
                    db.collection("publicLessonQuestionAnswers").document(a_id),
                    answer_data,
                )

            answers.append(
                AnswerInfo(
                    id=a_id,
                    author=user,
                    question_id=question_ref.id,
                    body=body,
                    created_at=created,
                )
            )

    writer.flush()

    print("---- seed completed ----")
    print(f"course_id={course_id} lesson_number={LESSON_NUMBER_TARGET}")
    print(f"notes_created={len(students) * 5} (students only)")
    print(f"questions_created={len(students) * 5} (students only)")
    print(f"answers_created={len(users) * 10} (all users)")
    print(
        f"formula_check=(students*10)+(users*10)={(len(students) * 10) + (len(users) * 10)}"
    )


if __name__ == "__main__":
    main()
