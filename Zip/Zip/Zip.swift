//
//  Zip.swift
//  Zip
//
//  Created by Roy Marmelstein on 13/12/2015.
//  Copyright © 2015 Roy Marmelstein. All rights reserved.
//

import Foundation
private import Minizip

/// Zip class
public class Zip {
  
  /**
   Set of vaild file extensions
   */
  private static nonisolated(unsafe) var customFileExtensions: Set<String> = []
  private static let lock = NSLock()
  
  // MARK: Lifecycle
  
  /**
   Init
   
   - returns: Zip object
   */
  public init() {
  }
}

// MARK: - Unzip

extension Zip {
  /**
   Unzip file
   
   - parameter zipFilePath: Local file path of zipped file. NSURL.
   - parameter destination: Local file path to unzip to. NSURL.
   - parameter overwrite:   Overwrite bool.
   - parameter password:    Optional password if file is protected.
   - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0 and 1.
   
   - throws: Error if unzipping fails or if fail is not found. Can be printed with a description variable.
   
   - notes: Supports implicit progress composition
   */
  public class func unzipFile(
    _ zipFilePath: URL,
    destination: URL,
    overwrite: Bool,
    password: String?,
    progress: ((_ progress: Double) -> Void)? = nil,
    fileOutputHandler: ((_ unzippedFile: URL) -> Void)? = nil
  ) throws {
    
    // File manager
    let fileManager = FileManager.default
    
    // Check whether a zip file exists at path.
    let path = zipFilePath.path
    
    if fileManager.fileExists(atPath: path) == false
        || fileExtensionIsInvalid(zipFilePath.pathExtension)
    {
      throw ZipError.fileNotFound
    }
    
    // Unzip set up
    var ret: Int32 = 0
    var crc_ret: Int32 = 0
    let bufferSize: UInt32 = 4096
    var buffer = [CUnsignedChar](repeating: 0, count: Int(bufferSize))
    
    // Progress handler set up
    var totalSize: Double = 0.0
    var currentPosition: Double = 0.0
    let fileAttributes = try fileManager.attributesOfItem(atPath: path)
    if let attributeFileSize = fileAttributes[FileAttributeKey.size] as? Double {
      totalSize += attributeFileSize
    }
    
    let progressTracker = Progress(totalUnitCount: Int64(totalSize))
    progressTracker.isCancellable = false
    progressTracker.isPausable = false
    progressTracker.kind = ProgressKind.file
    
    // Begin unzipping
    let zip = unzOpen64(path)
    defer {
      unzClose(zip)
    }
    if unzGoToFirstFile(zip) != UNZ_OK {
      throw ZipError.unzipFail
    }
    repeat {
      if let cPassword = password?.cString(using: String.Encoding.ascii) {
        ret = unzOpenCurrentFilePassword(zip, cPassword)
        if ret == UNZ_BADPASSWORD {
          throw ZipError.incorrectPassword
        }
      } else {
        ret = unzOpenCurrentFile(zip)
        if ret == UNZ_PARAMERROR {
          throw ZipError.incorrectPassword
        }
      }
      if ret != UNZ_OK {
        throw ZipError.unzipFail
      }
      var fileInfo = unz_file_info64()
      memset(&fileInfo, 0, MemoryLayout<unz_file_info>.size)
      ret = unzGetCurrentFileInfo64(zip, &fileInfo, nil, 0, nil, 0, nil, 0)
      if ret != UNZ_OK {
        unzCloseCurrentFile(zip)
        throw ZipError.unzipFail
      }
      currentPosition += Double(fileInfo.compressed_size)
      let fileNameSize = Int(fileInfo.size_filename) + 1
      //let fileName = UnsafeMutablePointer<CChar>(allocatingCapacity: fileNameSize)
      let fileName = UnsafeMutablePointer<CChar>.allocate(capacity: fileNameSize)
      
      unzGetCurrentFileInfo64(zip, &fileInfo, fileName, UInt16(fileNameSize), nil, 0, nil, 0)
      fileName[Int(fileInfo.size_filename)] = 0
      
      var pathString = String(cString: fileName)
      
      guard pathString.count > 0 else {
        throw ZipError.unzipFail
      }
      
      var isDirectory = false
      let fileInfoSizeFileName = Int(fileInfo.size_filename - 1)
      if fileName[fileInfoSizeFileName] == "/".cString(using: String.Encoding.utf8)?.first
          || fileName[fileInfoSizeFileName] == "\\".cString(using: String.Encoding.utf8)?.first
      {
        isDirectory = true
      }
      free(fileName)
      if pathString.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\")) != nil {
        pathString = pathString.replacingOccurrences(of: "\\", with: "/")
      }
      
      let fullPath = destination.appendingPathComponent(pathString).standardized.path
      // .standardized removes any ".. to move a level up".
      // If we then check that the fullPath starts with the destination directory we know we are not extracting "outside" te destination.
      guard fullPath.starts(with: destination.standardized.path) else {
        throw ZipError.unzipFail
      }
      
      let creationDate = Date()
      
      let directoryAttributes: [FileAttributeKey: Any]?
#if os(Linux)
      // On Linux, setting attributes is not yet really implemented.
      // In Swift 4.2, the only settable attribute is `.posixPermissions`.
      // See https://github.com/apple/swift-corelibs-foundation/blob/swift-4.2-branch/Foundation/FileManager.swift#L182-L196
      directoryAttributes = nil
#else
      directoryAttributes = [
        .creationDate: creationDate,
        .modificationDate: creationDate
      ]
#endif
      
      do {
        if isDirectory {
          try fileManager.createDirectory(
            atPath: fullPath,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
          )
        } else {
          let parentDirectory = (fullPath as NSString).deletingLastPathComponent
          try fileManager.createDirectory(
            atPath: parentDirectory,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
          )
        }
      } catch {}
      if fileManager.fileExists(atPath: fullPath) && !isDirectory && !overwrite {
        unzCloseCurrentFile(zip)
        ret = unzGoToNextFile(zip)
      }
      
      var writeBytes: UInt64 = 0
      var filePointer: UnsafeMutablePointer<FILE>?
      filePointer = fopen(fullPath, "wb")
      while filePointer != nil {
        let readBytes = unzReadCurrentFile(zip, &buffer, bufferSize)
        if readBytes > 0 {
          guard fwrite(buffer, Int(readBytes), 1, filePointer) == 1 else {
            throw ZipError.unzipFail
          }
          writeBytes += UInt64(readBytes)
        } else {
          break
        }
      }
      
      if let fp = filePointer { fclose(fp) }
      
      crc_ret = unzCloseCurrentFile(zip)
      if crc_ret == UNZ_CRCERROR {
        throw ZipError.unzipFail
      }
      guard writeBytes == fileInfo.uncompressed_size else {
        throw ZipError.unzipFail
      }
      
      //Set file permissions from current fileInfo
      if fileInfo.external_fa != 0 {
        let permissions = (fileInfo.external_fa >> 16) & 0x1FF
        //We will devifne a valid permission range between Owner read only to full access
        if permissions >= 0o400 && permissions <= 0o777 {
          do {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: fullPath)
          } catch {
            print("Failed to set permissions to file \(fullPath), error: \(error)")
          }
        }
      }
      
