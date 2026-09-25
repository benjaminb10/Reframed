import AVFoundation
import AppKit

enum CameraHandleCorner: CaseIterable {
  case topLeft, topRight, bottomLeft, bottomRight

  var isLeft: Bool { self == .topLeft || self == .bottomLeft }
  var isTop: Bool { self == .topLeft || self == .topRight }

  var cursor: NSCursor {
    switch self {
    case .topLeft: NSCursor.frameResize(position: .topLeft, directions: .all)
    case .topRight: NSCursor.frameResize(position: .topRight, directions: .all)
    case .bottomLeft: NSCursor.frameResize(position: .bottomLeft, directions: .all)
    case .bottomRight: NSCursor.frameResize(position: .bottomRight, directions: .all)
    }
  }
}

enum CameraDragMode: Equatable {
  case none
  case move
  case resize(CameraHandleCorner)
  case radius
}

extension VideoPreviewContainer {
  static let cameraHandleSize: CGFloat = 10
  static let cameraHandleHitDistance: CGFloat = 10
  static let cameraHoverMargin: CGFloat = 12

  var canEditCameraFrame: Bool {
    coordinator != nil && !webcamWrapper.isHidden && !isCameraFullscreen && currentWebcamSize != nil
  }

  var canEditCameraRadius: Bool {
    canEditCameraFrame && coordinator?.cameraCornerRadius != nil && !currentCameraAspect.isCircle
  }

  func cameraCornerPoint(_ corner: CameraHandleCorner, in frame: CGRect) -> CGPoint {
    CGPoint(x: corner.isLeft ? frame.minX : frame.maxX, y: corner.isTop ? frame.maxY : frame.minY)
  }

  func cameraRadiusHandleCenter(in frame: CGRect) -> CGPoint {
    let radius = currentCameraAspect.cornerRadius(in: frame, percentage: currentCameraCornerRadius)
    let inset = min(max(radius, 16), min(frame.width, frame.height) / 2)
    return CGPoint(x: frame.minX + inset, y: frame.maxY - inset)
  }

  func cameraDragMode(at loc: CGPoint) -> CameraDragMode {
    guard canEditCameraFrame else { return .none }
    let frame = webcamWrapper.frame
    if canEditCameraRadius, hypot(loc.x - cameraRadiusHandleCenter(in: frame).x, loc.y - cameraRadiusHandleCenter(in: frame).y) <= 9 {
      return .radius
    }
    for corner in CameraHandleCorner.allCases {
      let p = cameraCornerPoint(corner, in: frame)
      if hypot(loc.x - p.x, loc.y - p.y) <= Self.cameraHandleHitDistance {
        return .resize(corner)
      }
    }
    return frame.contains(loc) ? .move : .none
  }

  func updateCameraCursor(at loc: CGPoint) {
    switch cameraDragMode(at: loc) {
    case .radius: NSCursor.pointingHand.set()
    case .resize(let corner): corner.cursor.set()
    case .move: NSCursor.openHand.set()
    case .none: NSCursor.arrow.set()
    }
  }

  private func setupCameraHandles() {
    cameraHandlesLayer.zPosition = 1000
    cameraHandlesLayer.isHidden = true
    let outline = CAShapeLayer()
    outline.fillColor = nil
    outline.strokeColor = NSColor.controlAccentColor.cgColor
    outline.lineWidth = 1.5
    cameraHandlesLayer.addSublayer(outline)
    for _ in CameraHandleCorner.allCases {
      let handle = CALayer()
      handle.backgroundColor = NSColor.white.cgColor
      handle.borderColor = NSColor.controlAccentColor.cgColor
      handle.borderWidth = 1.5
      handle.cornerRadius = 2
      cameraHandlesLayer.addSublayer(handle)
    }
    let dot = CALayer()
    dot.backgroundColor = NSColor.controlAccentColor.cgColor
    dot.borderColor = NSColor.white.cgColor
    dot.borderWidth = 1.5
    dot.cornerRadius = 5
    cameraHandlesLayer.addSublayer(dot)
    layer?.addSublayer(cameraHandlesLayer)
  }

  func layoutCameraHandles() {
    if cameraHandlesLayer.superlayer == nil { setupCameraHandles() }
    let show = canEditCameraFrame && (isHoveringCamera || activeCameraDrag != .none)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    cameraHandlesLayer.isHidden = !show
    if show, let layers = cameraHandlesLayer.sublayers, layers.count == 6 {
      let frame = webcamWrapper.frame
      cameraHandlesLayer.frame = bounds
      let radius = currentCameraAspect.cornerRadius(in: frame, percentage: currentCameraCornerRadius)
      (layers[0] as? CAShapeLayer)?.path = CGPath(
        roundedRect: frame,
        cornerWidth: min(radius, frame.width / 2),
        cornerHeight: min(radius, frame.height / 2),
        transform: nil
      )
      let size = Self.cameraHandleSize
      for (index, corner) in CameraHandleCorner.allCases.enumerated() {
        let p = cameraCornerPoint(corner, in: frame)
        layers[index + 1].frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
      }
      let center = cameraRadiusHandleCenter(in: frame)
      layers[5].isHidden = !canEditCameraRadius
      layers[5].frame = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
    }
    CATransaction.commit()
  }

  func dragCameraResize(_ corner: CameraHandleCorner, to loc: CGPoint) {
    guard let coord = coordinator, let webcamSize = currentWebcamSize else { return }
    let canvasRect = AVMakeRect(aspectRatio: currentCanvasSize, insideRect: bounds)
    guard canvasRect.width > 0 && canvasRect.height > 0 else { return }
    let start = coord.startLayout
    let heightFactor =
      currentCameraAspect.heightToWidthRatio(webcamSize: webcamSize)
      * (currentCanvasSize.width / max(currentCanvasSize.height, 1))
    let startHeight = start.relativeWidth * heightFactor
    let anchorX = corner.isLeft ? start.relativeX + start.relativeWidth : start.relativeX
    let anchorY = corner.isTop ? start.relativeY + startHeight : start.relativeY
    let pointerX = (loc.x - canvasRect.origin.x) / canvasRect.width
    let pointerY = (bounds.height - loc.y - canvasRect.origin.y) / canvasRect.height

    let roomX = corner.isLeft ? anchorX : 1 - anchorX
    let roomY = corner.isTop ? anchorY : 1 - anchorY
    let maxWidth = min(coord.maxCameraRelativeWidth, roomX, roomY / max(heightFactor, 0.001))
    let wanted = max(abs(pointerX - anchorX), abs(pointerY - anchorY) / max(heightFactor, 0.001))
    let width = min(max(wanted, min(0.1, maxWidth)), maxWidth)
    let height = width * heightFactor

    var layout = start
    layout.relativeWidth = width
    layout.relativeX = corner.isLeft ? anchorX - width : anchorX
    layout.relativeY = corner.isTop ? anchorY - height : anchorY
    coord.cameraLayout.wrappedValue = layout
    currentLayout = layout
    layoutAll()
    layoutCameraHandles()
  }

  func dragCameraRadius(to loc: CGPoint) {
    guard let binding = coordinator?.cameraCornerRadius else { return }
    let frame = webcamWrapper.frame
    let minDimension = min(frame.width, frame.height)
    guard minDimension > 0 else { return }
    let inset = ((loc.x - frame.minX) + (frame.maxY - loc.y)) / 2
    let percentage = (max(0, min(50, inset / minDimension * 100))).rounded()
    binding.wrappedValue = percentage
    currentCameraCornerRadius = percentage
    layoutAll()
    layoutCameraHandles()
  }
}
