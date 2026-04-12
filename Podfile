# Eidos Podfile
#
# LiteRT-LM integration is DEFERRED to Phase 2 (first Mac session).
# See plan.md §A1 for rationale — the spec's MediaPipeTasksGenAI pod
# is deprecated and is NOT used here.
#
# On the first Mac session:
#   1. Check github.com/google-ai-edge/LiteRT-LM for the current iOS
#      distribution mechanism (SPM, prebuilt xcframework, or source build).
#   2. If CocoaPods-based, add the pod entry below and run `pod install`.
#   3. If SPM-based, remove this Podfile entirely and add the dependency
#      via Xcode's Package Dependencies UI (or update project.yml with
#      a `packages:` section).

platform :ios, '17.0'
use_frameworks!

target 'Eidos' do
  # TODO(phase 2): pod 'LiteRT-LM' or equivalent — confirm on Mac.
end

target 'EidosShareExtension' do
  # Share Extension stays lightweight — no inference pods here.
end