      ret = unzGoToNextFile(zip)
      
      // Update progress handler
      if let progressHandler = progress {
        progressHandler((currentPosition / totalSize))
      }
      
      if let fileHandler = fileOutputHandler,
         let encodedString = fullPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
         let fileUrl = URL(string: encodedString)
      {
        fileHandler(fileUrl)
      }
      
      progressTracker.completedUnitCount = Int64(currentPosition)
      
    } while ret == UNZ_OK && ret != UNZ_END_OF_LIST_OF_FILE
    
    // Completed. Update progress handler.
    if let progressHandler = progress {
      progressHandler(1.0)
    }
    
    progressTracker.completedUnitCount = Int64(totalSize)
    
  }
  
  /// Returns the file info of a zip file.
  ///
  /// - Parameter zipFilePath: Local file path of zipped file.
  /// - Returns: An  ``UnzipFileInfo`` instance.
  public class func unzipFileInfo(_ zipFilePath: URL) throws -> UnzipFileInfo {
    guard
      !fileExtensionIsInvalid(zipFilePath.pathExtension),
      let file = unzOpen64(zipFilePath.path)
    else { throw ZipError.fileNotFound }
    defer { unzClose(file) }
    return try UnzipFileInfo(file: file)
  }
}

// MARK: - Zip Files

extension Zip {
  /**
   Zip files.
   
   - parameter paths:       Array of NSURL filepaths.
   - parameter zipFilePath: Destination NSURL, should lead to a .zip filepath.
   - parameter password:    Password string. Optional.
   - parameter compression: Compression strategy
   - parameter globalExtraFields: An array of ``ZipExtraField``s to use as extra data.
   - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0 and 1.
   
   - throws: Error if zipping fails.
   
   - notes: Supports implicit progress composition
   */
  public class func zipFiles(
    paths: [URL],
    zipFilePath: URL,
    password: String?,
    compression: ZipCompression = .DefaultCompression,
    globalExtraFields: [ZipExtraField] = [],
    progress: ((_ progress: Double) -> Void)?
  ) throws {
    var data = Data()
    for field in globalExtraFields {
      data.append(field.combinedData)
    }
    try zipFiles(
      paths: paths,
      zipFilePath: zipFilePath,
      password: password,
      compression: compression,
      globalExtraData: data,
      progress: progress
    )
  }
  
