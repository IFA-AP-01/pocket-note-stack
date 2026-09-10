import SwiftUI

enum DeckMetrics {
    enum RestPill {
        static let spacing: CGFloat = 5
        static let maxNotes = 14
        static let padding: CGFloat = 8
        static let crossAxisSize: CGFloat = 14
        static let cornerRadius: CGFloat = 6
        static let backgroundOpacity: Double = 0.3
        static let shadowRadius: CGFloat = 5
        static let shadowOpacity: Double = 0.24
        
        static let dashCornerRadius: CGFloat = 2.5
        static let dashLength: CGFloat = 16
        static let dashThickness: CGFloat = 7
    }

    enum Fan {
        static func crossAxisSize(on axis: DeckMainAxis) -> CGFloat {
            Tab.closedDepthLabelled(on: axis)
        }
        static let crossAxisSize: CGFloat = 36
        static let layoutSpacing: CGFloat = 8
        static func tabSpacingLabelled(on axis: DeckMainAxis) -> CGFloat {
            Tab.exposedLengthLabelled(on: axis) - Tab.closedLengthLabelled(on: axis)
        }
        static var tabSpacingLabelled: CGFloat {
            Tab.exposedLengthLabelled(on: .horizontal) - Tab.closedLengthLabelled(on: .horizontal)
        }
        static let tabSpacingUnlabelled: CGFloat = 6
    }

    enum Tab {
        static func closedDepthLabelled(on axis: DeckMainAxis) -> CGFloat {
            switch axis {
            case .horizontal: 36
            case .vertical: 36
            }
        }
        static let closedDepthLabelled: CGFloat = 36
        static let closedDepthUnlabelled: CGFloat = 20
        static func closedLengthLabelled(on axis: DeckMainAxis) -> CGFloat {
            switch axis {
            case .horizontal: 220
            case .vertical: 160
            }
        }
        static let closedLengthUnlabelled: CGFloat = 28
        static func exposedLengthLabelled(on axis: DeckMainAxis) -> CGFloat {
            switch axis {
            case .horizontal: 160
            case .vertical: 80
            }
        }
        static let exposedLengthLabelled: CGFloat = 80
        static let hoverDepthIncrease: CGFloat = 0
        
        static let shadowRadiusActive: CGFloat = 8
        static let shadowRadiusIdle: CGFloat = 4
        static let shadowOpacityActive: Double = 0.25
        static let shadowOpacityIdle: Double = 0.16
        
        static func previewSize(on axis: DeckMainAxis) -> CGSize {
            switch axis {
            case .horizontal: CGSize(width: 220, height: 160)
            case .vertical: CGSize(width: 240, height: 160)
            }
        }
        static let previewWidth: CGFloat = 240
        static let previewHeight: CGFloat = 160
        static let previewSize = CGSize(width: previewWidth, height: previewHeight)
        static let expansionTolerance: CGFloat = 2
        
        static let pinIndicatorSize: CGFloat = 6
        static let pinIndicatorPadding: CGFloat = 8
        
        static let cornerRadius: CGFloat = 14
        static let borderLineWidth: CGFloat = 2
        
        static let closedContentThickness: CGFloat = 10
        static let closedContentLength: CGFloat = 20
        static let closedContentCornerRadius: CGFloat = 3
        
        static let previewStripThickness: CGFloat = 12
        
        static let titleFontSize: CGFloat = 10.5
        static let titleTracking: CGFloat = 1.2
        static let titleInset: CGFloat = 4
        
        static let contentPadding: CGFloat = 14
        static let bodyFontSize: CGFloat = 13
        static let bodyLineSpacing: CGFloat = 2
        static let bodyLineLimit = 6
    }

    enum Navigation {
        static let buttonSize: CGFloat = 26
        static let iconSize: CGFloat = 10
        static let opacityEnabled: Double = 0.86
        static let opacityDisabled: Double = 0.28
        static let backgroundOpacityEnabled: Double = 0.42
        static let backgroundOpacityDisabled: Double = 0.20
    }

    enum EmptyTab {
        static let fontSize: CGFloat = 9
        static let length: CGFloat = 150
        static let depth: CGFloat = 46
        static let cornerRadius: CGFloat = 10
    }

    enum AddButton {
        static let size: CGFloat = 28
        static let iconSize: CGFloat = 12
        static let iconOpacity: Double = 0.88
        static let backgroundOpacity: Double = 0.44
        static let hoverScale: CGFloat = 1.08
        static let shadowRadius: CGFloat = 5
        static let shadowY: CGFloat = 2
    }
    
    enum Transitions {
        static let stagedOffset: CGFloat = 90
        static let hiddenOffset: CGFloat = 50
        static let shadowOffsetLength: CGFloat = 3
        static let shadowOffsetDepth: CGFloat = 2
        static let collapseAdditionalOffset: CGFloat = 84
    }
    
    enum Animation {
        static let hoverDuration: TimeInterval = 0.14
        static let hoverPreviewDelay: TimeInterval = 0.2
        static let hoverVelocityThreshold: CGFloat = 50
        static let hoverOpenDelay: TimeInterval = 0.3
        static let previewSpringResponse: Double = 0.30
        static let previewSpringDamping: Double = 0.95
        static let openSpringResponse: Double = 0.28
        static let openSpringDamping: Double = 0.95
        static let expandSpringResponse: Double = 0.30
        static let expandSpringDamping: Double = 0.95
        static let stageSpringResponse: Double = 0.36
        static let stageSpringDamping: Double = 0.95
        static let stageStaggerDelay: Double = 0.045
        static let pressDuration: TimeInterval = 0.11
        static let openDuration: TimeInterval = 0.12
    }
}
