import Foundation

/// Data in memory that will be archived as a file.
public struct ArchiveFile {
  var filename: String
  var data: NSData
  var modifiedTime: Date?
  
  public init(filename: String, data: NSData, modifiedTime: Date?) {
    self.filename = filename
    self.data = data
    self.modifiedTime = modifiedTime
  }
}
