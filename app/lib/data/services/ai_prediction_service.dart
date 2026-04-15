import 'package:flutter_riverpod/flutter_riverpod.dart';

// =============================================================================
// AI PREDICTION SERVICE — DEPRECATED (HTTP calls removed)
// =============================================================================
//
// Dữ liệu AI giờ được đọc từ Firestore qua AiInsightsRepository.
// File này giữ lại provider placeholder để các import cũ không lỗi,
// nhưng tất cả logic gọi HTTP AI API đã bị xóa theo PLAN1.
//
// Xem: data/repositories/ai_insights_repository.dart
// =============================================================================

/// Provider giữ lại để không break import cũ.
/// Các consumer cũ nên migrate sang aiInsightProvider từ ai_insights_repository.
final aiPredictionServiceProvider = Provider<AiPredictionServiceStub>((ref) {
  return AiPredictionServiceStub();
});

/// Stub class — không còn gọi HTTP AI API
class AiPredictionServiceStub {
  // Không còn baseUrl, không gọi HTTP
  // Các consumer cũ sẽ được migrate dần sang aiInsightProvider
}
