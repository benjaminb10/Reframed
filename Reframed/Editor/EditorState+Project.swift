import AppKit
import CoreMedia
import Foundation

extension EditorState {
  func deleteRecording() {
    pendingSaveTask?.cancel()
    pendingSaveTask = nil
    micProcessingTask?.cancel()
    micProcessingTask = nil
    transcriptionTask?.cancel()
    transcriptionTask = nil
    if let project {
      self.project = nil
      try? project.delete()
    } else {
      let fm = FileManager.default
      try? fm.removeItem(at: result.screenVideoURL)
      if let webcamURL = result.webcamVideoURL {
        try? fm.removeItem(at: webcamURL)
      }
      if let sysURL = result.systemAudioURL {
        try? fm.removeItem(at: sysURL)
      }
      if let micURL = result.microphoneAudioURL {
        try? fm.removeItem(at: micURL)
      }
    }
  }

  func openProjectFolder() {
    if let bundleURL = project?.bundleURL {
      NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    } else {
      let dir = FileManager.default.projectSaveDirectory()
      NSWorkspace.shared.open(dir)
    }
  }

  func openExportedFile() {
    if let lastExportedURL {
      NSWorkspace.shared.activateFileViewerSelecting([lastExportedURL])
    } else {
      let dir = FileManager.default.defaultSaveDirectory()
      NSWorkspace.shared.open(dir)
    }
  }

  func renameProject(_ newName: String) {
    guard var proj = project else { return }
    do {
      try proj.rename(to: newName)
    } catch {
      logger.error("Failed to rename project: \(error)")
      return
    }
    project = proj
    result = proj.recordingResult
    projectName = proj.name
  }

  func saveState() {
    guard let project else { return }
    do {
      try project.saveEditorState(createSnapshot())
    } catch {
      logger.error("Failed to save editor state: \(error)")
    }
  }

  func packageForPalmier(screenExport: URL) throws -> URL {
    let fm = FileManager.default
    let parent = screenExport.deletingLastPathComponent()
    var folder = parent.appendingPathComponent("\(projectName) - Palmier", isDirectory: true)
    var index = 2
    while fm.fileExists(atPath: folder.path) {
      folder = parent.appendingPathComponent("\(projectName) - Palmier \(index)", isDirectory: true)
      index += 1
    }
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)

    let screenName = "screen.\(screenExport.pathExtension)"
    try fm.moveItem(at: screenExport, to: folder.appendingPathComponent(screenName))

    var webcamName: String?
    if let webcam = result.webcamVideoURL, fm.fileExists(atPath: webcam.path) {
      let name = "webcam.\(webcam.pathExtension)"
      try fm.copyItem(at: webcam, to: folder.appendingPathComponent(name))
      webcamName = name
    }

    var micName: String?
    if let mic = result.microphoneAudioURL, fm.fileExists(atPath: mic.path) {
      let name = "mic.\(mic.pathExtension)"
      try fm.copyItem(at: mic, to: folder.appendingPathComponent(name))
      micName = name
    }

    let guide = palmierGuide(screenName: screenName, webcamName: webcamName, micName: micName)
    try guide.write(to: folder.appendingPathComponent("PALMIER.md"), atomically: true, encoding: .utf8)
    return folder
  }

  private func palmierGuide(screenName: String, webcamName: String?, micName: String?) -> String {
    var files = ["- `\(screenName)`: screen with cursor, zooms and background, mixed audio (\(formatDuration(duration)))"]
    if let webcamName {
      files.append(
        "- `\(webcamName)`: raw webcam, \(cameraMirrored ? "not mirrored yet, flip it horizontally" : "keep it unflipped")"
      )
    }
    if let micName {
      files.append("- `\(micName)`: clean microphone track, best source for transcription")
    }
    let layout =
      webcamName == nil
      ? "Screen only."
      : "Webcam fullscreen when I speak to camera (intro, outro), screen with the webcam as a square, rounded picture-in-picture in the bottom-right corner during demos."
    return """
      # \(projectName) for Palmier

      All files start at 0:00 and share the same timeline: place them all at 0 on the timeline, no sync needed.

      \(files.joined(separator: "\n"))

      ## Prompt for the Palmier agent

      Import every file in this folder at 0:00 on the timeline. Transcribe `\(micName ?? screenName)`. Remove silences and filler words. \(layout) Add captions. Export 1080p for YouTube.

      """
  }
}
