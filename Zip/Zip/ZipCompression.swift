import zlib

// MARK: - ZipCompression

public enum ZipCompression: Int {
  case NoCompression
  case BestSpeed
  case DefaultCompression
  case BestCompression
}

// MARK: - Minizip Compression

extension ZipCompression {
  var minizipCompression: Int32 {
    switch self {
    case .NoCompression:
      return Z_NO_COMPRESSION
    case .BestSpeed:
      return Z_BEST_SPEED
    case .DefaultCompression:
      return Z_DEFAULT_COMPRESSION
    case .BestCompression:
      return Z_BEST_COMPRESSION
    }
  }
}
