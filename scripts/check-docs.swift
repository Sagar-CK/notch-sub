import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let listing = Process()
listing.executableURL = URL(fileURLWithPath: "/usr/bin/git")
listing.arguments = ["ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.md"]
let output = Pipe()
listing.standardOutput = output
try listing.run()
let data = output.fileHandleForReading.readDataToEndOfFile()
listing.waitUntilExit()
guard listing.terminationStatus == 0 else { exit(1) }
let files = String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
let links = try NSRegularExpression(pattern: #"\]\(([^\s)]+)(?:\s+"[^"]*")?\)|\bsrc="([^"]+)""#)
var failures = 0
for file in Set(files).sorted() {
  let source = root.appendingPathComponent(file)
  guard FileManager.default.fileExists(atPath: source.path) else { continue }
  let text = try String(contentsOf: source, encoding: .utf8)
  for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
    if line.contains("\u{2014}") {
      print("\(file):\(offset + 1): replace the em dash")
      failures += 1
    }
  }
  for match in links.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
    let capture = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
    guard let range = Range(capture, in: text) else { continue }
    let destination = String(text[range])
    if destination.hasPrefix("#") || destination.contains(":") { continue }
    let path =
      String(destination.split(separator: "#", maxSplits: 1)[0])
      .removingPercentEncoding ?? destination
    let target = source.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    if !FileManager.default.fileExists(atPath: target.path) {
      print("\(file): missing local link \(destination)")
      failures += 1
    }
  }
}
guard failures == 0 else { exit(1) }
print("Documentation checks passed")
