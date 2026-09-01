import Foundation
import zlib

// MARK: - 模型

public struct EPUBMetadata: Equatable, Sendable {
    public let title: String
    public let creator: String?
    public let language: String?
}

public struct EPUBChapter: Equatable, Sendable {
    public let id: String
    public let title: String
    /// 段落级纯文本（重排阅读模式使用）
    public let textBlocks: [String]
    /// 原始 XHTML（WebKit 渲染模式使用）
    public let rawXHTML: String
}

public struct EPUBDocument: Equatable, Sendable {
    public let metadata: EPUBMetadata
    public let chapters: [EPUBChapter]

    public var displayName: String {
        metadata.title.isEmpty ? "未命名 EPUB" : metadata.title
    }
}

public enum EPUBError: Error, Equatable, Sendable {
    case notAnEPUB(String)
    case invalidContainer
    case missingOPF(String)
    case missingSpineItem(String)
    case unsupportedCompression(String)
    case corruptArchive(String)
}

// MARK: - 解析入口

public enum EPUBCore {
    /// 从磁盘 URL 解析 EPUB。
    public static func parse(url: URL) throws -> EPUBDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EPUBError.notAnEPUB("cannot read file: \(error.localizedDescription)")
        }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> EPUBDocument {
        let archive = try ZIPArchive(data: data)

        guard let containerData = try archive.read(named: "META-INF/container.xml") else {
            throw EPUBError.invalidContainer
        }
        let container = try XMLReader.parse(data: containerData)
        guard let rootfile = container.firstAttribute(
            path: ["rootfiles", "rootfile"],
            attribute: "full-path"
        ) else {
            throw EPUBError.invalidContainer
        }

        guard let opfData = try archive.read(named: rootfile) else {
            throw EPUBError.missingOPF(rootfile)
        }
        let opf = try XMLReader.parse(data: opfData)

        let title = opf.firstText(path: ["metadata", "title"]) ?? "未命名"
        let creator = opf.firstText(path: ["metadata", "creator"])
        let language = opf.firstText(path: ["metadata", "language"])

        var manifest: [String: (href: String, properties: String)] = [:]
        for node in opf.children(named: "manifest").first?.children(named: "item") ?? [] {
            guard let id = node.attribute("id"), let href = node.attribute("href") else { continue }
            manifest[id] = (href, node.attribute("properties") ?? "")
        }

        let spineRefs = (opf.children(named: "spine").first?.children(named: "itemref") ?? []).compactMap {
            $0.attribute("idref")
        }
        guard !spineRefs.isEmpty else { throw EPUBError.missingOPF("spine is empty") }

        let basePath = (rootfile as NSString).deletingLastPathComponent
        var chapters: [EPUBChapter] = []
        for (index, idref) in spineRefs.enumerated() {
            guard let item = manifest[idref] else {
                throw EPUBError.missingSpineItem(idref)
            }
            // EPUB 3 导航文档与封面不进正文
            if item.properties.contains("nav") || item.properties.contains("cover-image") { continue }
            let resolved = resolve(href: item.href, basePath: basePath)
            guard let rawData = try archive.read(named: resolved) else { continue }
            guard let raw = String(data: rawData, encoding: .utf8) else { continue }
            let blocks = XHTMLExtractor.blocks(from: raw)
            chapters.append(
                EPUBChapter(
                    id: idref,
                    title: blocks.first ?? "第 \(index + 1) 节",
                    textBlocks: blocks,
                    rawXHTML: raw
                )
            )
        }
        guard !chapters.isEmpty else { throw EPUBError.missingOPF("no readable chapters") }

        // 用第一章标题美化显示名
        let finalTitle = title == "未命名" ? chapters.first?.title ?? title : title
        return EPUBDocument(
            metadata: EPUBMetadata(title: finalTitle, creator: creator, language: language),
            chapters: chapters
        )
    }

    private static func resolve(href: String, basePath: String) -> String {
        let components = href.split(separator: "/").map(String.init)
        guard let first = components.first else { return basePath.isEmpty ? href : "\(basePath)/\(href)" }
        if first.contains(":") || href.hasPrefix("/") { return href }
        let baseParts = basePath.isEmpty ? [] : basePath.split(separator: "/").map(String.init)
        var parts = baseParts
        for component in components {
            if component == "." { continue }
            if component == ".." { _ = parts.popLast(); continue }
            parts.append(component)
        }
        return parts.joined(separator: "/")
    }
}

// MARK: - ZIP 读取（仅需解包，不依赖第三方）

private struct ZIPEntry {
    let name: String
    let method: UInt16
    let compressedSize: UInt64
    let localHeaderOffset: UInt32
}

private final class ZIPArchive {
    private let data: Data
    private let entries: [ZIPEntry]

    init(data: Data) throws {
        self.data = data
        self.entries = try ZIPArchive.readCentralDirectory(data: data)
        guard !entries.isEmpty else { throw EPUBError.corruptArchive("empty central directory") }
    }

    func read(named name: String) throws -> Data? {
        let normalized = name.hasPrefix("/") ? String(name.dropFirst()) : name
        guard let entry = entries.first(where: { $0.name == normalized }) else { return nil }
        return try readEntry(entry)
    }

