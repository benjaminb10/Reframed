import AVFoundation
import AppKit

@MainActor
final class WebcamPreviewWindow {
  private var panel: NSPanel?
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var isMirrored = ConfigService.shared.mirrorCamera
  private var loadingView: NSView?
  nonisolated(unsafe) private var moveObserver: NSObjectProtocol?
  private var appearanceObserver: NSKeyValueObservation?

  private var cornerRadiusPercent: CGFloat = ConfigService.shared.liveCameraCornerRadius
  private let interactionView = WebcamPreviewInteractionView()
  private var editStartFrame: NSRect = .zero
  private var videoWidth: CGFloat = 270
  private var videoHeight: CGFloat = 202
  private var cameraAspect: CameraAspect = .original
  private var webcamSize: CGSize?

  private var cornerRadius: CGFloat {
    let rect = CGRect(origin: .zero, size: CGSize(width: videoWidth, height: videoHeight))
    if cameraAspect.isCircle {
      return cameraAspect.cornerRadius(in: rect, percentage: 50)
    }
    return min(videoWidth, videoHeight) * cornerRadiusPercent / 100
  }

  private func installInteractionView() {
    guard let contentView = panel?.contentView else { return }
    interactionView.frame = contentView.bounds
    interactionView.autoresizingMask = [.width, .height]
    interactionView.cornerRadius = cornerRadius
    interactionView.allowsRadius = !cameraAspect.isCircle
    interactionView.onBeginEdit = { [weak self] in
      self?.editStartFrame = self?.panel?.frame ?? .zero
    }
    interactionView.onResize = { [weak self] corner, mouse in
      self?.resize(from: corner, to: mouse)
    }
    interactionView.onRadius = { [weak self] percentage in
      self?.cornerRadiusPercent = percentage
      self?.relayoutContent()
    }
    interactionView.onEndEdit = { [weak self] in
      self?.persistLiveLayout()
    }
    interactionView.removeFromSuperview()
    contentView.addSubview(interactionView)
  }

  private func resize(from corner: CameraHandleCorner, to mouse: NSPoint) {
    guard let panel else { return }
    let start = editStartFrame
    let anchorX = corner.isLeft ? start.maxX : start.minX
    let anchorY = corner.isTop ? start.minY : start.maxY
    let ratio = videoHeight / max(videoWidth, 1)
    let screenWidth = (panel.screen ?? NSScreen.main)?.visibleFrame.width ?? 1440
    let wanted = max(abs(mouse.x - anchorX), abs(mouse.y - anchorY) / max(ratio, 0.01))
    let width = round(min(max(wanted, 120), screenWidth * 0.6))
    let height = round(width * ratio)
    videoWidth = width
    videoHeight = height
    let origin = NSPoint(x: corner.isLeft ? anchorX - width : anchorX, y: corner.isTop ? anchorY : anchorY - height)
    panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    relayoutContent()
  }

  private func relayoutContent() {
    guard let panel, let contentView = panel.contentView else { return }
    contentView.frame = NSRect(origin: .zero, size: panel.frame.size)
    for subview in contentView.subviews where subview !== interactionView {
      subview.frame = contentView.bounds
      subview.layer?.cornerRadius = cornerRadius
    }
    previewLayer?.frame = contentView.bounds
    interactionView.frame = contentView.bounds
    interactionView.cornerRadius = cornerRadius
    interactionView.allowsRadius = !cameraAspect.isCircle
    panel.invalidateShadow()
  }

  private func persistLiveLayout() {
    ConfigService.shared.liveCameraWidth = videoWidth
    ConfigService.shared.liveCameraCornerRadius = cornerRadiusPercent
    savePosition()
  }

  private var totalWidth: CGFloat { videoWidth }
  private var totalHeight: CGFloat { videoHeight }

