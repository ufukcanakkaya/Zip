import Foundation
internal import Minizip

// MARK: - UnzipFileInfo

/// A data type for the info of a zip file.
public struct UnzipFileInfo {
  /// The raw data that comprises of the extra data of this file info.
  public let extraData: Data?
  
  /// The ``ZipCompressionMethod`` used to zip this file.
  public let compressionMethod: ZipCompressionMethod
  
  init(file: unzFile) throws {
    var info = unz_file_info()
    var result = unzGetCurrentFileInfo(file, &info, nil, 0, nil, 0, nil, 0)
    guard result == UNZ_OK else { throw ZipError.unzipFail }
    var extraData = Data(count: Int(info.size_file_extra))
    result = extraData.withUnsafeMutableBytes {
      unzGetCurrentFileInfo(file, nil, nil, 0, $0.baseAddress, info.size_file_extra, nil, 0)
    }
    guard result == UNZ_OK else { throw ZipError.unzipFail }
    self.extraData = info.size_file_extra > 0 ? extraData : nil
    self.compressionMethod = ZipCompressionMethod(rawValue: info.compression_method)
  }
}

// MARK: - Extra Fields

extension UnzipFileInfo {
  /// The ``ZipExtraField``s from the ``extraData`` of this file info.
  ///
  /// Minizip will hide the extra field for AES Encryption. To check if the file was encrypted with
  /// AES, you can check if ``compressionMethod`` is ``ZipCompressionMethod/aesEncryption``.
  public var extraFields: [ZipExtraField]? {
    self.extraData.flatMap { data in
      var byteIndex = 0
      var fields = [ZipExtraField]()
      while byteIndex < data.count {
        let header = data[byteIndex..<(byteIndex + 4)].withUnsafeBytes {
          $0.assumingMemoryBound(to: ExtraFieldHeader.self).baseAddress?.pointee
        }
        guard let header else { return fields }
        byteIndex += 4
        let byteIndexEnd = byteIndex + Int(header.dataSize)
        guard byteIndexEnd <= data.count else { return fields }
        fields.append(ZipExtraField(id: header.id, data: data[byteIndex..<byteIndexEnd]))
        byteIndex = byteIndexEnd
      }
      return fields
    }
  }
}