    private func readEntry(_ entry: ZIPEntry) throws -> Data {
        let offset = Int(entry.localHeaderOffset)
        guard offset + 30 <= data.count else { throw EPUBError.corruptArchive("bad local header offset") }
        let nameLength = Int(Self.readUInt16(data, at: offset + 26))
        let extraLength = Int(Self.readUInt16(data, at: offset + 28))
        let payloadStart = offset + 30 + nameLength + extraLength
        guard payloadStart + Int(entry.compressedSize) <= data.count else {
            throw EPUBError.corruptArchive("payload out of bounds")
        }
        let payload = data.subdata(in: payloadStart..<payloadStart + Int(entry.compressedSize))
        switch entry.method {
        case 0:
            return payload
        case 8:
            guard let inflated = inflateRaw(payload) else {
                throw EPUBError.corruptArchive("deflate failed for \(entry.name)")
            }
            return inflated
        default:
            throw EPUBError.unsupportedCompression("method \(entry.method) for \(entry.name)")
        }
    }

    private static func readCentralDirectory(data: Data) throws -> [ZIPEntry] {
        // 从尾部 64KB 内找 EOCD 签名 0x06054b50
        let searchStart = max(0, data.count - 65_536)
        let tail = data.subdata(in: searchStart..<data.count)
        guard let eocdOffset = findSignature(tail, signature: 0x06054b50) else {
            throw EPUBError.notAnEPUB("no end-of-central-directory")
        }
        let eocd = searchStart + eocdOffset
        guard eocd + 22 <= data.count else { throw EPUBError.corruptArchive("truncated EOCD") }
        let count = Int(readUInt16(data, at: eocd + 10))
        let directoryOffset = Int(readUInt32(data, at: eocd + 16))

        var entries: [ZIPEntry] = []
        var cursor = directoryOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, readUInt32(data, at: cursor) == 0x02014b50 else {
                throw EPUBError.corruptArchive("bad central directory entry")
            }
            let method = readUInt16(data, at: cursor + 10)
            let compressedSize = UInt64(readUInt32(data, at: cursor + 20))
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let localOffset = readUInt32(data, at: cursor + 42)
            guard cursor + 46 + nameLength <= data.count else { throw EPUBError.corruptArchive("truncated entry name") }
            let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8) ?? ""
            entries.append(ZIPEntry(name: name, method: method, compressedSize: compressedSize, localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func findSignature(_ data: Data, signature: UInt32) -> Int? {
        let bytes = [UInt8(signature & 0xFF), UInt8((signature >> 8) & 0xFF), UInt8((signature >> 16) & 0xFF), UInt8((signature >> 24) & 0xFF)]
        var index = data.count - 4
        while index >= 0 {
            if data[index] == bytes[0],
               data[index + 1] == bytes[1],
               data[index + 2] == bytes[2],
               data[index + 3] == bytes[3] {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}

private func inflateRaw(_ data: Data) -> Data? {
    var stream = z_stream()
    let bufferSize = 65_536
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    let initStatus = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
        guard let base = raw.baseAddress else { return Z_ERRNO }
        stream.next_in = UnsafeMutablePointer<UInt8>(mutating: base.assumingMemoryBound(to: UInt8.self))
        stream.avail_in = uInt(raw.count)
        return inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    }
    guard initStatus == Z_OK else { return nil }
    defer { inflateEnd(&stream) }

    var output = Data()
    var status: Int32 = Z_OK
    repeat {
        stream.next_out = buffer
        stream.avail_out = uInt(bufferSize)
        status = inflate(&stream, Z_NO_FLUSH)
        guard status == Z_OK || status == Z_STREAM_END else { return nil }
        let produced = bufferSize - Int(stream.avail_out)
        output.append(buffer, count: produced)
    } while status != Z_STREAM_END
    return output
}

// MARK: - XML 轻量读取

private final class XMLNode {
    var name: String
    var attributes: [String: String] = [:]
    var children: [XMLNode] = []
    var text: String = ""
    init(name: String) { self.name = name }
    func attribute(_ key: String) -> String? { attributes[key] }
    func children(named name: String) -> [XMLNode] { children.filter { $0.name == name } }
}

private final class XMLReader: NSObject, XMLParserDelegate {
    private var root: XMLNode?
    private var stack: [XMLNode] = []
    private var currentText = ""

    static func parse(data: Data) throws -> XMLNode {
        let reader = XMLReader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        guard parser.parse() else {
            throw EPUBError.notAnEPUB("invalid XML: \(parser.parserError?.localizedDescription ?? "unknown")")
        }
        guard let root = reader.root else { throw EPUBError.notAnEPUB("empty XML") }
        return root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if let parent = stack.last { parent.text += currentText }
        currentText = ""
        let node = XMLNode(name: elementName)
        node.attributes = attributeDict
        stack.last?.children.append(node)
        stack.append(node)
        if root == nil { root = node }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let node = stack.last {
            node.text = (node.text + currentText).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        currentText = ""
        _ = stack.popLast()
    }
}

private extension XMLNode {
    func firstText(path: [String]) -> String? {
        var nodes: [XMLNode] = [self]
        for name in path {
            nodes = nodes.flatMap { $0.children(named: name) }
        }
        return nodes.first?.text.isEmpty == false ? nodes.first?.text : nil
    }

    func firstAttribute(path: [String], attribute: String) -> String? {
        var nodes: [XMLNode] = [self]
        for name in path {
            nodes = nodes.flatMap { $0.children(named: name) }
        }
        return nodes.first?.attributes[attribute]
    }
}

// MARK: - XHTML → 段落文本

private enum XHTMLExtractor {
    static let blockTags: Set<String> = ["p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "tr", "td", "th", "dt", "dd", "figcaption"]
    static let skipTags: Set<String> = ["script", "style", "head", "title", "nav", "svg", "math"]

    /// 优先用 XML 解析（规范 EPUB 的 XHTML 是 well-formed）；失败则回退到正则剥标签。
    static func blocks(from xhtml: String) -> [String] {
        let decoded = XHTMLEntities.decode(xhtml)
        if let xmlBlocks = xmlBlocks(from: decoded), !xmlBlocks.isEmpty {
            return xmlBlocks
        }
        return regexBlocks(from: decoded)
    }

    private static func xmlBlocks(from decoded: String) -> [String]? {
        guard let data = decoded.data(using: .utf8) else { return nil }
        let reader = HTMLBlockReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), !reader.blocks.isEmpty else { return nil }
        return reader.blocks
    }

    private static func regexBlocks(from decoded: String) -> [String] {
        var text = decoded
        for tag in skipTags {
            text = text.replacingOccurrences(
                of: "<\(tag)[\\s\\S]*?</\(tag)>",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        var blocks: [String] = []
        var current = ""
        let pattern = "<(p|div|li|h[1-6]|blockquote|tr|td|th|br)([^>]*)>(.*?)(</\\1>|$)"
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: pattern, options: .regularExpression, range: searchRange) {
            let tag = String(text[match.lowerBound..<match.upperBound])
            let inner = tag.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            let cleaned = XHTMLEntities.decode(inner)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                if !current.isEmpty { blocks.append(current) }
                current = cleaned
            } else if tag.hasPrefix("<br") && !current.isEmpty {
                blocks.append(current)
                current = ""
            }
            searchRange = match.upperBound..<text.endIndex
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }
}

/// XML 模式下的块收集
private final class HTMLBlockReader: NSObject, XMLParserDelegate {
    private(set) var blocks: [String] = []
    private var inBlock = false
    private var current = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if XHTMLExtractor.blockTags.contains(elementName) {
            if inBlock { blocks.append(current) }
            current = ""
            inBlock = true
        } else if elementName == "br" {
            if !current.isEmpty { blocks.append(current); current = "" }
        } else if XHTMLExtractor.skipTags.contains(elementName) {
            // 跳过整棵子树：由 didEnd 恢复
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inBlock { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if XHTMLExtractor.blockTags.contains(elementName), inBlock {
            let cleaned = XHTMLEntities.decode(current).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { blocks.append(cleaned) }
            current = ""
            inBlock = false
        }
    }
}

private enum XHTMLEntities {
    static func decode(_ string: String) -> String {
        var result = string
        let replacements: [String: String] = [
            "&nbsp;": "\u{00A0}", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}", "&mdash;": "\u{2014}",
            "&ndash;": "\u{2013}", "&hellip;": "\u{2026}", "&emsp;": "\u{2003}",
            "&ensp;": "\u{2002}", "&middot;": "\u{00B7}", "&bull;": "\u{2022}",
            "&copy;": "\u{00A9}", "&deg;": "\u{00B0}", "&times;": "\u{00D7}",
            "&eacute;": "é", "&egrave;": "è", "&ecirc;": "ê", "&euml;": "ë",
            "&aacute;": "á", "&agrave;": "à", "&uuml;": "ü", "&ouml;": "ö",
            "&ccedil;": "ç", "&ntilde;": "ñ", "&iexcl;": "\u{00A1}",
            "&iquest;": "\u{00BF}", "&sect;": "\u{00A7}", "&para;": "\u{00B6}"
        ]
        for (entity, value) in replacements {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return decodeNumericEntities(result)
    }

    private static func decodeNumericEntities(_ string: String) -> String {
        let pattern = "&#(x?[0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        var output = ""
        var lastEnd = string.startIndex
        for match in regex.matches(in: string, options: [], range: nsRange) {
            guard let range = Range(match.range, in: string),
                  let codeRange = Range(match.range(at: 1), in: string) else { continue }
            output += string[lastEnd..<range.lowerBound]
            let code = String(string[codeRange])
            let isHex = code.hasPrefix("x") || code.hasPrefix("X")
            let digits = isHex ? String(code.dropFirst()) : code
            if let value = isHex ? UInt32(digits, radix: 16) : UInt32(digits),
               let scalar = UnicodeScalar(value) {
                output += String(Character(scalar))
            }
            lastEnd = range.upperBound
        }
        output += string[lastEnd..<string.endIndex]
        return output
    }
}
