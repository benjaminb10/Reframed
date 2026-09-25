import AppKit

final class WebcamPreviewInteractionView: NSView {
  var cornerRadius: CGFloat = 0 {
    didSet { layoutHandles() }
  }
  var allowsRadius = true {
    didSet { layoutHandles() }
  }
  var onBeginEdit: (() -> Void)?
  var onResize: ((CameraHandleCorner, NSPoint) -> Void)?
  var onRadius: ((CGFloat) -> Void)?
  var onEndEdit: (() -> Void)?

  private let handlesLayer = CALayer()
  private let outline = CAShapeLayer()
  private var cornerHandles: [CALayer] = []
  private let radiusDot = CALayer()
  private var trackingArea: NSTrackingArea?
  private var isHovering = false
  private var mode: CameraDragMode = .none
  private let handleSize: CGFloat = 12
  private let hitDistance: CGFloat = 14

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    handlesLayer.isHidden = true
    outline.fillColor = nil
    outline.strokeColor = NSColor.controlAccentColor.cgColor
    outline.lineWidth = 2
    handlesLayer.addSublayer(outline)
    for _ in CameraHandleCorner.allCases {
      let handle = CALayer()
      handle.backgroundColor = NSColor.white.cgColor
      handle.borderColor = NSColor.controlAccentColor.cgColor
      handle.borderWidth = 2
      handle.cornerRadius = 3
      handlesLayer.addSublayer(handle)
      cornerHandles.append(handle)
    }
    radiusDot.backgroundColor = NSColor.controlAccentColor.cgColor
    radiusDot.borderColor = NSColor.white.cgColor
    radiusDot.borderWidth = 2
    radiusDot.cornerRadius = 6
    handlesLayer.addSublayer(radiusDot)
    layer?.addSublayer(handlesLayer)
  }

  required init?(coder: NSCoder) { nil }

  override var mouseDownCanMoveWindow: Bool { false }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func layout() {
    super.layout()
    layoutHandles()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  private func cornerPoint(_ corner: CameraHandleCorner) -> CGPoint {
    let inset = handleSize / 2 + 1
    return CGPoint(
      x: corner.isLeft ? bounds.minX + inset : bounds.maxX - inset,
      y: corner.isTop ? bounds.maxY - inset : bounds.minY + inset
    )
  }

  private var radiusDotCenter: CGPoint {
    let inset = min(max(cornerRadius, 22), min(bounds.width, bounds.height) / 2)
    return CGPoint(x: bounds.minX + inset, y: bounds.maxY - inset)
  }

  private func dragMode(at loc: CGPoint) -> CameraDragMode {
    if allowsRadius, hypot(loc.x - radiusDotCenter.x, loc.y - radiusDotCenter.y) <= 10 {
      return .radius
    }
    for corner in CameraHandleCorner.allCases {
      let p = cornerPoint(corner)
      if hypot(loc.x - p.x, loc.y - p.y) <= hitDistance {
        return .resize(corner)
      }
    }
    return bounds.contains(loc) ? .move : .none
  }

  private func updateCursor(at loc: CGPoint) {
    switch dragMode(at: loc) {
    case .radius: NSCursor.pointingHand.set()
    case .resize(let corner): corner.cursor.set()
    case .move: NSCursor.openHand.set()
    case .none: NSCursor.arrow.set()
    }
  }

  func layoutHandles() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    handlesLayer.frame = bounds
    handlesLayer.isHidden = !(isHovering || mode != .none)
    let rect = bounds.insetBy(dx: 1, dy: 1)
    let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
    outline.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    for (index, corner) in CameraHandleCorner.allCases.enumerated() {
      let p = cornerPoint(corner)
      cornerHandles[index].frame = CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2, width: handleSize, height: handleSize)
    }
    radiusDot.isHidden = !allowsRadius
    let c = radiusDotCenter
    radiusDot.frame = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
    CATransaction.commit()
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
    layoutHandles()
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    layoutHandles()
    if mode == .none { NSCursor.arrow.set() }
  }

  override func mouseMoved(with event: NSEvent) {
    if !isHovering {
      isHovering = true
      layoutHandles()
    }
    updateCursor(at: convert(event.locationInWindow, from: nil))
  }

  override func mouseDown(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)
    let hit = dragMode(at: loc)
    switch hit {
    case .move:
      NSCursor.closedHand.set()
      window?.performDrag(with: event)
      updateCursor(at: convert(window?.mouseLocationOutsideOfEventStream ?? loc, from: nil))
    case .resize, .radius:
      mode = hit
      onBeginEdit?()
      layoutHandles()
    case .none:
      super.mouseDown(with: event)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    switch mode {
    case .resize(let corner):
      onResize?(corner, NSEvent.mouseLocation)
    case .radius:
      let loc = convert(event.locationInWindow, from: nil)
      let minDimension = min(bounds.width, bounds.height)
      guard minDimension > 0 else { return }
      let inset = ((loc.x - bounds.minX) + (bounds.maxY - loc.y)) / 2
      onRadius?((max(0, min(50, inset / minDimension * 100))).rounded())
    case .move, .none:
      break
    }
  }

  override func mouseUp(with event: NSEvent) {
    guard mode != .none else { return }
    mode = .none
    onEndEdit?()
    layoutHandles()
    updateCursor(at: convert(event.locationInWindow, from: nil))
  }
}
