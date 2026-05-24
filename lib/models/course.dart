class Course {
  const Course({
    required this.title,
    required this.instructorName,
    required this.category,
    required this.level,
    required this.duration,
    required this.lessonCount,
    required this.rating,
    required this.priceLabel,
    required this.description,
    required this.lessons,
  });

  final String title;
  final String instructorName;
  final String category;
  final String level;
  final String duration;
  final int lessonCount;
  final double rating;
  final String priceLabel;
  final String description;
  final List<CourseLesson> lessons;
}

class CourseLesson {
  const CourseLesson({
    required this.title,
    required this.duration,
    this.isPreview = false,
  });

  final String title;
  final String duration;
  final bool isPreview;
}
