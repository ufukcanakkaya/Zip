import Foundation

// MARK: - ZipExtraField

/// A data type for an extra field in a zip archive.
public struct ZipExtraField: Hashable, Sendable, Identifiable, Codable {
  /// The ID of this extra field.
  ///
  /// Ids 0-31 are reserved for use by PKWARE. Additionally, some ids are reserved for special
  /// purposes like AES encryption. See https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
  /// for more information.
  public let id: ID
  
  /// The raw data of this extra field.
  public let data: Data
  
  /// The data size of this extra field.
  public var dataSize: UInt16 {
    UInt16(self.data.count)
  }
  
  public init(id: ID, data: Data) {
    self.id = id
    self.data = data
  }
}

// MARK: - ID

extension ZipExtraField {
  /// A data type for the id of a ``ZipExtraField``.
  ///
  /// Ids 0-31 are reserved for use by PKWARE. Additionally, some ids are reserved for special
  /// purposes like AES encryption. See https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
  /// for more information.
  public struct ID: Hashable, Sendable, RawRepresentable, Codable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
      self.rawValue = rawValue
    }
  }
}

extension ZipExtraField.ID: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: UInt16) {
    self.init(rawValue: value)
  }
}

// MARK: - Combined Data

extension ZipExtraField {
  /// An instance of `Data` that combines ``id``, ``data``, and ``dataSize`` in the extra data
  /// field format specified by the PKWARE Zip specification.
  public var combinedData: Data {
    var data = Data()
    data.append(
      withUnsafeBytes(
        of: ExtraFieldHeader(
          id: ID(rawValue: self.id.rawValue.littleEndian),
          dataSize: self.dataSize.littleEndian
        )
      ) { Data($0) }
    )
    data.append(self.data)
    return data
  }
}
