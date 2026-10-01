import Foundation

/// Just enough ZIP support to pull a ROM out of an archive: reads the
/// central directory and inflates stored or deflated entries.
public enum ZipArchive {
    public struct Entry: Equatable {
        public let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let headerOffset: Int
    }

    public static func isZip(_ data: [UInt8]) -> Bool {
        data.count >= 4 && data[0] == 0x50 && data[1] == 0x4B && data[2] == 0x03 && data[3] == 0x04
    }

    public static func entries(_ data: [UInt8]) -> [Entry] {
        // End of central directory: signature 50 4B 05 06, within the last 64 KB.
        guard data.count >= 22 else { return [] }
        var eocd = -1
        var i = data.count - 22
        let stop = max(0, data.count - 22 - 0xFFFF)
        while i >= stop {
            if data[i] == 0x50 && data[i + 1] == 0x4B && data[i + 2] == 0x05 && data[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { return [] }
        let count = Int(u16(data, eocd + 10))
        var offset = Int(u32(data, eocd + 16))
        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= data.count, u32(data, offset) == 0x0201_4B50 else { break }
            let method = Int(u16(data, offset + 10))
            let compressed = Int(u32(data, offset + 20))
            let size = Int(u32(data, offset + 24))
            let nameLength = Int(u16(data, offset + 28))
            let extraLength = Int(u16(data, offset + 30))
            let commentLength = Int(u16(data, offset + 32))
            let header = Int(u32(data, offset + 42))
            guard offset + 46 + nameLength <= data.count else { break }
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            result.append(Entry(name: name, method: method, compressedSize: compressed, size: size, headerOffset: header))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    public static func extract(_ entry: Entry, from data: [UInt8]) -> [UInt8]? {
        let h = entry.headerOffset
        guard h + 30 <= data.count, u32(data, h) == 0x0403_4B50 else { return nil }
        let start = h + 30 + Int(u16(data, h + 26)) + Int(u16(data, h + 28))
        guard start + entry.compressedSize <= data.count else { return nil }
        let payload = Array(data[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return payload
        case 8:
            guard let out = Inflate.decompress(payload, expectedSize: entry.size) else { return nil }
            return out.count == entry.size ? out : nil
        default:
            return nil
        }
    }

    /// The first file inside the archive that looks like a ROM, by extension.
    public static func firstROM(in data: [UInt8]) -> (name: String, data: [UInt8])? {
        let candidates = entries(data).filter { entry in
            let ext = (entry.name as NSString).pathExtension.lowercased()
            return ConsoleSystem.allExtensions.contains(ext) && !entry.name.hasPrefix("__MACOSX")
        }
        for entry in candidates {
            if let bytes = extract(entry, from: data) {
                return ((entry.name as NSString).lastPathComponent, bytes)
            }
        }
        return nil
    }

    @inline(__always) static func u16(_ d: [UInt8], _ i: Int) -> UInt16 {
        UInt16(d[i]) | UInt16(d[i + 1]) << 8
    }

    @inline(__always) static func u32(_ d: [UInt8], _ i: Int) -> UInt32 {
        let low = UInt32(u16(d, i))
        let high = UInt32(u16(d, i + 2))
        return low | high << 16
    }
}

/// A compact RFC 1951 (DEFLATE) decoder.
enum Inflate {
    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for i in 1..<16 { offsets[i] = offsets[i - 1] + counts[i - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, l) in lengths.enumerated() where l != 0 {
                symbols[offsets[l]] = symbol
                offsets[l] += 1
            }
        }
    }

    private struct BitReader {
        let data: [UInt8]
        var position = 0
        var bitBuffer = 0
        var bitCount = 0
        var overrun = false

        mutating func bits(_ need: Int) -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard position < data.count else {
                    overrun = true
                    return 0
                }
                value |= Int(data[position]) << bitCount
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func alignToByte() {
            bitBuffer = 0
            bitCount = 0
        }

        mutating func decode(_ h: Huffman) -> Int {
            var code = 0, first = 0, index = 0
            for length in 1..<16 {
                code |= bits(1)
                if overrun { return -1 }
                let count = h.counts[length]
                if code - count < first {
                    return h.symbols[index + (code - first)]
                }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            return -1
        }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    static func decompress(_ input: [UInt8], expectedSize: Int = 0) -> [UInt8]? {
        var reader = BitReader(data: input)
        var out: [UInt8] = []
        out.reserveCapacity(expectedSize)
        var last = 0
        repeat {
            last = reader.bits(1)
            let type = reader.bits(2)
            if reader.overrun { return nil }
            switch type {
            case 0:
                reader.alignToByte()
                guard reader.position + 4 <= input.count else { return nil }
                let len = Int(input[reader.position]) | Int(input[reader.position + 1]) << 8
                reader.position += 4
                guard reader.position + len <= input.count else { return nil }
                out.append(contentsOf: input[reader.position..<(reader.position + len)])
                reader.position += len
            case 1:
                var lengths = [Int](repeating: 8, count: 288)
                for i in 144..<256 { lengths[i] = 9 }
                for i in 256..<280 { lengths[i] = 7 }
                let lit = Huffman(lengths: lengths)
                let dist = Huffman(lengths: [Int](repeating: 5, count: 30))
                guard codes(&reader, &out, lit, dist) else { return nil }
            case 2:
                let nlen = reader.bits(5) + 257
                let ndist = reader.bits(5) + 1
                let ncode = reader.bits(4) + 4
                guard nlen <= 286, ndist <= 30 else { return nil }
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var codeLengths = [Int](repeating: 0, count: 19)
                for i in 0..<ncode { codeLengths[order[i]] = reader.bits(3) }
                let lencode = Huffman(lengths: codeLengths)
                var lengths: [Int] = []
                while lengths.count < nlen + ndist {
                    let symbol = reader.decode(lencode)
                    if symbol < 0 { return nil }
                    if symbol < 16 {
                        lengths.append(symbol)
                    } else {
                        var repeatValue = 0
                        var count: Int
                        if symbol == 16 {
                            guard let previous = lengths.last else { return nil }
                            repeatValue = previous
                            count = 3 + reader.bits(2)
                        } else if symbol == 17 {
                            count = 3 + reader.bits(3)
                        } else {
                            count = 11 + reader.bits(7)
                        }
                        guard lengths.count + count <= nlen + ndist else { return nil }
                        lengths += [Int](repeating: repeatValue, count: count)
                    }
                }
                let lit = Huffman(lengths: Array(lengths[0..<nlen]))
                let dist = Huffman(lengths: Array(lengths[nlen...]))
                guard codes(&reader, &out, lit, dist) else { return nil }
            default:
                return nil
            }
        } while last == 0
        return out
    }

    private static func codes(_ reader: inout BitReader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman) -> Bool {
        while true {
            let symbol = reader.decode(lit)
            if symbol < 0 { return false }
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return true
            } else {
                let s = symbol - 257
                guard s < lengthBase.count else { return false }
                let length = lengthBase[s] + reader.bits(lengthExtra[s])
                let d = reader.decode(dist)
                guard d >= 0 && d < distBase.count else { return false }
                let distance = distBase[d] + reader.bits(distExtra[d])
                guard distance <= out.count, !reader.overrun else { return false }
                let start = out.count - distance
                for i in 0..<length { out.append(out[start + i]) }
            }
        }
    }
}
