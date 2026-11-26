String featureError(Object error, String fallback) => switch (error) {
  FormatException(:final message) => message,
  StateError(:final message) => message,
  UnsupportedError(:final message) => message?.toString() ?? fallback,
  _ => fallback,
};
