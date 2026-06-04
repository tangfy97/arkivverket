import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum MarkdownHTMLRenderer {
    static func render(_ markdown: String) -> String {
        let body = blocks(from: markdown)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              --text: #141412;
              --secondary: #6B6B68;
              --accent: #3C6F6B;
              --border: rgba(0,0,0,.06);
              --surface: #FEFDFB;
              --soft: #F4F3F0;
              --rule: rgba(0,0,0,.08);
            }
            html, body {
              margin: 0; padding: 0;
              background: var(--surface);
              color: var(--text);
              font: 15px/1.65 -apple-system, "SF Pro Text", sans-serif;
              -webkit-font-smoothing: antialiased;
            }
            body { padding: 48px 44px 64px; box-sizing: border-box; }
            h1 {
              font-size: clamp(36px, 6vw, 52px);
              line-height: 1.05;
              font-weight: 200;
              letter-spacing: -0.02em;
              margin: 0 0 6px;
              color: var(--text);
            }
            .subtitle {
              font-size: 13px;
              color: var(--secondary);
              margin: 0 0 40px;
              font-weight: 400;
            }
            h2 {
              font-size: 9.5px;
              font-weight: 700;
              letter-spacing: 0.14em;
              text-transform: uppercase;
              color: var(--accent);
              margin: 40px 0 14px;
              padding-bottom: 8px;
              border-bottom: 1px solid var(--rule);
            }
            h3 {
              font-size: 9px;
              font-weight: 600;
              letter-spacing: 0.10em;
              text-transform: uppercase;
              color: var(--secondary);
              margin: 28px 0 10px;
            }
            p { margin: 0 0 14px; max-width: 62ch; }
            strong { font-weight: 600; color: var(--text); }
            ul { margin: 0 0 18px; padding: 0 0 0 0; list-style: none; }
            li {
              margin: 5px 0;
              padding-left: 16px;
              position: relative;
            }
            li::before {
              content: "–";
              position: absolute;
              left: 0;
              color: var(--accent);
            }
            .table-wrap {
              overflow-x: auto;
              margin: 16px 0 28px;
            }
            table {
              width: 100%;
              border-collapse: collapse;
              font-size: 13px;
            }
            th {
              text-align: left;
              font-size: 9px;
              font-weight: 700;
              letter-spacing: 0.10em;
              text-transform: uppercase;
              color: var(--secondary);
              padding: 0 16px 10px 0;
              border-bottom: 1px solid var(--rule);
            }
            td {
              padding: 9px 16px 9px 0;
              vertical-align: top;
              border-bottom: 1px solid var(--border);
              color: var(--text);
            }
            tr:last-child td { border-bottom: 0; }
            code {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
              font-size: 0.88em;
              background: var(--soft);
              padding: 2px 6px;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func blocks(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var index = 0
        var subtitlePending = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                let classAttribute = subtitlePending ? " class=\"subtitle\"" : ""
                html.append("<p\(classAttribute)>\(inline(paragraph.joined(separator: " ")))</p>")
                subtitlePending = false
                paragraph.removeAll()
            }
        }

        func flushList() {
            if !listItems.isEmpty {
                html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
                listItems.removeAll()
            }
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if isTableStart(lines, at: index) {
                flushParagraph()
                flushList()
                subtitlePending = false
                let parsed = parseTable(lines, from: index)
                html.append(parsed.html)
                index = parsed.nextIndex
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                flushList()
                html.append("<h1>\(inline(String(line.dropFirst(2))))</h1>")
                subtitlePending = true
            } else if line.hasPrefix("## ") {
                flushParagraph()
                flushList()
                subtitlePending = false
                html.append("<h2>\(inline(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("### ") {
                flushParagraph()
                flushList()
                subtitlePending = false
                html.append("<h3>\(inline(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("- ") {
                flushParagraph()
                subtitlePending = false
                listItems.append(inline(String(line.dropFirst(2))))
            } else {
                flushList()
                if raw.hasSuffix("  ") {
                    flushParagraph()
                    let classAttribute = subtitlePending ? " class=\"subtitle\"" : ""
                    html.append("<p\(classAttribute)>\(inline(line))</p>")
                    subtitlePending = false
                } else {
                    paragraph.append(line)
                }
            }
            index += 1
        }

        flushParagraph()
        flushList()
        return html.joined(separator: "\n")
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && separator.range(of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#, options: .regularExpression) != nil
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (html: String, nextIndex: Int) {
        let headers = tableCells(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            rows.append(tableCells(line))
            index += 1
        }

        let head = headers.map { "<th>\(inline($0))</th>" }.joined()
        let body = rows.map { row in
            "<tr>\(row.map { "<td>\(inline($0))</td>" }.joined())</tr>"
        }.joined()
        return ("<div class=\"table-wrap\"><table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table></div>", index)
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func inline(_ text: String) -> String {
        var output = escape(text)
        output = output.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        return output
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