  func showLoading(cameraAspect: CameraAspect = ConfigService.shared.cameraAspect, webcamSize: CGSize? = nil) {
    configureStyle(cameraAspect: cameraAspect, webcamSize: webcamSize)

    if panel == nil {
      createPanel()
    } else {
      resizePanelForCurrentStyle()
    }

    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    loadingView?.removeFromSuperview()

    guard let contentView = panel?.contentView else { return }
    contentView.subviews.forEach { $0.removeFromSuperview() }

    let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: videoWidth, height: videoHeight)))
    container.wantsLayer = true
    container.layer?.cornerRadius = cornerRadius
    container.layer?.masksToBounds = true
    container.layer?.backgroundColor = ReframedColors.backgroundNS.cgColor

    let spinner = NSProgressIndicator(frame: NSRect(x: (videoWidth - 24) / 2, y: (videoHeight - 24) / 2 + 10, width: 24, height: 24))
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.appearance = NSAppearance(named: ReframedColors.isDark ? .darkAqua : .aqua)
    spinner.startAnimation(nil)
    container.addSubview(spinner)

    let label = NSTextField(labelWithString: "Camera is starting...")
    label.font = NSFont.systemFont(ofSize: FontSize.xs, weight: .medium)
    label.textColor = ReframedColors.secondaryTextNS
    label.alignment = .center
    label.frame = NSRect(x: 0, y: (videoHeight - 24) / 2 - 18, width: videoWidth, height: 16)
    container.addSubview(label)

    contentView.addSubview(container)
    loadingView = container
    installInteractionView()

    panel?.orderFrontRegardless()
  }

  func show(
    captureSession: AVCaptureSession,
    cameraAspect: CameraAspect = ConfigService.shared.cameraAspect,
    webcamSize: CGSize? = nil
  ) {
    configureStyle(cameraAspect: cameraAspect, webcamSize: webcamSize)

    if panel == nil {
      createPanel()
    } else {
      resizePanelForCurrentStyle()
    }

    previewLayer?.removeFromSuperlayer()
    previewLayer = nil

    guard let contentView = panel?.contentView else { return }
    contentView.subviews
      .filter { $0 !== loadingView }
      .forEach { $0.removeFromSuperview() }

    let videoView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: videoWidth, height: videoHeight)))
    videoView.wantsLayer = true
    videoView.layer?.cornerRadius = cornerRadius
    videoView.layer?.masksToBounds = true

    let layer = AVCaptureVideoPreviewLayer(session: captureSession)
    layer.videoGravity = .resizeAspectFill
    layer.frame = videoView.bounds
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    videoView.layer?.addSublayer(layer)
    self.previewLayer = layer
    isMirrored = ConfigService.shared.mirrorCamera
    applyMirror(to: layer)

    contentView.addSubview(videoView, positioned: .below, relativeTo: loadingView)
    installInteractionView()
    panel?.orderFrontRegardless()

    let pendingLoadingView = loadingView
    loadingView = nil
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      pendingLoadingView?.removeFromSuperview()
    }
  }

  func showError(_ message: String, cameraAspect: CameraAspect = ConfigService.shared.cameraAspect, webcamSize: CGSize? = nil) {
    configureStyle(cameraAspect: cameraAspect, webcamSize: webcamSize)

    if panel == nil {
      createPanel()
    } else {
      resizePanelForCurrentStyle()
    }

    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    loadingView?.removeFromSuperview()
    loadingView = nil

    guard let contentView = panel?.contentView else { return }
    contentView.subviews.forEach { $0.removeFromSuperview() }

    let container = NSView(frame: NSRect(origin: .zero, size: NSSize(width: videoWidth, height: videoHeight)))
    container.wantsLayer = true
    container.layer?.cornerRadius = cornerRadius
    container.layer?.masksToBounds = true
    container.layer?.backgroundColor = ReframedColors.backgroundNS.cgColor

    let icon = NSImageView(frame: NSRect(x: (videoWidth - 24) / 2, y: (videoHeight - 24) / 2 + 10, width: 24, height: 24))
    icon.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
    icon.contentTintColor = .systemOrange
    container.addSubview(icon)

    let label = NSTextField(labelWithString: message)
    label.font = NSFont.systemFont(ofSize: FontSize.xs, weight: .medium)
    label.textColor = ReframedColors.secondaryTextNS
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.frame = NSRect(x: 4, y: (videoHeight - 24) / 2 - 18, width: videoWidth - 8, height: 16)
    container.addSubview(label)

    contentView.addSubview(container)
    loadingView = container
    installInteractionView()

    panel?.orderFrontRegardless()
  }

  func setMirrored(_ mirrored: Bool) {
    isMirrored = mirrored
    if let previewLayer { applyMirror(to: previewLayer) }
  }

  private func applyMirror(to layer: AVCaptureVideoPreviewLayer) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.setAffineTransform(isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
    CATransaction.commit()
  }

  func updateStyle(cameraAspect: CameraAspect, webcamSize: CGSize? = nil) {
    configureStyle(cameraAspect: cameraAspect, webcamSize: webcamSize)
    resizePanelForCurrentStyle()
  }

  func hide() {
    panel?.orderOut(nil)
  }

  func unhide() {
    panel?.orderFrontRegardless()
  }

  func close() {
    savePosition()
    if let observer = moveObserver {
      NotificationCenter.default.removeObserver(observer)
      moveObserver = nil
    }
    appearanceObserver?.invalidate()
    appearanceObserver = nil
    previewLayer?.removeFromSuperlayer()
    previewLayer = nil
    loadingView?.removeFromSuperview()
    loadingView = nil
    panel?.orderOut(nil)
    panel?.contentView = nil
    panel = nil
  }

  private func createPanel() {
    let origin = resolvedOrigin()

    let panel = NSPanel(
      contentRect: NSRect(origin: origin, size: NSSize(width: totalWidth, height: totalHeight)),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    panel.isFloatingPanel = true
    panel.isMovableByWindowBackground = true
    panel.hasShadow = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.sharingType = Window.sharingType

    let contentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: totalWidth, height: totalHeight)))
    contentView.wantsLayer = true
    contentView.layer?.masksToBounds = false
    contentView.layer?.backgroundColor = NSColor.clear.cgColor

    panel.contentView = contentView
    self.panel = panel

    moveObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification,
      object: panel,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.savePosition()
      }
    }

    appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
      MainActor.assumeIsolated {
        self?.updateColors()
      }
    }
  }

  private func configureStyle(cameraAspect: CameraAspect, webcamSize: CGSize?) {
    self.cameraAspect = cameraAspect
    if let webcamSize {
      self.webcamSize = webcamSize
    }

    let sourceSize = self.webcamSize ?? CGSize(width: 4, height: 3)
    let ratio = cameraAspect.heightToWidthRatio(webcamSize: sourceSize)
    videoWidth = ConfigService.shared.liveCameraWidth
    videoHeight = round(videoWidth * ratio)
  }

  private func resizePanelForCurrentStyle() {
    guard let panel else { return }
    let newSize = NSSize(width: totalWidth, height: totalHeight)
    let oldFrame = panel.frame
    let origin = CGPoint(x: oldFrame.maxX - newSize.width, y: oldFrame.origin.y)
    panel.setFrame(NSRect(origin: origin, size: newSize), display: true)

    relayoutContent()
  }

  private func updateColors() {
    if let container = loadingView {
      container.layer?.backgroundColor = ReframedColors.backgroundNS.cgColor
      for subview in container.subviews {
        if let label = subview as? NSTextField {
          label.textColor = ReframedColors.secondaryTextNS
        }
        if let spinner = subview as? NSProgressIndicator {
          spinner.appearance = NSAppearance(named: ReframedColors.isDark ? .darkAqua : .aqua)
        }
      }
    }
  }

  private func resolvedOrigin() -> CGPoint {
    if let saved = StateService.shared.webcamPreviewPosition {
      let panelRect = NSRect(origin: saved, size: NSSize(width: totalWidth, height: totalHeight))
      for screen in NSScreen.screens {
        if screen.visibleFrame.intersects(panelRect) {
          return saved
        }
      }
    }

    return defaultOrigin()
  }

  private func defaultOrigin() -> CGPoint {
    guard let screen = NSScreen.main else { return .zero }
    let screenFrame = screen.visibleFrame
    return CGPoint(
      x: screenFrame.maxX - totalWidth - 20,
      y: screenFrame.minY + 20
    )
  }

  private func savePosition() {
    guard let panel else { return }
    let frame = panel.frame
    StateService.shared.webcamPreviewPosition = frame.origin
    if let screen = panel.screen ?? NSScreen.main {
      let screenFrame = screen.frame
      ConfigService.shared.liveCameraRelativeWidth = frame.width / max(screenFrame.width, 1)
      let isRight = frame.midX > screenFrame.midX
      let isTop = frame.midY > screenFrame.midY
      ConfigService.shared.liveCameraCorner =
        isTop ? (isRight ? .topRight : .topLeft) : (isRight ? .bottomRight : .bottomLeft)
    }
  }
}
