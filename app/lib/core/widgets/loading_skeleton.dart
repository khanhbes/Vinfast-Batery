import 'package:flutter/material.dart';
import 'responsive_card_grid.dart';

import '../theme/luxe_theme.dart';
import 'luxe_kit.dart';

/// Skeleton loading — LUXE: glass frames under a brushed-platinum sweep.
class LoadingSkeleton extends StatelessWidget {
  final SkeletonLayout layout;
  final int itemCount;

  const LoadingSkeleton({
    super.key,
    this.layout = SkeletonLayout.card,
    this.itemCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Đang tải',
      child: ExcludeSemantics(child: LuxeShimmer(child: _buildLayout())),
    );
  }

  Widget _buildLayout() {
    switch (layout) {
      case SkeletonLayout.card:
        return _buildCardSkeleton();
      case SkeletonLayout.list:
        return _buildListSkeleton();
      case SkeletonLayout.stats:
        return _buildStatsSkeleton();
      case SkeletonLayout.gauge:
        return _buildGaugeSkeleton();
    }
  }

  Widget _buildCardSkeleton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LuxeColors.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LuxeColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: LuxeColors.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: LuxeColors.raised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 120,
                      decoration: BoxDecoration(
                        color: LuxeColors.raised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 10,
            width: double.infinity,
            decoration: BoxDecoration(
              color: LuxeColors.raised,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 10,
            width: 200,
            decoration: BoxDecoration(
              color: LuxeColors.raised,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSkeleton() {
    return Column(
      children: List.generate(
        itemCount,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: LuxeColors.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: LuxeColors.hairline),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: LuxeColors.raised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 140,
                        decoration: BoxDecoration(
                          color: LuxeColors.raised,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 100,
                        decoration: BoxDecoration(
                          color: LuxeColors.raised,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 50,
                  decoration: BoxDecoration(
                    color: LuxeColors.raised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSkeleton() {
    return ResponsiveCardGrid(
      children: List.generate(
        4,
        (_) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: LuxeColors.glass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LuxeColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: LuxeColors.raised,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 18,
                width: 60,
                decoration: BoxDecoration(
                  color: LuxeColors.raised,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                width: 80,
                decoration: BoxDecoration(
                  color: LuxeColors.raised,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGaugeSkeleton() {
    return Center(
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          color: LuxeColors.raised,
          shape: BoxShape.circle,
          border: Border.all(color: LuxeColors.hairline, width: 8),
        ),
      ),
    );
  }
}

enum SkeletonLayout { card, list, stats, gauge }
