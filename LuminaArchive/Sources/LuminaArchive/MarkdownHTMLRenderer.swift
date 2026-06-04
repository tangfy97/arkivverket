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
              color-scheme: light;
              --text: #333333;
              --secondary: #737373;
              --accent: #5B8C8A;
              --border: rgba(0,0,0,.10);
              --surface: #ffffff;
              --soft: #F8F7F3;
            }
            html, body {
              margin: 0;
              padding: 0;
              background: var(--surface);
              color: var(--text);
              font: 14px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              line-height: 1.55;
            }
            body { padding: clamp(22px, 5vw, 42px); box-sizing: border-box; }
            h1 {
              font-size: clamp(28px, 7vw, 42px);
              line-height: 1.08;
              font-weight: 300;
              letter-spacing: 0;
              margin: 0 0 28px;
            }
            h2, h3 {
              color: var(--accent);
              font-size: 11px;
              line-height: 1.3;
              font-weight: 700;
              letter-spacing: .08em;
              text-transform: uppercase;
              margin: 32px 0 10px;
            }
            p { margin: 0 0 16px; max-width: 68ch; }
            strong { font-weight: 700; color: #222; }
            ul { margin: 0 0 18px 1.2em; padding: 0; }
            li { margin: 6px 0; }
            .table-wrap {
              overflow-x: auto;
              margin: 18px 0 24px;
              border: 1px solid var(--border);
              border-radius: 8px;
              background: var(--surface);
            }
            table {
              width: 100%;
              min-width: 420px;
              border-collapse: collapse;
              font-size: 13px;
            }
            th, td {
              padding: 10px 12px;
              text-align: left;
              vertical-align: top;
              border-bottom: 1px solid var(--border);
            }
            th {
              background: var(--soft);
              color: #2f4f4d;
              font-size: 11px;
              letter-spacing: .04em;
              text-transform: uppercase;
            }
            tr:last-child td { border-bottom: 0; }
            code {
              padding: 2px 5px;
              border-radius: 5px;
              background: var(--soft);
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: .92em;
            }
            @media (max-width: 420px) {
              body { padding: 22px; }
              table { min-width: 360px; }
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

        func flushParagraph() {
            if !paragraph.isEmpty {
                html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
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
                let parsed = parseTable(lines, from: index)
                html.append(parsed.html)
                index = parsed.nextIndex
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                flushList()
                html.append("<h1>\(inline(String(line.dropFirst(2))))</h1>")
            } else if line.hasPrefix("## ") {
                flushParagraph()
                flushList()
                html.append("<h2>\(inline(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("### ") {
                flushParagraph()
                flushList()
                html.append("<h3>\(inline(String(line.dropFirst(4))))</h3>")
            } else if line.hasPrefix("- ") {
                flushParagraph()
                listItems.append(inline(String(line.dropFirst(2))))
            } else {
                flushList()
                if raw.hasSuffix("  ") {
                    flushParagraph()
                    html.append("<p>\(inline(line))</p>")
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