  /**
   Zip files.
   
   - parameter paths:       Array of NSURL filepaths.
   - parameter zipFilePath: Destination NSURL, should lead to a .zip filepath.
   - parameter password:    Password string. Optional.
   - parameter compression: Compression strategy
   - parameter globalExtraData: Data to attach to the "extra" field of the zip header.
   - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0 and 1.
   
   - throws: Error if zipping fails.
   
   - notes: Supports implicit progress composition
   */
  @_disfavoredOverload
  public class func zipFiles(
    paths: [URL],
    zipFilePath: URL,
    password: String?,
    compression: ZipCompression = .DefaultCompression,
    globalExtraData: Data? = nil,
    progress: ((_ progress: Double) -> Void)?
  ) throws {
    
    // File manager
    let fileManager = FileManager.default
    
    // Check whether a zip file exists at path.
    let destinationPath = zipFilePath.path
    
    // Process zip paths
    let processedPaths = ZipUtilities().processZipPaths(paths)
    
    // Zip set up
    let chunkSize: Int = 16384
    
    // Progress handler set up
    var currentPosition: Double = 0.0
    var totalSize: Double = 0.0
    // Get totalSize for progress handler
    for path in processedPaths {
      do {
        let filePath = path.filePath()
        let fileAttributes = try fileManager.attributesOfItem(atPath: filePath)
        let fileSize = fileAttributes[FileAttributeKey.size] as? Double
        if let fileSize = fileSize {
          totalSize += fileSize
        }
      } catch {}
    }
    
    let progressTracker = Progress(totalUnitCount: Int64(totalSize))
    progressTracker.isCancellable = false
    progressTracker.isPausable = false
    progressTracker.kind = ProgressKind.file
    
    // Begin Zipping
    let zip = zipOpen(destinationPath, APPEND_STATUS_CREATE)
    for path in processedPaths {
      let filePath = path.filePath()
      var isDirectory: ObjCBool = false
      _ = fileManager.fileExists(atPath: filePath, isDirectory: &isDirectory)
      if !isDirectory.boolValue {
        guard let input = fopen(filePath, "r") else {
          throw ZipError.zipFail
        }
        defer { fclose(input) }
        let fileName = path.fileName
        var zipInfo: zip_fileinfo = zip_fileinfo(
          dos_date: 0,
          internal_fa: 0,
          external_fa: 0
        )
        do {
          let fileAttributes = try fileManager.attributesOfItem(atPath: filePath)
          if let fileDate = fileAttributes[FileAttributeKey.modificationDate] as? Date {
            zipInfo.dos_date = fileDate.dosDate()
          }
          if let fileSize = fileAttributes[FileAttributeKey.size] as? Double {
            currentPosition += fileSize
          }
        } catch {}
        guard let buffer = malloc(chunkSize) else {
          throw ZipError.zipFail
        }
        try openNewFileInZip3(
          file: zip,
          filename: fileName,
          info: &zipInfo,
          password: password,
          globalExtraData: globalExtraData,
          compression: compression
        )
        var length: Int = 0
        while feof(input) == 0 {
          length = fread(buffer, 1, chunkSize, input)
          zipWriteInFileInZip(zip, buffer, UInt32(length))
        }
        
        // Update progress handler, only if progress is not 1, because
        // if we call it when progress == 1, the user will receive
        // a progress handler call with value 1.0 twice.
        if let progressHandler = progress, currentPosition / totalSize != 1 {
          progressHandler(currentPosition / totalSize)
        }
        
        progressTracker.completedUnitCount = Int64(currentPosition)
        
        zipCloseFileInZip(zip)
        free(buffer)
      }
    }
    zipClose(zip, nil)
    
    // Completed. Update progress handler.
    if let progressHandler = progress {
      progressHandler(1.0)
    }
    
    progressTracker.completedUnitCount = Int64(totalSize)
  }
  
