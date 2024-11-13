// MARK: - ZipCompressionMethod

public struct ZipCompressionMethod: RawRepresentable, Hashable, Sendable {
  public let rawValue: UInt16
  
  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }
}

// MARK: - Known Methods

extension ZipCompressionMethod {
  public static let aesEncryption = Self(rawValue: 99)
  public static let deflated = Self(rawValue: 8)
}
