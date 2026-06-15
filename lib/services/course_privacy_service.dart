import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/course_privacy_consent.dart';
import '../models/course_privacy_policy.dart';

class CoursePrivacyService {
  const CoursePrivacyService();

  CollectionReference<Map<String, dynamic>> get _courses =>
      FirebaseFirestore.instance.collection('courses');

  DocumentReference<Map<String, dynamic>> _courseRef(String courseId) =>
      _courses.doc(courseId);

  DocumentReference<Map<String, dynamic>> _consentRef({
    required String userId,
    required String courseId,
  }) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('coursePrivacyConsents')
        .doc(courseId);
  }

  DocumentReference<Map<String, dynamic>> _teacherLegalNameShareRef({
    required String courseId,
    required String userId,
  }) {
    return _courseRef(
      courseId,
    ).collection('teacherLegalNameShares').doc(userId);
  }

  DocumentReference<Map<String, dynamic>> _peerLegalNameShareRef({
    required String courseId,
    required String token,
  }) {
    return _courseRef(courseId).collection('peerLegalNames').doc(token);
  }

  Stream<CoursePrivacyPolicy> policyStream(String courseId) {
    if (Firebase.apps.isEmpty || courseId.isEmpty) {
      return Stream.value(CoursePrivacyPolicy.empty);
    }
    return _courseRef(courseId).snapshots().map((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      return CoursePrivacyPolicy.fromCourseMap(data).normalized();
    });
  }

  Future<CoursePrivacyPolicy> loadPolicy(String courseId) async {
    if (Firebase.apps.isEmpty || courseId.isEmpty) {
      return CoursePrivacyPolicy.empty;
    }
    try {
      final snapshot = await _courseRef(courseId).get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      return CoursePrivacyPolicy.fromCourseMap(data).normalized();
    } on FirebaseException {
      return CoursePrivacyPolicy.empty;
    }
  }

  Stream<CoursePrivacyConsent?> consentStream({
    required String userId,
    required String courseId,
  }) {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return Stream.value(null);
    }
    return _consentRef(userId: userId, courseId: courseId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return null;
      }
      return CoursePrivacyConsent.fromFirestore(snapshot);
    });
  }

  Future<CoursePrivacyConsent?> loadConsent({
    required String userId,
    required String courseId,
  }) async {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return null;
    }
    try {
      final snapshot = await _consentRef(
        userId: userId,
        courseId: courseId,
      ).get();
      if (!snapshot.exists) {
        return null;
      }
      return CoursePrivacyConsent.fromFirestore(snapshot);
    } on FirebaseException {
      return null;
    }
  }

  Future<String?> loadLegalName(String userId) async {
    if (Firebase.apps.isEmpty || userId.isEmpty) {
      return null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final value = (snapshot.data()?['legalName'] as String?)?.trim();
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    } on FirebaseException {
      return null;
    }
  }

  Future<void> setLegalNameIfAbsent({
    required String userId,
    required String legalName,
  }) async {
    if (Firebase.apps.isEmpty || userId.isEmpty) {
      return;
    }
    final trimmed = legalName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('legalName is empty');
    }
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final existing = (snapshot.data()?['legalName'] as String?)?.trim() ?? '';
      if (existing.isNotEmpty && existing != trimmed) {
        throw StateError('本名は登録後に変更できません。');
      }
      if (existing.isNotEmpty) {
        return;
      }
      transaction.set(userRef, {
        'legalName': trimmed,
        'legalNameLockedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<CourseEntryRequirement> evaluateEntryRequirement({
    required String userId,
    required String courseId,
  }) async {
    final policy = await loadPolicy(courseId);
    final consent = await loadConsent(userId: userId, courseId: courseId);
    final legalName = await loadLegalName(userId);
    return CourseEntryRequirement(
      policy: policy,
      consent: consent,
      legalName: legalName,
      isResolved: true,
    );
  }

  Stream<CourseEntryRequirement> watchEntryRequirement({
    required String userId,
    required String courseId,
  }) {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return Stream.value(
        const CourseEntryRequirement(
          policy: CoursePrivacyPolicy.empty,
          consent: null,
          legalName: null,
          isResolved: true,
        ),
      );
    }
    return Stream.multi((controller) {
      CoursePrivacyPolicy? latestPolicy;
      CoursePrivacyConsent? latestConsent;
      String? latestLegalName;
      var hasPolicy = false;
      var hasConsent = false;
      var hasLegalName = false;

      void emitIfReady() {
        if (!hasPolicy || latestPolicy == null) {
          return;
        }
        final isResolved = hasPolicy && hasConsent && hasLegalName;
        controller.add(
          CourseEntryRequirement(
            policy: latestPolicy!,
            consent: latestConsent,
            legalName: latestLegalName,
            isResolved: isResolved,
          ),
        );
      }

      final policySub = policyStream(courseId).listen((policy) {
        latestPolicy = policy;
        hasPolicy = true;
        emitIfReady();
      }, onError: controller.addError);

      final consentSub = consentStream(userId: userId, courseId: courseId)
          .listen((consent) {
            latestConsent = consent;
            hasConsent = true;
            emitIfReady();
          }, onError: controller.addError);

      final legalNameSub = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots()
          .listen((snapshot) {
            final value = (snapshot.data()?['legalName'] as String?)?.trim();
            latestLegalName = (value ?? '').isEmpty ? null : value;
            hasLegalName = true;
            emitIfReady();
          }, onError: controller.addError);

      controller.onCancel = () async {
        await policySub.cancel();
        await consentSub.cancel();
        await legalNameSub.cancel();
      };
    });
  }

  Future<void> saveConsent({
    required String userId,
    required String courseId,
    required CoursePrivacyPolicy policy,
    required bool agreeInstructorShare,
    required bool agreePeerShare,
    required String legalName,
  }) async {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return;
    }
    final normalizedPolicy = policy.normalized();
    if (normalizedPolicy.shareAmongLearnersEnabled &&
        !normalizedPolicy.shareWithInstructorEnabled) {
      throw StateError('受講者同士の本名公開は先生共有の有効化が必要です。');
    }
    if (normalizedPolicy.shareWithInstructorEnabled && !agreeInstructorShare) {
      throw StateError('先生への本名共有への同意が必要です。');
    }
    if (normalizedPolicy.shareAmongLearnersEnabled && !agreePeerShare) {
      throw StateError('受講者同士の本名共有への同意が必要です。');
    }
    final safeLegalName = legalName.trim();
    if (normalizedPolicy.requiresLegalName && safeLegalName.isEmpty) {
      throw StateError('本名の登録が必要です。');
    }

    await setLegalNameIfAbsent(userId: userId, legalName: safeLegalName);
    final consentRef = _consentRef(userId: userId, courseId: courseId);
    final existingConsent = await consentRef.get();
    final existingToken = (existingConsent.data()?['peerShareToken'] as String?)
        ?.trim();
    final token = existingToken?.isNotEmpty == true
        ? existingToken!
        : FirebaseFirestore.instance.collection('tmp').doc().id;

    final batch = FirebaseFirestore.instance.batch();
    batch.set(consentRef, {
      'courseId': courseId,
      'userId': userId,
      'acceptedPolicyVersion': normalizedPolicy.consentPolicyVersion,
      'acceptedInstructorLegalNameShare': agreeInstructorShare,
      'acceptedPeerLegalNameShare': agreePeerShare,
      'peerShareToken': agreePeerShare ? token : null,
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final teacherShareRef = _teacherLegalNameShareRef(
      courseId: courseId,
      userId: userId,
    );
    if (agreeInstructorShare) {
      batch.set(teacherShareRef, {
        'courseId': courseId,
        'userId': userId,
        'legalName': safeLegalName,
        'acceptedPolicyVersion': normalizedPolicy.consentPolicyVersion,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      batch.delete(teacherShareRef);
    }

    final peerShareRef = _peerLegalNameShareRef(
      courseId: courseId,
      token: token,
    );
    if (!agreePeerShare && existingToken != null && existingToken.isNotEmpty) {
      batch.delete(peerShareRef);
    }

    await batch.commit();
    try {
      await syncPeerLegalNameShareForEnrollment(
        userId: userId,
        courseId: courseId,
      );
    } on FirebaseException {
      // Consent completion should not fail when peer-share sync is delayed.
    }
  }

  Future<bool> _hasCourseEnrollment({
    required String userId,
    required String courseId,
  }) async {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return false;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('enrollments')
          .doc(courseId)
          .get();
      return snapshot.exists;
    } on FirebaseException {
      return false;
    }
  }

  Future<void> syncPeerLegalNameShareForEnrollment({
    required String userId,
    required String courseId,
  }) async {
    if (Firebase.apps.isEmpty || userId.isEmpty || courseId.isEmpty) {
      return;
    }
    final policy = await loadPolicy(courseId);
    final consent = await loadConsent(userId: userId, courseId: courseId);
    if (consent == null) {
      return;
    }
    final token = (consent.peerShareToken ?? '').trim();
    if (token.isEmpty) {
      return;
    }
    final peerShareRef = _peerLegalNameShareRef(courseId: courseId, token: token);
    final normalizedPolicy = policy.normalized();
    final shouldSharePeerLegalName =
        normalizedPolicy.shareAmongLearnersEnabled &&
        consent.covers(normalizedPolicy);
    if (!shouldSharePeerLegalName) {
      try {
        await peerShareRef.delete();
      } on FirebaseException {
        // Keep consent flow resilient even if cleanup is blocked.
      }
      return;
    }
    final hasEnrollment = await _hasCourseEnrollment(
      userId: userId,
      courseId: courseId,
    );
    if (!hasEnrollment) {
      return;
    }
    final legalName = (await loadLegalName(userId))?.trim() ?? '';
    if (legalName.isEmpty) {
      return;
    }
    await peerShareRef.set({
      'courseId': courseId,
      'legalName': legalName,
      'acceptedPolicyVersion': normalizedPolicy.consentPolicyVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePolicy({
    required String courseId,
    required bool shareWithInstructorEnabled,
    required bool shareAmongLearnersEnabled,
  }) async {
    if (Firebase.apps.isEmpty || courseId.isEmpty) {
      return;
    }
    final normalized = CoursePrivacyPolicy(
      shareWithInstructorEnabled: shareWithInstructorEnabled,
      shareAmongLearnersEnabled: shareAmongLearnersEnabled,
      consentPolicyVersion: 1,
    ).normalized();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final ref = _courseRef(courseId);
      final snapshot = await transaction.get(ref);
      final current = CoursePrivacyPolicy.fromCourseMap(
        snapshot.data() ?? const <String, dynamic>{},
      );
      final changed =
          current.shareWithInstructorEnabled !=
              normalized.shareWithInstructorEnabled ||
          current.shareAmongLearnersEnabled !=
              normalized.shareAmongLearnersEnabled;
      final nextVersion = changed
          ? current.consentPolicyVersion + 1
          : current.consentPolicyVersion;
      transaction.set(ref, {
        coursePrivacyPolicyField: {
          coursePrivacyShareWithInstructorField:
              normalized.shareWithInstructorEnabled,
          coursePrivacyShareAmongLearnersField:
              normalized.shareAmongLearnersEnabled,
          coursePrivacyConsentPolicyVersionField: nextVersion,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Stream<List<String>> peerLegalNamesStream(String courseId) {
    if (Firebase.apps.isEmpty || courseId.isEmpty) {
      return Stream.value(const []);
    }
    return _courseRef(courseId).collection('peerLegalNames').snapshots().map((
      snapshot,
    ) {
      final names =
          snapshot.docs
              .map((doc) => (doc.data()['legalName'] as String?)?.trim() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      return names;
    });
  }
}