  /**
   Zip data in memory.
   
   - parameter archiveFiles:Array of Archive Files.
   - parameter zipFilePath: Destination NSURL, should lead to a .zip filepath.
   - parameter password:    Password string. Optional.
   - parameter compression: Compression strategy
   - parameter globalExtraData: Data to attach to the "extra" field of the zip header.
   - parameter progress: A progress closure called after unzipping each file in the archive. Double value betweem 0 and 1.
   
   - throws: Error if zipping fails.
   
   - notes: Supports implicit progress composition
   */
  public class func zipData(
    archiveFiles: [ArchiveFile],
    zipFilePath: URL,
    password: String?,
    compression: ZipCompression = .DefaultCompression,
    globalExtraData: Data? = nil,
    progress: ((_ progress: Double) -> Void)?
  ) throws {
    
    let destinationPath = zipFilePath.path
    
    // Progress handler set up
    var currentPosition: Int = 0
    var totalSize: Int = 0
    
    for archiveFile in archiveFiles {
      totalSize += archiveFile.data.length
    }
    
    let progressTracker = Progress(totalUnitCount: Int64(totalSize))
    progressTracker.isCancellable = false
    progressTracker.isPausable = false
    progressTracker.kind = ProgressKind.file
    
    // Begin Zipping
    let zip = zipOpen(destinationPath, APPEND_STATUS_CREATE)
    
    for archiveFile in archiveFiles {
      
      // Skip empty data
      if archiveFile.data.length == 0 {
        continue
      }
      
      // Setup the zip file info
      var zipInfo = zip_fileinfo(
        dos_date: 0,
        internal_fa: 0,
        external_fa: 0
      )
      
      if let modifiedTime = archiveFile.modifiedTime {
        zipInfo.dos_date = modifiedTime.dosDate()
      }
      
      // Write the data as a file to zip
      try openNewFileInZip3(
        file: zip,
        filename: archiveFile.filename,
        info: &zipInfo,
        password: password,
        globalExtraData: globalExtraData,
        compression: compression
      )
      zipWriteInFileInZip(zip, archiveFile.data.bytes, UInt32(archiveFile.data.length))
      zipCloseFileInZip(zip)
      
      // Update progress handler
      currentPosition += archiveFile.data.length
      
      if let progressHandler = progress {
        progressHandler((Double(currentPosition / totalSize)))
      }
      
      progressTracker.completedUnitCount = Int64(currentPosition)
    }
    
    zipClose(zip, nil)
    
    // Completed. Update progress handler.
    if let progressHandler = progress {
      progressHandler(1.0)
    }
    
    progressTracker.completedUnitCount = Int64(totalSize)
  }
  
  @discardableResult
  private class func openNewFileInZip3(
    file: zipFile?,
    filename: String?,
    info: inout zip_fileinfo,
    password: String?,
    globalExtraData: Data?,
    compression: ZipCompression
  ) throws -> Int32 {
    var extraData = globalExtraData.flatMap { [UInt8]($0) } ?? []
    guard let filename else { throw ZipError.unzipFail }
    return zipOpenNewFileInZip3(
      file,
      filename,
      &info,
      nil,
      0,
      &extraData,
      UInt16(extraData.count),
      nil,
      UInt16(Z_DEFLATED),
      compression.minizipCompression,
      0,
      -MAX_WBITS,
      DEF_MEM_LEVEL,
      Z_DEFAULT_STRATEGY,
      password,
      0
    )
  }
}

// MARK: - File Extensions

extension Zip {
  
  /**
   Check if file extension is invalid.
   
   - parameter fileExtension: A file extension.
   
   - returns: false if the extension is a valid file extension, otherwise true.
   */
  internal class func fileExtensionIsInvalid(_ fileExtension: String?) -> Bool {
    
    guard let fileExtension = fileExtension else { return true }
    
    return !isValidFileExtension(fileExtension)
  }
  
  /**
   Add a file extension to the set of custom file extensions
   
   - parameter fileExtension: A file extension.
   */
  public class func addCustomFileExtension(_ fileExtension: String) {
    _ = lock.withLock {
      customFileExtensions.insert(fileExtension)
    }
  }
  
  /**
   Remove a file extension from the set of custom file extensions
   
   - parameter fileExtension: A file extension.
   */
  public class func removeCustomFileExtension(_ fileExtension: String) {
    _ = lock.withLock {
      customFileExtensions.remove(fileExtension)
    }
  }
  
  /**
   Check if a specific file extension is valid
   
   - parameter fileExtension: A file extension.
   
   - returns: true if the extension valid, otherwise false.
   */
  public class func isValidFileExtension(_ fileExtension: String) -> Bool {
    lock.withLock {
      let validFileExtensions: Set<String> = customFileExtensions.union(["zip", "cbz"])
      
      return validFileExtensions.contains(fileExtension)
    }
  }
  
}
