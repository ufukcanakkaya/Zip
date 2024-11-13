import Foundation
private import Minizip

// MARK: - ZipError

public enum ZipError: Error {
  case fileNotFound
  case unzipFail
  case zipFail
  case incorrectPassword
}

// MARK: - Description

extension ZipError {
  /// User readable description
  public var description: String {
    switch self {
    case .fileNotFound: return NSLocalizedString("File not found.", comment: "")
    case .unzipFail: return NSLocalizedString("Failed to unzip file.", comment: "")
    case .zipFail: return NSLocalizedString("Failed to zip file.", comment: "")
    case .incorrectPassword: return NSLocalizedString("Incorrect password.", comment: "")
    }
  }
}
